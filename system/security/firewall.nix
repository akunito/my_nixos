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
      # Assuming eth0 is your external network, and eth1 is your internal network, this will allow your internal to access the external:
      # iptables -A FORWARD -i eth0 -o eth1 -j ACCEPT
      # iptables -A FORWARD -i eth0 -o nm-bridge -j ACCEPT

      # Dropping Invalid Packets
      iptables -A INPUT -m conntrack --ctstate INVALID -j DROP

      # ================== Docker Bridge Network rules ==================
      # Allow Docker Bridge Network (docker0) Traffic:
      # This allows traffic between Docker containers and the host, and between containers themselves.
      # iptables -A INPUT -i docker0 -j ACCEPT
      # iptables -A FORWARD -o docker0 -j ACCEPT
      # iptables -A FORWARD -i docker0 -j ACCEPT
      # iptables -A OUTPUT -o docker0 -j ACCEPT
      
      # Allow NAT for Docker:
      # This allows Docker to perform NAT, which is required for outbound connections from containers to the external network.
      # iptables -t nat -A POSTROUTING -s 172.17.0.0/16 ! -o docker0 -j MASQUERADE
      
      # Allow Established and Related Connections:
      # This ensures that return traffic for existing connections is allowed.
      # iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

      # Prevent Docker from Interfering with Non-Docker Traffic:
      # This prevents Docker from interfering with existing non-Docker traffic, specifically by adding rules to manage Docker's network address translation and forwarding.
      # iptables -A FORWARD -o eth0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
      # iptables -A FORWARD -o eth0 -j DOCKER-USER
      # iptables -A FORWARD -i eth0 -o docker0 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
      # iptables -A FORWARD -i eth0 -o docker0 -j ACCEPT

      # Optional: Restrict External Access to Docker Containers:
      # If you want to restrict access to Docker containers from external networks, you can add specific rules to control which ports or IP ranges can access your containers.
      # For example, to allow access to a specific container on port 9443 (Portainer's default secure port) from a specific IP range:
      # iptables -A INPUT -p tcp -s 192.168.0.0/24 --dport 9443 -j ACCEPT

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

      # ================== Cockpit rules ================== ( For VM's access )
      # Allowing Incoming Cockpit from Specific IP address (if 192.168.0.90/24)
      iptables -A INPUT -p tcp -s 192.168.0.90/24 --dport 9090 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
      # Allowing Incoming Cockpit from Specific IP address (if 192.168.0.91/24)
      iptables -A INPUT -p tcp -s 192.168.0.91/24 --dport 9090 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
      # Allowing Outgoing Cockpit responses (from port 9090)
      iptables -A OUTPUT -p tcp --sport 9090 -m conntrack --ctstate ESTABLISHED -j ACCEPT

    '';
  };
}