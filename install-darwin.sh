#!/usr/bin/env bash
# install-darwin.sh - Complete macOS Nix setup from scratch
#
# Usage: ./install-darwin.sh [DOTFILES_DIR] [PROFILE]
# Example: ./install-darwin.sh ~/.dotfiles MACBOOK-KOMI
#
# This script:
# 1. Installs Nix package manager (if not present)
# 2. Installs Homebrew (for GUI casks)
# 3. Bootstraps nix-darwin
# 4. Backs up existing Homebrew packages
# 5. Applies the specified profile

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

DOTFILES_DIR="${1:-$HOME/.dotfiles}"
PROFILE="${2:-MACBOOK}"

log_info() {
  echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
  echo -e "${GREEN}[OK]${NC} $1"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

# ============================================================================
# PHASE 1: Install Nix Package Manager
# ============================================================================
install_nix() {
  if command -v nix &>/dev/null; then
    log_success "Nix already installed"
    return
  fi

  log_info "Installing Nix (Determinate Systems installer)..."
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install

  # Source nix
  if [ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
  fi

  log_success "Nix installed successfully"
}

# ============================================================================
# PHASE 2: Install Homebrew (needed for GUI casks)
# ============================================================================
install_homebrew() {
  if command -v brew &>/dev/null; then
    log_success "Homebrew already installed"
    return
  fi

  log_info "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  # Add Homebrew to PATH for this session
  if [ -f /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [ -f /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi

  log_success "Homebrew installed successfully"
}

# ============================================================================
# PHASE 3: Clone dotfiles (if not present)
# ============================================================================
clone_dotfiles() {
  if [ -d "$DOTFILES_DIR" ]; then
    log_success "Dotfiles directory exists at $DOTFILES_DIR"
    return
  fi

  log_info "Cloning dotfiles to $DOTFILES_DIR..."
  git clone https://github.com/akunito/dotfiles.git "$DOTFILES_DIR"
  log_success "Dotfiles cloned successfully"
}

# ============================================================================
# PHASE 4: Bootstrap nix-darwin
# ============================================================================
bootstrap_darwin() {
  if command -v darwin-rebuild &>/dev/null; then
    log_success "nix-darwin already installed"
    return
  fi

  log_info "Bootstrapping nix-darwin..."

  cd "$DOTFILES_DIR"

  # Link the profile-specific flake
  FLAKE_FILE="flake.${PROFILE}.nix"
  if [[ ! -f "$FLAKE_FILE" ]]; then
    log_error "Profile flake not found: $FLAKE_FILE"
    log_info "Available profiles:"
    ls -1 flake.*.nix 2>/dev/null || echo "  None found"
    exit 1
  fi

  ln -sf "$FLAKE_FILE" flake.nix
  log_info "Linked $FLAKE_FILE -> flake.nix"

  # Bootstrap nix-darwin
  nix run nix-darwin -- switch --flake ".#system"

  log_success "nix-darwin bootstrapped successfully"
}

# ============================================================================
# PHASE 5: Homebrew Migration (backup existing packages)
# ============================================================================
migrate_homebrew() {
  log_info "Checking for Homebrew packages to backup..."

  if command -v brew &>/dev/null; then
    BACKUP_FILE="${HOME}/.brew-backup-$(date +%Y%m%d).Brewfile"
    brew bundle dump --file="$BACKUP_FILE" --force 2>/dev/null || true
    log_success "Homebrew packages backed up to $BACKUP_FILE"

    echo ""
    log_info "Migration notes:"
    echo "  - Backed up Homebrew packages (can restore with: brew bundle install --file=$BACKUP_FILE)"
    echo "  - Nix will now manage most CLI tools"
    echo "  - Homebrew casks (GUI apps) continue via nix-darwin homebrew module"
    echo "  - To remove brew CLI tools: brew uninstall <package>"
  fi
}

# ============================================================================
# PHASE 6: Deploy profile
# ============================================================================
deploy_profile() {
  cd "$DOTFILES_DIR"

  FLAKE_FILE="flake.${PROFILE}.nix"
  if [[ ! -f "$FLAKE_FILE" ]]; then
    log_error "Profile flake not found: $FLAKE_FILE"
    exit 1
  fi

  # Symlink profile-specific flake
  ln -sf "$FLAKE_FILE" flake.nix
  log_success "Linked $FLAKE_FILE -> flake.nix"

  # Build and switch
  log_info "Building and switching to profile: $PROFILE"
  darwin-rebuild switch --flake ".#system"

  log_success "Darwin configuration applied"
}

# ============================================================================
# PHASE 7: Post-install verification
# ============================================================================
verify_install() {
  log_info "Verifying installation..."

  local errors=0

  # Check nix
  if command -v nix &>/dev/null; then
    log_success "nix: $(nix --version)"
  else
    log_error "nix not found in PATH"
    ((errors++))
  fi

  # Check darwin-rebuild
  if command -v darwin-rebuild &>/dev/null; then
    log_success "darwin-rebuild available"
  else
    log_error "darwin-rebuild not found in PATH"
    ((errors++))
  fi

  # Check home-manager
  if command -v home-manager &>/dev/null; then
    log_success "home-manager available"
  else
    log_warn "home-manager not in PATH (may need shell restart)"
  fi

  # Check Homebrew
  if command -v brew &>/dev/null; then
    log_success "brew: $(brew --version | head -n1)"
  else
    log_warn "brew not found in PATH"
  fi

  if [ $errors -gt 0 ]; then
    log_error "Installation completed with $errors errors"
    return 1
  fi

  return 0
}

# ============================================================================
# Main
# ============================================================================
main() {
  echo ""
  echo "========================================================================"
  echo " macOS Nix Setup - Profile: $PROFILE"
  echo "========================================================================"
  echo ""
  echo "Dotfiles directory: $DOTFILES_DIR"
  echo ""

  # Confirm
  read -p "Continue with installation? [y/N] " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_info "Installation cancelled"
    exit 0
  fi

  echo ""

  install_nix
  install_homebrew
  clone_dotfiles
  bootstrap_darwin
  migrate_homebrew
  deploy_profile

  echo ""

  if verify_install; then
    echo ""
    echo "========================================================================"
    echo " Setup complete!"
    echo "========================================================================"
    echo ""
    echo "Next steps:"
    echo "  1. Restart your terminal (or run: exec \$SHELL)"
    echo "  2. Verify Hammerspoon is running (menu bar icon)"
    echo "  3. Test Touch ID for sudo: sudo -v"
    echo ""
    echo "To rebuild after config changes:"
    echo "  darwin-rebuild switch --flake ~/.dotfiles#system"
    echo ""
  else
    log_error "Setup completed with errors. Please check the output above."
    exit 1
  fi
}

main "$@"
