# Sudo without password for remote SSH connections

## What should I do? 
There are two options to allow sudo without password for SSH users:

- (Recommended) To set your SSH client machine to pass the sudo password when connecting to the server. https://stackoverflow.com/questions/10310299/what-is-the-proper-way-to-sudo-over-ssh

- (Not recommended) To set the sudoers file to allow NOPASSWD for the WHEEL user's group.


## sudo options from sudoo.nix explained
If you have set in flake.nix to allow sudo without password for SSH users, here the explanation of the options:

options = [ "NOPASSWD" "SETENV" ];

These are specific sudo options that modify how the permissions are applied:
- NOPASSWD: Allows the user to execute sudo commands without having to enter their password.
- SETENV: Enables the user to modify environment variables when using sudo, potentially useful for setting variables specific to certain commands or scripts.
