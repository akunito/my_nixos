{ inputs, pkgs, rea-agents, uid, extraModules ? [ ] }:
# extraModules: tests only (e.g. a root console for the escape test); empty in production.
# REA microVM for tiers 1-2 (AINF-408 F2). A user-run QEMU guest (microvm.nix):
# no NIC at all, its own store (storeOnDisk: the host /nix/store is NOT shared — it
# holds generated configs with secret-derived values), RAM-only root, QEMU -sandbox on.
# The case is shared over 9p from fixed per-user session paths that the launcher
# points at the case before boot; the guest mounts it at its own absolute path (REA
# only takes absolute paths). REA's MCP is relayed over vsock (CID 4242, port 5000).
# Prototype measurements and gotchas: docs/akunito/plans/rea-sandbox/aislamiento.md.
let
  reaEnv = import ./env.nix { inherit pkgs rea-agents; };
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
          shares = [ (share "target" true) (share "out" false) (share "work" false) (share "ctl" true) ];
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
            mount --bind /mnt/target "$d/target"
            mount -o remount,bind,ro "$d/target"
            mount --bind /mnt/out "$d/out"
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
              '') reaEnv.env)}
              echo "export TMPDIR=$d/work HOME=$d/work"
              echo "exec ${rea-agents}/bin/rea mcp 2>>$d/work/rea-mcp.err"
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
        environment.systemPackages = reaEnv.tools;
      })
    ] ++ extraModules;
  };
in
guest.config.microvm.declaredRunner
