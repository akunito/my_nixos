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
      # Rules from -> https://www.digitalocean.com/community/tutorials/iptables-essentials-common-firewall-rules-and-commands
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
      iptables -A INPUT -m conntrack --ctstate INVALID -j DROP

      # ================== SSH rules ==================
      # Allowing Incoming SSH from Specific IP address (if 192.168.0.0/24) or subnet (if 192.168.0.90/24)
      iptables -A INPUT -p tcp -s 192.168.0.90/24 --dport 22 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
      iptables -A INPUT -p tcp -s 192.168.0.91/24 --dport 22 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
      iptables -A OUTPUT -p tcp --sport 22 -m conntrack --ctstate ESTABLISHED -j ACCEPT

      # # ================== RDP rules ================== ( IT WORKS OK | DISABLED)
      # # Allowing Incoming RDP from Specific IP address (if 192.168.0.90/24)
      # iptables -A INPUT -p tcp -s 192.168.0.90/24 --dport 3389 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
      # # Allowing Incoming RDP from Specific IP address (if 192.168.0.91/24)
      # iptables -A INPUT -p tcp -s 192.168.0.91/24 --dport 3389 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
      # # Allowing Outgoing RDP responses (from port 3389)
      # iptables -A OUTPUT -p tcp --sport 3389 -m conntrack --ctstate ESTABLISHED -j ACCEPT

      # ================== VNC rules ================== ( For VM's VNC access )
      # Allowing Incoming VNC from Specific IP address (if 192.168.0.90/24)
      iptables -A INPUT -p tcp -s 192.168.0.90/24 --dport 5901 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
      # Allowing Incoming VNC from Specific IP address (if 192.168.0.91/24)
      iptables -A INPUT -p tcp -s 192.168.0.91/24 --dport 5901 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
      # Allowing Outgoing VNC responses (from port 5901)
      iptables -A OUTPUT -p tcp --sport 5901 -m conntrack --ctstate ESTABLISHED -j ACCEPT

    '';
  };
}