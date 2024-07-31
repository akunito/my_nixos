{ ... }:

{
  # Firewall
  # networking.firewall.enable = true;
  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # Firewall settings
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];
    allowedUDPPorts = [ 22 ];
    extraCommands = ''
      # ================== General rules ==================
      # Allowing Loopback Connections
      iptables -A INPUT -i lo -j ACCEPT
      iptables -A OUTPUT -o lo -j ACCEPT

      # Allowing Established and Related Incoming Connections
      iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
      
      # Allowing Established Outgoing Connections
      iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED -j ACCEPT

      # Allowing Internal Network to access External
      iptables -A FORWARD -i eth1 -o eth0 -j ACCEPT

      # Dropping Invalid Packets
      sudo iptables -A INPUT -m conntrack --ctstate INVALID -j DROP

      # ================== SSH rules ==================
      # Allowing Incoming SSH from Specific IP address (if 192.168.0.0/24) or subnet (if 192.168.0.90/24)
      iptables -A INPUT -p tcp -s 192.168.0.90/24 --dport 22 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
      iptables -A INPUT -p tcp -s 192.168.0.91/24 --dport 22 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
      iptables -A OUTPUT -p tcp --sport 22 -m conntrack --ctstate ESTABLISHED -j ACCEPT
    '';
  };
}