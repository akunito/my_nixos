# Sudo Configuration

Guide to configuring sudo for remote SSH connections and specific commands.

## Table of Contents

- [Overview](#overview)
- [Options](#options)
- [Remote SSH Connections](#remote-ssh-connections)
- [Command-Specific Rules](#command-specific-rules)
- [Security Recommendations](#security-recommendations)

## Overview

This configuration provides flexible sudo/doas setup with fine-grained control over which commands can be run without a password.

## Options

### Sudo Options Explained

From `sudo.nix` configuration:

```nix
options = [ "NOPASSWD" "SETENV" ];
```

These are specific sudo options that modify how permissions are applied:

- **NOPASSWD**: Allows the user to execute sudo commands without having to enter their password.
- **SETENV**: Enables the user to modify environment variables when using sudo, potentially useful for setting variables specific to certain commands or scripts.

## Remote SSH Connections

### The Problem

When connecting via SSH and needing to run sudo commands, you're prompted for a password, which is inconvenient for remote operations.

### Solutions

There are two options:

#### Option 1: SSH Password Forwarding (Recommended)

Configure your SSH client to pass the sudo password when connecting to the server.

**Reference**: [Stack Overflow - Sudo over SSH](https://stackoverflow.com/questions/10310299/what-is-the-proper-way-to-sudo-over-ssh)

**How it works**:
- SSH client forwards your password
- No need to configure NOPASSWD on server
- More secure than blanket NOPASSWD

#### Option 2: NOPASSWD for WHEEL Group (Not Recommended)

Set the sudoers file to allow NOPASSWD for the WHEEL user's group.

**Configuration**:
```nix
systemSettings = {
  sudoNOPASSWD = true;  # NOT recommended
};
```

**Why not recommended**:
- Less secure
- Allows all sudo commands without password
- Better to use specific command rules

## Command-Specific Rules

### Configuration

Instead of blanket NOPASSWD, use specific command rules:

```nix
systemSettings = {
  sudoEnable = true;
  sudoNOPASSWD = false;  # Don't enable blanket NOPASSWD
  sudoCommands = [
    {
      command = "/run/current-system/sw/bin/systemctl suspend";
      options = [ "NOPASSWD" ];
    }
    {
      command = "/run/current-system/sw/bin/restic";
      options = [ "NOPASSWD" "SETENV" ];
    }
    {
      command = "/run/current-system/sw/bin/rsync";
      options = [ "NOPASSWD" "SETENV" ];
    }
  ];
};
```

### How It Works

The `sudo.nix` module configures sudo based on these settings:

```nix
security.sudo = {
  enable = systemSettings.sudoEnable;
  extraRules = lib.mkIf (systemSettings.sudoNOPASSWD == true) [{
    users = [ "${userSettings.username}" ];
    commands = systemSettings.sudoCommands;
  }];
  extraConfig = with pkgs; ''
    Defaults:picloud secure_path="${lib.makeBinPath [
      systemd
    ]}:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin"
  '';
};
```

### Common Use Cases

#### System Control

```nix
{
  command = "/run/current-system/sw/bin/systemctl suspend";
  options = [ "NOPASSWD" ];
}
```

#### Backup Operations

```nix
{
  command = "/run/current-system/sw/bin/restic";
  options = [ "NOPASSWD" "SETENV" ];
}
```

#### File Operations

```nix
{
  command = "/run/current-system/sw/bin/rsync";
  options = [ "NOPASSWD" "SETENV" ];
}
```

## Security Recommendations

### 1. Prefer SSH Password Forwarding

For remote operations, use SSH password forwarding instead of NOPASSWD:

```sh
# Configure SSH client
ssh -o RequestTTY=yes user@server "sudo command"
```

### 2. Use Specific Command Rules

Instead of blanket NOPASSWD:

✅ **Good**:
```nix
sudoCommands = [
  { command = "/run/current-system/sw/bin/restic"; options = [ "NOPASSWD" "SETENV" ]; }
];
```

❌ **Bad**:
```nix
sudoNOPASSWD = true;  # Allows ALL commands without password
```

### 3. Use Polkit for GUI Applications

For GUI applications that need elevated privileges, use Polkit instead of sudo:

```nix
systemSettings = {
  polkitEnable = true;
  polkitRules = ''...'';
};
```

See [Polkit Configuration](polkit.md) for details.

### 4. Review Sudo Rules Regularly

- Review `sudoCommands` periodically
- Remove unused rules
- Verify rules are still needed
- Document why each rule exists

### 5. Use Wrapper Scripts

For complex operations, create wrapper scripts with specific sudo rules:

```nix
{
  command = "/run/wrappers/bin/restic";
  options = [ "NOPASSWD" ];
}
```

## Best Practices

### 1. Minimal Permissions

Grant only the minimum permissions needed:
- Specific commands, not all commands
- Specific users, not all users
- Specific options, not all options

### 2. Document Rules

Add comments explaining why each sudo rule exists:

```nix
sudoCommands = [
  # Allow suspend without password for power management
  {
    command = "/run/current-system/sw/bin/systemctl suspend";
    options = [ "NOPASSWD" ];
  }
  # Allow restic for automated backups
  {
    command = "/run/current-system/sw/bin/restic";
    options = [ "NOPASSWD" "SETENV" ];
  }
];
```

### 3. Test Incrementally

After adding sudo rules:
1. Test the specific command
2. Verify it works as expected
3. Check that other commands still require password
4. Review sudo logs

### 4. Monitor Sudo Usage

Check sudo logs regularly:

```sh
# View sudo logs
sudo journalctl -u sudo

# Check recent sudo usage
sudo grep sudo /var/log/auth.log
```

## Related Documentation

- [Security Guide](../security.md) - Overall security configuration
- [Polkit Configuration](polkit.md) - Alternative to sudo for GUI apps
- [Restic Backups](restic-backups.md) - Example of sudo usage

