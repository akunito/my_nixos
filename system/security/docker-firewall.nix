# Close the Docker firewall bypass.
#
# THE PROBLEM
# -----------
# `networking.firewall.allowedTCPPorts` only filters the INPUT chain. Traffic to
# a published container port is DNAT'd and then traverses FORWARD, not INPUT, so
# the NixOS firewall never sees it. Docker's own FORWARD policy is ACCEPT and it
# leaves the DOCKER-USER hook empty, which means every `ports:` entry in a
# docker-compose file that binds 0.0.0.0 (the default!) is reachable from the
# entire LAN — and from every Tailscale peer — regardless of what the NixOS
# firewall config says.
#
# On a dev workstation that typically means bare Postgres/Redis/app ports for
# work-in-progress stacks are silently exposed to the whole network.
#
# THE FIX
# -------
# Docker guarantees DOCKER-USER is consulted before any of its own rules, and it
# does not manage the contents. So we install:
#
#   1. RETURN for RELATED,ESTABLISHED  — keeps container egress + replies working
#   2. DROP NEW on each external interface — blocks unsolicited inbound
#   3. optional per-interface/port RETURN exceptions, inserted before (2)
#
# Container-to-container traffic and traffic from the host are untouched
# (they don't arrive on an external interface).
#
# This is a network-level backstop; binding compose ports to 127.0.0.1 is still
# the better habit. The backstop exists because compose files live in project
# repos that this config doesn't own.
{
  config,
  lib,
  pkgs,
  systemSettings,
  ...
}:

