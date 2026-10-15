{ inputs, pkgs, rea-agents, uid, cacheDir, web ? false, dynamic ? false, ghidraExtensions ? [ ], extraModules ? [ ] }:
# dynamic = true: the F3b lane — the target is executed (REA capture_process_scenario)
# with a fake network inside the guest: every name resolves to 10.99.0.1 / fd99::1,
# all TCP is redirected to a transparent mitmproxy that records it, other UDP/ICMP is
# logged; nothing can leave (still no NIC). Records land in <case>/out/net/.
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
  pwndbg = inputs.pwndbg.packages.${pkgs.stdenv.hostPlatform.system}.pwndbg.meta.pwndbgVenv;
  reaEnv = import ./env.nix { inherit pkgs rea-agents pwndbg ghidraExtensions; };
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
  } // pkgs.lib.optionalAttrs (!web) {
    HOPPER_LAUNCHER_PATH = "/opt/hopper/bin/Hopper";
    REA_JEB_MCP_URL = "http://127.0.0.1:8425/mcp"; # served only in --jeb cases (rea-jeb)
  } // pkgs.lib.optionalAttrs dynamic {
    # Executed targets inherit REA's environment: give them an ordinary userland too
    # (curl was "command not found" with the REA-only PATH, measured).
    PATH = reaEnv.env.PATH + ":/run/current-system/sw/bin";
  };
  run = "/run/user/${toString uid}/rea-vm";
  hopper = import ./hopper.nix { inherit pkgs; };
  jeb = import ./jeb.nix { inherit pkgs; };
  # REA's Linux Hopper demo path hardcodes /usr/bin/python3 (BridgeLauncher.ts) and the
  # helper loads libX11/libXtst by soname through ctypes; nixpkgs' glibc has no system
  # search path, so the wrapper supplies them. `exec -a` keeps argv[0] = /usr/bin/python3,
  # which REA's ownership check compares against the command line.
  hopperPython = pkgs.writeShellScript "rea-usr-bin-python3" ''
    export LD_LIBRARY_PATH=${pkgs.lib.makeLibraryPath [ pkgs.libx11 pkgs.libxtst ]}
    exec -a /usr/bin/python3 ${pkgs.python3}/bin/python3 "$@"
  '';
  # Dynamic lane: every HTTP(S) request gets an empty 200 from mitmproxy itself (the flow
  # is still recorded); nothing tries to reach an upstream that does not exist.
  fakeResponder = pkgs.writeText "rea-fake-responder.py" ''
    from mitmproxy import http

    def request(flow: http.HTTPFlow) -> None:
        flow.response = http.Response.make(200, b"", {"Content-Type": "text/plain"})
  '';
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
      echo "PROPOSAL: REJECT —$reject matches anti-cheat/DRM rules. Diego decides: overridable when he explicitly asks (2026-10-14); a match on a name can be a false positive."
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
          mem = 8192; # Ghidra (4 GiB heap) + an optional JEB (2 GiB, --jeb cases)
          interfaces = [ ];
          storeOnDisk = true;
          vsock.cid = 4242;
          # out/ is NOT the case dir: a root-in-guest attacker could plant symlinks/setuid
          # files there for a host reader at any time (audit 2026-10-14). The guest writes a
          # staging dir in the user's tmpfs (also caps its size); rea-vm-mcp sweeps it and
          # moves it into the case only after QEMU has exited.
          shares = pkgs.lib.optional (!web) (share "target" true) ++ [
            { proto = "9p"; tag = "out"; source = "${run}/out-stage"; mountPoint = "/mnt/out"; readOnly = false; securityModel = "none"; }
            (share "ctl" true) ]
            # Network records get their own share with REAL permissions ("mapped": guest
            # owner/mode kept in xattrs): out/ uses securityModel none, where every file looks
            # owned by uid 1000 = the user the target runs as, so a target could rewrite its
            # own records. Here only guest root writes.
            ++ pkgs.lib.optional dynamic { proto = "9p"; tag = "net"; source = "${run}/net-stage"; mountPoint = "/mnt/net"; readOnly = false; securityModel = "mapped"; };
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
          # Dynamic lane: no REA (so no execution) unless the fake network and its
          # recorders are up — a failed rea-fakenet once ran the target with no records.
          after = [ "rea-case-mounts.service" ] ++ lib.optionals dynamic [ "rea-fakenet.service" "rea-dnsmasq.service" "rea-mitm.service" ];
          requires = [ "rea-case-mounts.service" ] ++ lib.optionals dynamic [ "rea-fakenet.service" "rea-dnsmasq.service" "rea-mitm.service" ];
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
        # Dynamic lane: fake network. rea0 is a dummy interface holding the default routes,
        # so every destination "exists" locally; packets that are not redirected are dropped
        # by the dummy device.
        networking.nameservers = lib.mkIf dynamic [ "127.0.0.1" ];
        # dnsmasq and mitmproxy parse target-chosen bytes: unprivileged, so a bug in them
        # does not make the records forgeable (audit 2026-10-14).
        security.sudo.enable = false; # nobody here may use it; one setuid parser less
        users.users.mitm = lib.mkIf dynamic { isSystemUser = true; group = "mitm"; };
        users.groups.mitm = lib.mkIf dynamic { };
        # Keep out/net/ about the target only: no NTP lookups, no IPv6 router solicitations.
        services.timesyncd.enable = lib.mkIf dynamic false;
        boot.kernel.sysctl = lib.mkIf dynamic {
          "net.ipv6.conf.default.router_solicitations" = 0;
          "net.ipv6.conf.default.accept_ra" = 0;
        };
        systemd.services.rea-fakenet = lib.mkIf dynamic {
          wantedBy = [ "multi-user.target" ];
          after = [ "rea-case-mounts.service" ];
          requires = [ "rea-case-mounts.service" ];
          before = [ "rea-mcp.service" "rea-dnsmasq.service" "rea-mitm.service" ];
          serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
          path = [ pkgs.iproute2 pkgs.iptables pkgs.coreutils pkgs.util-linux ];
          script = ''
            chown root:root /mnt/net && chmod 755 /mnt/net
            # Pre-created for the unprivileged recorders: creating files on 9p is what failed
            # for a non-root mitmproxy (Permission denied, measured); writing an owned file works.
            install -o mitm -g mitm -m 644 /dev/null /mnt/net/dns.log
            install -o mitm -g mitm -m 644 /dev/null /mnt/net/mitm.log
            install -o mitm -g mitm -m 644 /dev/null /mnt/net/flows.mitm
            d=$(cat /mnt/ctl/case)
            mkdir -p "$d/out/net" && mount --bind /mnt/net "$d/out/net"
            ip link add rea0 type dummy
            ip addr add 10.99.0.1/24 dev rea0
            ip -6 addr add fd99::1/64 dev rea0 nodad
            ip link set rea0 up
            ip route add default dev rea0
            ip -6 route add default dev rea0
            # Match "not loopback", never `-o rea0`: 10.99.0.1/fd99::1 are LOCAL addresses, so
            # traffic to them leaves through lo and an `-o rea0` rule never saw it (measured:
            # every connect got "Connection refused"). Only the target's user (rea: REA runs it
            # as its own child) goes to the recorder.
            for t in "iptables 127.0.0.0/8 icmp" "ip6tables ::1/128 ipv6-icmp"; do
              set -- $t
              $1 -t nat -A OUTPUT -p tcp ! -d "$2" -m owner --uid-owner rea -j REDIRECT --to-ports 8888
              # a target with its own resolver (8.8.8.8 …) still lands in dnsmasq's log
              $1 -t nat -A OUTPUT -p udp ! -d "$2" --dport 53 -j REDIRECT --to-ports 53
              $1 -N rea-rec
              $1 -A OUTPUT ! -d "$2" -m owner --uid-owner rea -j rea-rec
              $1 -A rea-rec -p udp --dport 53 -j RETURN
              $1 -A rea-rec -p udp -j LOG --log-prefix "REA-UDP "
              $1 -A rea-rec -p udp -j RETURN
              $1 -A rea-rec -p "$3" -j LOG --log-prefix "REA-ICMP "
              $1 -A rea-rec -p "$3" -j RETURN
              # Anything else (SCTP, DCCP, UDP-Lite…) is dropped by the dummy but recorded.
              # Redirected TCP already has dst 127.0.0.1/::1 here and never gets this far.
              $1 -A rea-rec -j LOG --log-prefix "REA-OTHER "
            done
            # Everything needed is loaded by now (dummy, xt_owner, xt_LOG, nat, 9p, vsock):
            # no module autoload from socket() for the target (classic LPE surface).
            echo 1 > /proc/sys/kernel/modules_disabled
          '';
        };
        systemd.services.rea-dnsmasq = lib.mkIf dynamic {
          wantedBy = [ "multi-user.target" ];
          after = [ "rea-fakenet.service" ];
          requires = [ "rea-fakenet.service" ];
          script = ''
            exec ${pkgs.dnsmasq}/bin/dnsmasq -k --user=mitm --group=mitm --no-resolv --no-hosts \
              --listen-address=127.0.0.1,10.99.0.1 --bind-interfaces \
              --address=/#/10.99.0.1 --address=/#/fd99::1 \
              --log-queries --log-facility=/mnt/net/dns.log
          '';
        };
        systemd.services.rea-mitm = lib.mkIf dynamic {
          wantedBy = [ "multi-user.target" ];
          after = [ "rea-fakenet.service" ];
          requires = [ "rea-fakenet.service" ];
          serviceConfig = {
            User = "mitm"; Group = "mitm"; RuntimeDirectory = "mitm";
            NoNewPrivileges = true; CapabilityBoundingSet = ""; ProtectSystem = "strict";
            ProtectHome = "read-only"; ReadWritePaths = [ "/mnt/net" ];
          };
          script = ''
            # Default listen host = v4 AND v6 sockets. `--listen-host ::` gives a v6-only socket
            # (asyncio sets IPV6_V6ONLY) and every redirected IPv4 connect was refused (measured).
            # The fake responder answers every request itself: there is no upstream to reach.
            exec ${pkgs.mitmproxy}/bin/mitmdump --mode transparent --listen-port 8888 \
              --set confdir=/run/mitm --set connection_strategy=lazy --set showhost=true \
              -s ${fakeResponder} \
              -w /mnt/net/flows.mitm >> /mnt/net/mitm.log 2>&1
          '';
        };
        # The mitm CA is generated at boot (never in the store, which is readable); targets
        # that honour SSL_CERT_FILE can be pointed at this bundle to expose their TLS payloads.
        systemd.services.rea-ca-bundle = lib.mkIf dynamic {
          wantedBy = [ "multi-user.target" ];
          after = [ "rea-mitm.service" ];
          serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
          script = ''
            for _ in $(seq 1 60); do [ -s /run/mitm/mitmproxy-ca-cert.pem ] && break; sleep 0.5; done
            cat ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt /run/mitm/mitmproxy-ca-cert.pem > /run/rea-ca-bundle.pem
            chmod 644 /run/rea-ca-bundle.pem
          '';
          path = [ pkgs.coreutils ];
        };
        systemd.services.rea-packets = lib.mkIf dynamic {
          wantedBy = [ "multi-user.target" ];
          after = [ "rea-fakenet.service" ];
          path = [ pkgs.systemd pkgs.gnugrep ];
          script = ''
            journalctl -k -f -o short-iso | grep --line-buffered -E 'REA-(UDP|ICMP|OTHER)' >> /mnt/net/packets.log
          '';
        };
        # Hopper demo (F6): the vendor binary runs unpatched through nix-ld (REA pins its
        # sha256), with the paths REA hardcodes for a Linux install.
        programs.nix-ld = lib.mkIf (!web) {
          enable = true;
          libraries = with pkgs; [ qt6.qtbase libx11 libxrender libbsd libglvnd stdenv.cc.cc.lib zlib gmp ];
        };
        systemd.tmpfiles.rules = lib.optionals (!web) [
          "L+ /opt/hopper - - - - ${hopper}/opt/hopper"
          "L+ /usr/bin/python3 - - - - ${hopperPython}"
          "L+ /usr/bin/Xvfb - - - - ${pkgs.xvfb}/bin/Xvfb"
          "L+ /usr/bin/xauth - - - - ${pkgs.xauth}/bin/xauth"
          "L+ /usr/bin/unshare - - - - ${pkgs.util-linux}/bin/unshare"
        ];
        fonts.enableDefaultPackages = !web;
        # JEB CE headless with its MCP server, only when the case asked for it (ctl/jeb):
        # the EULA forbids making its output available to third parties (jeb.nix), and it
        # costs another 2 GiB of JVM. No NIC, so no update checks or telemetry either.
        systemd.services.rea-jeb = lib.mkIf (!web) {
          wantedBy = [ "multi-user.target" ];
          after = [ "rea-case-mounts.service" ];
          requires = [ "rea-case-mounts.service" ];
          before = [ "rea-mcp.service" ];
          unitConfig.ConditionPathExists = "/mnt/ctl/jeb";
          serviceConfig = { User = "rea"; Group = "users"; RuntimeDirectory = "rea-jeb"; Environment = "HOME=/run/rea-jeb"; };
          # ctl/jeb exists only once Diego accepted the EULA himself (rea.nix); --config is a
          # FILE, and headless JEB asks on stdin and quits without `.EulaAccepted = true`.
          script = ''
            printf '.EulaAccepted = true\n' > /run/rea-jeb/jeb-client.cfg
            exec ${pkgs.jdk21}/bin/java -Xmx2g -Djeb.sharedProgram -jar ${jeb}/opt/jeb/bin/app/jeb.jar \
              -c --mcp --interface=127.0.0.1 --port=8425 --config=/run/rea-jeb/jeb-client.cfg < /dev/null
          '';
        };
        environment.systemPackages = reaEnv.tools ++ lib.optional web pkgs.chromium
          ++ lib.optionals dynamic [ pkgs.dnsmasq pkgs.iproute2 pkgs.iptables pkgs.curl pkgs.wget pkgs.python3 pkgs.dnsutils pkgs.netcat-openbsd pkgs.strace pkgs.ltrace ];
      })
    ] ++ extraModules;
  };
in
# chromiumWrapper: the absolute path REA must be given as executable_path (web cases).
guest.config.microvm.declaredRunner // { inherit chromiumWrapper; }
