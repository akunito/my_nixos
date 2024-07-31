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
    allowedTCPPorts = [ 34389 ];
    # allowedUDPPorts = [ ... ];
    extraCommands = ''
      # Default deny incoming traffic
      iptables -P INPUT DROP
      iptables -P FORWARD DROP

      # Default allow outgoing traffic
      iptables -P OUTPUT ACCEPT

      # Allow HTTP and HTTPS traffic
      iptables -A INPUT -p tcp --dport 80 -j ACCEPT
      iptables -A INPUT -p tcp --dport 443 -j ACCEPT

      # Allow SSH from specific IP addresses to port 34389
      iptables -A INPUT -p tcp --dport 34389 -s 192.168.1.90 -j ACCEPT
      iptables -A INPUT -p tcp --dport 34389 -s 192.168.1.91 -j ACCEPT

      # Drop other connections to port 34389
      #iptables -A INPUT -p tcp --dport 34389 -j DROP

      # Ensure loopback traffic is allowed
      iptables -A INPUT -i lo -j ACCEPT

      # Allow established and related connections
      iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    '';
  };
}