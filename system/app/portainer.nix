{ config, pkgs, lib, ... }:

{
  # imports = [ portainer-on-nixos.nixosModules ];
  
  # environment.systemPackages = with pkgs; [
  #   portainer-on-nixos
  # ];
  services.portainer = {
    enable = true;        # Enable Portainer
    version = "latest";   # Use the latest version of Portainer
    openFirewall = false; # Don't open firewall by default
    port = 9443;          # Set Portainer port to 9443
  };

  # services.portainer = {
  #   enable = true; # Default false

  #   version = "latest"; # Default latest, you can check dockerhub for
  #                       # other tags.

  #   openFirewall = "false"; # Default false, set to 'true' if you want
  #                           # to be able to access via the port on
  #                           # something other than localhost. 

  #   port = 9443; # Sets the port number in both the firewall and
  #                 # the docker container port mapping itself.
  # };
}
