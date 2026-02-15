# Polkit Configuration

Guide to configuring Polkit for fine-grained permission management.

## Table of Contents

- [Overview](#overview)
- [Configuration](#configuration)
- [Common Actions](#common-actions)
- [Example Rules](#example-rules)
- [Best Practices](#best-practices)

## Overview

Polkit (PolicyKit) provides a framework for managing privileges in a fine-grained way. It's particularly useful for GUI applications that need elevated permissions without requiring sudo passwords.

### When to Use Polkit

- **GUI Applications**: Applications that need system permissions
- **System Operations**: Reboot, shutdown, suspend
- **Service Management**: Starting/stopping systemd units
- **Command Execution**: Running specific commands with elevated privileges

### When NOT to Use Polkit

- **CLI Operations**: Use sudo for command-line operations
- **Script Automation**: Use sudo or systemd services
- **Full Root Access**: Use sudo for comprehensive system access

## Configuration

### Enable Polkit

In your flake configuration:

```nix
systemSettings = {
  polkitEnable = true;
  polkitRules = ''
    polkit.addRule(function(action, subject) {
      // Your rules here
    });
  '';
};
```

### Module Configuration

The `polkit.nix` module applies these settings:

```nix
{ lib, systemSettings, pkgs, authorizedKeys ? [], ... }:

{
  security.polkit = {
    enable = true;
    extraConfig = systemSettings.polkitRules;
  };
}
```

## Common Actions

### System Actions

- `org.freedesktop.login1.reboot` - System reboot
- `org.freedesktop.login1.reboot-multiple-sessions` - Reboot with multiple sessions
- `org.freedesktop.login1.power-off` - System shutdown
- `org.freedesktop.login1.power-off-multiple-sessions` - Shutdown with multiple sessions
- `org.freedesktop.login1.suspend` - System suspend
- `org.freedesktop.login1.suspend-multiple-sessions` - Suspend with multiple sessions
- `org.freedesktop.login1.logout` - User logout
- `org.freedesktop.login1.logout-multiple-sessions` - Logout with multiple sessions

### SystemD Actions

- `org.freedesktop.systemd1.manage-units` - Manage systemd units
  - `verb`: "start", "stop", "restart", etc.
  - `unit`: Unit name (e.g., "mnt-NFS_Backups.mount")

### Command Execution

- `org.freedesktop.policykit.exec` - Execute commands
  - `command`: Full path to command (e.g., "/run/current-system/sw/bin/rsync")

## Example Rules

### Basic Example

Allow users in "users" group to reboot and power off:

```nix
polkitRules = ''
  polkit.addRule(function(action, subject) {
    if (
      subject.isInGroup("users") && (
        action.id == "org.freedesktop.login1.reboot" ||
        action.id == "org.freedesktop.login1.power-off"
      )
    ) {
      return polkit.Result.YES;
    }
  });
'';
```

### Complete Example

From the configuration:

```nix
polkitRules = ''
  polkit.addRule(function(action, subject) {
    if (
      subject.isInGroup("users") && (
        // Allow reboot and power-off actions
        action.id == "org.freedesktop.login1.reboot" ||
        action.id == "org.freedesktop.login1.reboot-multiple-sessions" ||
        action.id == "org.freedesktop.login1.power-off" ||
        action.id == "org.freedesktop.login1.power-off-multiple-sessions" ||
        action.id == "org.freedesktop.login1.suspend" ||
        action.id == "org.freedesktop.login1.suspend-multiple-sessions" ||
        action.id == "org.freedesktop.login1.logout" ||
        action.id == "org.freedesktop.login1.logout-multiple-sessions" ||

        // Allow managing specific systemd units
        (action.id == "org.freedesktop.systemd1.manage-units" &&
          action.lookup("verb") == "start" &&
          action.lookup("unit") == "mnt-NFS_Backups.mount") ||

        // Allow running rsync and restic
        (action.id == "org.freedesktop.policykit.exec" &&
          (action.lookup("command") == "/run/current-system/sw/bin/rsync" ||
           action.lookup("command") == "/run/current-system/sw/bin/restic"))
      )
    ) {
      return polkit.Result.YES;
    }
  });
'';
```

### SystemD Unit Management

Allow starting a specific mount unit:

```javascript
(action.id == "org.freedesktop.systemd1.manage-units" &&
  action.lookup("verb") == "start" &&
  action.lookup("unit") == "mnt-NFS_Backups.mount")
```

### Command Execution

Allow running specific commands:

```javascript
(action.id == "org.freedesktop.policykit.exec" &&
  (action.lookup("command") == "/run/current-system/sw/bin/rsync" ||
   action.lookup("command") == "/run/current-system/sw/bin/restic"))
```

## Best Practices

### 1. Use Groups, Not Individual Users

✅ **Good**:
```javascript
subject.isInGroup("users")
```

❌ **Bad**:
```javascript
subject.user == "username"
```

### 2. Be Specific

Only allow the exact actions needed:

✅ **Good**:
```javascript
action.id == "org.freedesktop.login1.reboot"
```

❌ **Bad**:
```javascript
action.id.startsWith("org.freedesktop.login1")
```

### 3. Document Rules

Add comments explaining why each rule exists:

```javascript
// Allow reboot and power-off for users group
// Needed for GUI power management
if (action.id == "org.freedesktop.login1.reboot" || ...) {
  return polkit.Result.YES;
}
```

### 4. Test Incrementally

After adding rules:
1. Test the specific action
2. Verify it works as expected
3. Check that other actions still require authentication
4. Review polkit logs

### 5. Use Polkit Results

Available results:
- `polkit.Result.YES` - Allow without authentication
- `polkit.Result.NO` - Deny
- `polkit.Result.AUTH_SELF` - Allow after authenticating as self
- `polkit.Result.AUTH_ADMIN` - Allow after authenticating as administrator
- `polkit.Result.NOT_HANDLED` - Let other rules handle it

## Troubleshooting

### Rule Not Working

**Problem**: Polkit rule doesn't apply.

**Solutions**:
1. Check syntax (JavaScript)
2. Verify group membership: `groups`
3. Check action ID: Look in application logs
4. Review polkit logs: `journalctl -u polkit`

### Still Prompted for Password

**Problem**: Still asked for password despite rule.

**Solutions**:
1. Verify rule syntax
2. Check group membership
3. Verify action ID matches
4. Restart polkit service: `sudo systemctl restart polkit`

### Too Permissive

**Problem**: Rule allows more than intended.

**Solutions**:
1. Make conditions more specific
2. Add additional checks
3. Use `polkit.Result.AUTH_SELF` instead of `YES`
4. Review and test rules

## Related Documentation

- [Security Guide](../security.md) - Overall security configuration
- [Sudo Configuration](sudo.md) - Alternative for CLI operations
- [System Modules](../system-modules/security-wm-utils.md) - Polkit module details

