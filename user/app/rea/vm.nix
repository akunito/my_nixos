{ inputs, pkgs, rea-agents, uid, cacheDir, web ? false, extraModules ? [ ] }:
# extraModules: tests only (e.g. a root console for the escape test); empty in production.
# web = true: the F3a web lane — no target/, Chromium, and an HTTP proxy that exists only
# as a vsock relay to the per-session host squid (no NIC; libslirp 4.9.1 has
# CVE-2026-9539 and microvm.nix cannot express restrict=on — audit 2026-10-14).
# REA microVM for tiers 1-2 (AINF-408 F2). A user-run QEMU guest (microvm.nix):
# no NIC at all, its own store (storeOnDisk: the host /nix/store is NOT shared — it
# holds generated configs with secret-derived values), RAM-only root, QEMU -sandbox on.
# The case is shared over 9p from fixed per-user session paths that the launcher
# points at the case before boot; the guest mounts it at its own absolute path (REA
# only takes absolute paths). REA's MCP is relayed over vsock (CID 4242, port 5000).
# Prototype measurements and gotchas: docs/akunito/plans/rea-sandbox/aislamiento.md.
let
  reaEnv = import ./env.nix { inherit pkgs rea-agents; };
  # Playwright 1.58.2 always appends --no-sandbox (REA never passes chromiumSandbox) and
  # no proxy. This wrapper drops the former (namespace sandbox works in the guest) and
  # forces every request through the relay; QUIC, non-proxied WebRTC UDP and DoH are off.
  chromiumWrapper = pkgs.writeShellScript "rea-chromium" ''
    args=()
    for a in "$@"; do [ "$a" = --no-sandbox ] || args+=("$a"); done
    # Chromium stderr is also copied to out/ (reaches the case through the staging sweep):
    # REA only reports "execution_failure" when a launch fails. tee, not a redirect:
    # Playwright reads the DevTools endpoint from this stderr.
    exec 2> >(${pkgs.coreutils}/bin/tee -a /mnt/out/chromium.err >&2)
    exec ${pkgs.chromium}/bin/chromium "''${args[@]}" \
      --proxy-server=http://127.0.0.1:3128 --proxy-bypass-list='<-loopback>' \
      '--host-resolver-rules=MAP * ~NOTFOUND , EXCLUDE 127.0.0.1' \
      --disable-quic --force-webrtc-ip-handling-policy=disable_non_proxied_udp --dns-over-https-mode=off \
      --disable-background-networking --disable-component-update --disable-domain-reliability
  '';
  envAll = reaEnv.env // pkgs.lib.optionalAttrs web {
    REA_BROWSER_EXECUTABLE = "${chromiumWrapper}";
    HTTPS_PROXY = "http://127.0.0.1:3128";
    HTTP_PROXY = "http://127.0.0.1:3128";
    NODE_USE_ENV_PROXY = "1"; # Node >= 24: fetch (WebSourceMapFetcher) honours the proxy
  };
  run = "/run/user/${toString uid}/rea-vm";
  share = tag: ro: {
    proto = "9p"; inherit tag; source = "${run}/${tag}"; mountPoint = "/mnt/${tag}";
    readOnly = ro; securityModel = "none"; # writes land as the user running QEMU
  };
  # rea-triage, guest side: one report for every file in target/, then a proposed tier.
  # Runs as the unprivileged guest user; the target is never executed.
  triage = pkgs.writeShellScript "rea-triage-guest" ''
    export PATH=${pkgs.lib.makeBinPath (with pkgs; [ coreutils findutils gnugrep gnused file detect-it-easy yara upx osslsigncode ])}
    d=$(cat /mnt/ctl/case)
    export HOME=$d/work
    # diec does not find its signature databases on its own (everything "Unknown",
    # measured 2026-10-14); deep + heuristic scan.
    die_args="-d -u -D ${pkgs.detect-it-easy}/lib/die/db -E ${pkgs.detect-it-easy}/lib/die/db_extra -C ${pkgs.detect-it-easy}/lib/die/db_custom"
    worst=1; reject=""
    for f in "$d"/target/*; do
      [ -f "$f" ] || continue
      echo "== $(basename "$f")"
      echo "size:   $(stat -c %s "$f") bytes"
      echo "sha256: $(sha256sum "$f" | cut -d' ' -f1)"
      echo "file:   $(file -b "$f" | head -c 300)"
      echo "die:"; timeout 120 diec $die_args "$f" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -v "^\s*$" | head -20 | sed 's/^/  /'
      if upx -t -q "$f" >/dev/null 2>&1; then echo "upx:    packed (upx -t ok)"; worst=2; fi
      case "$(file -b "$f")" in
        *PE32*) echo "authenticode:"; timeout 60 osslsigncode verify -in "$f" 2>&1 | grep -E -i 'signature|subject|issuer|verif|no signature' | head -8 | sed 's/^/  /' ;;
      esac
      hits=$(timeout 120 yara -w -m ${./triage.yar} "$f" 2>/dev/null || true)
      if [ -n "$hits" ]; then
        echo "yara:"; echo "$hits" | sed 's/^/  /'
        echo "$hits" | grep -q 'action="reject"' && reject="$reject $(basename "$f")"
        echo "$hits" | grep -q 'action="tier2"' && worst=2
      fi
      if timeout 120 diec $die_args "$f" 2>/dev/null | grep -q -i -E 'protector|packer|obfuscat|crypt'; then worst=2; fi
    done
    echo
    if [ -n "$reject" ]; then
      echo "PROPOSAL: REJECT —$reject matches anti-cheat/DRM rules (out of scope). Diego decides; a match on a name can be a false positive."
    else
      echo "PROPOSAL: tier $worst (tier 0 only for builds of our own repos; Diego confirms)"
    fi
  '';
  guest = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      inputs.microvm.nixosModules.microvm
      ({ lib, ... }: {
        system.stateVersion = "26.05";
        networking.hostName = "rea-vm";
        networking.useDHCP = false;
        documentation.enable = false;
        microvm = {
          hypervisor = "qemu";
          vcpu = 4;
          mem = 6144;
          interfaces = [ ];
          storeOnDisk = true;
          vsock.cid = 4242;
          # out/ is NOT the case dir: a root-in-guest attacker could plant symlinks/setuid
          # files there for a host reader at any time (audit 2026-10-14). The guest writes a
          # staging dir in the user's tmpfs (also caps its size); rea-vm-mcp sweeps it and
          # moves it into the case only after QEMU has exited.
          shares = pkgs.lib.optional (!web) (share "target" true) ++ [
            { proto = "9p"; tag = "out"; source = "${run}/out-stage"; mountPoint = "/mnt/out"; readOnly = false; securityModel = "none"; }
            (share "ctl" true) ];
          # work/ (Ghidra temp, REA HOME) is a throwaway disk, not a host directory: nothing
          # from it ever reaches the host fs, and it cannot fill /home. rea-vm-mcp deletes
          # the image before every boot, so the runner mkfs'es a fresh one.
          volumes = [ { image = "${cacheDir}/work.img"; size = 16384; fsType = "ext4"; mountPoint = "/mnt/work"; autoCreate = true; } ];
          # Seccomp beyond the runner's `-sandbox on`: no exec, no privilege changes, no
          # resource-control syscalls (nothing here needs them: no slirp cmd:, no bridge helper).
          qemu.extraArgs = [ "-sandbox" "on,obsolete=deny,elevateprivileges=deny,spawn=deny,resourcecontrol=deny" ];
        };
        users.users.rea = { isNormalUser = true; uid = 1000; group = "users"; home = "/tmp"; };
        systemd.services.rea-case-mounts = {
          wantedBy = [ "multi-user.target" ];
          after = [ "local-fs.target" ];
          serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
          path = [ pkgs.util-linux pkgs.coreutils ];
          script = ''
            d=$(cat /mnt/ctl/case)
            case "$d" in /home/*/rea/cases/*) ;; *) echo "refusing case path $d" >&2; exit 1 ;; esac
            mkdir -p "$d/target" "$d/out" "$d/work"
            if [ -d /mnt/target ]; then
              mount --bind /mnt/target "$d/target"
              mount -o remount,bind,ro "$d/target"
            fi
            mount --bind /mnt/out "$d/out"
            chown rea:users /mnt/work /mnt/out
            mount --bind /mnt/work "$d/work"
          '';
        };
        systemd.services.rea-mcp = {
          wantedBy = [ "multi-user.target" ];
          after = [ "rea-case-mounts.service" ];
          requires = [ "rea-case-mounts.service" ];
          path = [ pkgs.socat pkgs.coreutils ];
          script = ''
            d=$(cat /mnt/ctl/case)
            {
              echo '#!${pkgs.bash}/bin/bash'
              ${lib.concatStrings (lib.mapAttrsToList (k: v: ''echo 'export ${k}="${v}"'
              '') envAll)}
              echo "export TMPDIR=$d/work HOME=$d/work"
              echo "exec ${rea-agents}/bin/rea mcp 2>>$d/out/rea-mcp.err"
            } > /run/rea-mcp.sh
            chmod 755 /run/rea-mcp.sh
            exec socat VSOCK-LISTEN:5000,reuseaddr,fork EXEC:/run/rea-mcp.sh,su=rea
          '';
        };
        systemd.services.rea-triage = {
          wantedBy = [ "multi-user.target" ];
          after = [ "rea-case-mounts.service" ];
          requires = [ "rea-case-mounts.service" ];
          path = [ pkgs.socat ];
          script = "exec socat VSOCK-LISTEN:5001,reuseaddr,fork EXEC:${triage},su=rea";
        };
        # Web lane: the only way out is 127.0.0.1:3128 -> vsock -> host squid (port in ctl/).
        systemd.services.rea-proxy-relay = lib.mkIf web {
          wantedBy = [ "multi-user.target" ];
          path = [ pkgs.socat pkgs.coreutils ];
          script = "exec socat TCP-LISTEN:3128,bind=127.0.0.1,reuseaddr,fork VSOCK-CONNECT:2:$(cat /mnt/ctl/proxy-port)";
        };
        environment.systemPackages = reaEnv.tools ++ lib.optional web pkgs.chromium;
      })
    ] ++ extraModules;
  };
in
# chromiumWrapper: the absolute path REA must be given as executable_path (web cases).
guest.config.microvm.declaredRunner // { inherit chromiumWrapper; }
