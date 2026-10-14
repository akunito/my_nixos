{ inputs, pkgs, rea-agents, uid }:
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
        environment.systemPackages = reaEnv.tools;
      })
    ];
  };
in
guest.config.microvm.declaredRunner