let
  enabled = systemSettings.dockerFirewallEnable or false;
  extIfaces = systemSettings.dockerFirewallExternalInterfaces or [ ];
  allowRules = systemSettings.dockerFirewallAllowedPorts or [ ];

  marker = "nixos-docker-fw";

  # Build the rule set for one iptables binary (v4 or v6).
  rulesFor = ipt: ''
    # DOCKER-USER may not exist yet if docker hasn't started — create it so the
    # rules survive a docker restart that happens after us.
    ${ipt} -N DOCKER-USER 2>/dev/null || true

    # Remove any rules we previously added (idempotent re-apply).
    while ${ipt} -S DOCKER-USER 2>/dev/null | ${pkgs.gnugrep}/bin/grep -q -- '${marker}'; do
      rule="$(${ipt} -S DOCKER-USER | ${pkgs.gnugrep}/bin/grep -m1 -- '${marker}' | ${pkgs.gnused}/bin/sed 's/^-A DOCKER-USER //')"
      # shellcheck disable=SC2086
      ${ipt} -D DOCKER-USER $rule || break
    done

    # Everything below inserts at position 1, so the chain ends up in the
    # REVERSE of the order written here. Insert bottom-of-chain rules first.

    # (3) Bottom: drop unsolicited inbound to containers from outside.
    ${lib.concatMapStringsSep "\n" (iface: ''
      ${ipt} -I DOCKER-USER 1 -i ${iface} -m conntrack --ctstate NEW \
        -m comment --comment '${marker}' -j DROP
    '') extIfaces}

    # (2) Middle: explicit exceptions. Must be inserted AFTER the DROPs so they
    # land above them — a RETURN below the DROP would never be reached.
    #
    # Match on --ctorigdstport, NOT --dport. DOCKER-USER lives in FORWARD, which
    # runs after nat/PREROUTING has already DNAT'd the packet: by then --dport is
    # the CONTAINER's internal port (3000/3001/...), not the published one, so
    # `--dport 3110` silently never matches. --ctorigdstport is the pre-DNAT
    # port, i.e. exactly the number written in the compose `ports:` mapping, and
    # it doesn't depend on the container's (dynamic) IP.
    ${lib.concatMapStringsSep "\n" (r: ''
      ${ipt} -I DOCKER-USER 1 -i ${r.interface} -p ${r.protocol or "tcp"} \
        -m conntrack --ctorigdstport ${toString r.port} \
        -m comment --comment '${marker}' -j RETURN
    '') allowRules}

    # (1) Top: established/related always returns — inserted last.
    ${ipt} -I DOCKER-USER 1 -m conntrack --ctstate RELATED,ESTABLISHED \
      -m comment --comment '${marker}' -j RETURN
  '';

  # Second path: docker's userland proxy.
  #
  # With EnableUserlandProxy (docker's default) each published port ALSO gets a
  # `docker-proxy` process listening on 0.0.0.0:<port> on the host. Traffic that
  # reaches it is delivered locally — INPUT, not FORWARD — so DOCKER-USER never
  # sees it and the rules above do nothing. And because system/app/tailscale.nix
  # sets `trustedInterfaces = [ "tailscale0" ]`, nixos-fw accepts that traffic
  # outright: measured from the VPS, DESK's dev Postgres answered on
  # 100.64.0.5:5432 even with DOCKER-USER fully armed.
  #
  # So we mirror the drops into nixos-fw. The published-port list is read back
  # out of docker's own nat chain, which means it tracks whatever is actually
  # running instead of a hand-maintained list.
  #
  # virtualisation.docker.daemon.settings.userland-proxy = false (set alongside
  # this module) removes the second path entirely, but only takes effect for
  # containers started after the next docker daemon restart — this keeps the
  # hole closed in the meantime, and stays harmless afterwards.
  inputGuard = ipt: ''
    while ${ipt} -S nixos-fw 2>/dev/null | ${pkgs.gnugrep}/bin/grep -q -- '${marker}'; do
      rule="$(${ipt} -S nixos-fw | ${pkgs.gnugrep}/bin/grep -m1 -- '${marker}' | ${pkgs.gnused}/bin/sed 's/^-A nixos-fw //')"
      # shellcheck disable=SC2086
      ${ipt} -D nixos-fw $rule || break
    done

    # Whatever docker currently publishes on the host, straight from its own
    # nat chain — no hand-maintained port list to drift.
    published="$(${ipt} -t nat -S DOCKER 2>/dev/null \
      | ${pkgs.gnugrep}/bin/grep -oE -- '--dport [0-9]+' \
      | ${pkgs.gnugrep}/bin/grep -oE '[0-9]+' \
      | ${pkgs.coreutils}/bin/sort -u)"

    # Exceptions are per-interface, so the skip list has to be too: a port
    # allowed on tailscale0 must still be dropped on bond0/eno1.
    ${lib.concatMapStringsSep "\n" (iface: ''
      for port in $published; do
        case " ${lib.concatMapStringsSep " " (r: toString r.port)
                  (lib.filter (r: r.interface == iface) allowRules)} " in
          *" $port "*) continue ;;
        esac
        ${ipt} -I nixos-fw 1 -i ${iface} -p tcp --dport "$port" \
          -m conntrack --ctstate NEW -m comment --comment '${marker}' -j DROP
      done
    '') extIfaces}
  '';

  applyScript = pkgs.writeShellScript "docker-user-firewall" ''
    set -u
    ${rulesFor "${pkgs.iptables}/bin/iptables"}
    ${inputGuard "${pkgs.iptables}/bin/iptables"}

    # Best-effort for IPv6 — containers publish on [::] too. Runs in a subshell
    # so a missing ip6 DOCKER-USER chain (docker with IPv6 disabled) can't fail
    # the whole unit.
    (
    ${rulesFor "${pkgs.iptables}/bin/ip6tables"}
    ) || true
  '';
in
{
  config = lib.mkIf enabled {
    assertions = [
      {
        assertion = extIfaces != [ ];
        message = "dockerFirewallEnable = true requires dockerFirewallExternalInterfaces to list the interfaces to block (e.g. [ \"bond0\" \"eno1\" \"tailscale0\" ]).";
      }
    ];

    systemd.services.docker-user-firewall = {
      description = "Block unsolicited inbound traffic to Docker containers (DOCKER-USER)";
      # Re-apply whenever docker or the host firewall comes up: both can recreate
      # the chains underneath us.
      after = [ "docker.service" "firewall.service" "network-online.target" ];
      wants = [ "network-online.target" ];
      partOf = [ "docker.service" ];
      wantedBy = [ "multi-user.target" "docker.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${applyScript}";
      };
    };

    # The NixOS firewall flushes and rebuilds on reload; re-assert afterwards.
    networking.firewall.extraCommands = ''
      ${applyScript} || true
    '';
  };
}
