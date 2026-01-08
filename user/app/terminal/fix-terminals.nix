{ pkgs, ... }:

{
  # Python script to configure VS Code and Cursor terminal keybindings
  # Ensures proper Ctrl+C/V behavior in integrated terminals
  home.packages = [
    (pkgs.writers.writePython3Bin "fix-terminals" {
      libraries = [ ]; # No external libs needed, standard python is enough
      flakeIgnore = [ "E501" ]; # Optional: ignore linting line length
    } (builtins.readFile ../../../scripts/configure_terminals.py))
  ];
}

