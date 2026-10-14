# rea-net-mirror NETSTAGE DEST OUTSTAGE UNIT: while a dynamic-lane VM runs, copy its
# fake-network text logs from the net staging dir to <case>/out/net-live/ every 2 s, so the
# isolated session (which runs on the host) can read them before the VM is gone; and stop
# the VM's scope if the guest fills the host tmpfs (/run/user/1000 has no quota).
# The staging dirs are written by root-in-guest: every open is relative to a directory fd
# with O_NOFOLLOW, only an allow-list of names, only regular files, size-capped —
# a planted symlink, FIFO or huge file is skipped, never followed (audit rules 2026-10-14).
import os
import stat
import subprocess
import sys
import time

NAMES = ("dns.log", "mitm.log", "packets.log")
CAP = 8 << 20
BUDGET = 2 << 30
stage, dest, out_stage, unit = sys.argv[1:5]
os.makedirs(dest, mode=0o700, exist_ok=True)
stage_fd = os.open(stage, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
dest_fd = os.open(dest, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
seen = {}


def copy_one(name: str) -> None:
    fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=stage_fd)
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode):
            return
        key = (st.st_size, st.st_mtime_ns)
        if seen.get(name) == key:
            return
        if st.st_size > CAP:
            os.lseek(fd, st.st_size - CAP, os.SEEK_SET)
        data = os.read(fd, CAP)
    finally:
        os.close(fd)
    tmp = "." + name + ".tmp"
    out = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, 0o600, dir_fd=dest_fd)
    try:
        os.write(out, data)
    finally:
        os.close(out)
    os.rename(tmp, name, src_dir_fd=dest_fd, dst_dir_fd=dest_fd)
    seen[name] = key


def staged_bytes() -> int:
    total = 0
    for top in (stage, out_stage):
        for root, dirs, files in os.walk(top):
            for n in files:
                try:
                    total += os.lstat(os.path.join(root, n)).st_size
                except OSError:
                    pass
    return total


tick = 0
while True:
    for name in NAMES:
        try:
            copy_one(name)
        except FileNotFoundError:
            pass
        except OSError as e:
            print(f"rea-net-mirror: {name}: {e}", file=sys.stderr)
    tick += 1
    if tick % 5 == 0 and staged_bytes() > BUDGET:
        print("rea-net-mirror: guest output exceeds 2 GiB of host tmpfs, stopping the VM", file=sys.stderr)
        subprocess.run(["systemctl", "--user", "stop", unit + ".scope"], check=False)
        sys.exit(1)
    time.sleep(2)
