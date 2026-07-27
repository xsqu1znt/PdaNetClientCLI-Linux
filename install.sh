#!/usr/bin/env bash
set -Eeuo pipefail

readonly PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SYSTEM_SOURCE_DIR="$PROJECT_DIR/system/etc"
readonly USER_BIN_DIR="${PDANET_INSTALL_BIN_DIR:-$HOME/.local/bin}"
readonly USER_LIBEXEC_DIR="${PDANET_INSTALL_LIBEXEC_DIR:-$HOME/.local/libexec}"

info() {
  printf '==> %s\n' "$*"
}

ok() {
  printf '  OK  %s\n' "$*"
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: ./install.sh [OPTIONS]

Installs PdaNet and all of its runtime dependencies.

Options:
  --skip-packages  Do not install or verify distribution packages
  --skip-system    Do not install files under /etc
  -h, --help       Show this help
EOF
}

install_system_files() {
  (( EUID == 0 )) || die "--install-system must run as root."
  [[ -d "$SYSTEM_SOURCE_DIR" ]] || die "Missing system source directory."

  /usr/bin/install -D -m 0644 \
    "$SYSTEM_SOURCE_DIR/nftables-pdanet.nft" \
    /etc/nftables-pdanet.nft
  /usr/bin/install -D -m 0644 \
    "$SYSTEM_SOURCE_DIR/redsocks-pdanet.conf" \
    /etc/redsocks-pdanet.conf
  /usr/bin/install -D -m 0644 \
    "$SYSTEM_SOURCE_DIR/dnscrypt-proxy-pdanet.toml" \
    /etc/dnscrypt-proxy-pdanet.toml
  /usr/bin/install -D -m 0644 \
    "$SYSTEM_SOURCE_DIR/systemd/system/pdanet-redsocks.service" \
    /etc/systemd/system/pdanet-redsocks.service
  /usr/bin/install -D -m 0644 \
    "$SYSTEM_SOURCE_DIR/systemd/system/pdanet-dnscrypt.service" \
    /etc/systemd/system/pdanet-dnscrypt.service

  /usr/bin/systemctl daemon-reload
  ok "Installed system configuration and refreshed systemd."
}

if [[ "${1:-}" == "--install-system" ]]; then
  install_system_files
  exit
fi

package_is_installed() {
  local manager="$1"
  local package="$2"

  case "$manager" in
    dnf) rpm -q "$package" >/dev/null 2>&1 ;;
    apt) dpkg-query -W -f='${Status}' "$package" 2>/dev/null \
      | grep -qx 'install ok installed' ;;
    pacman) pacman -Q "$package" >/dev/null 2>&1 ;;
  esac
}

install_dependencies() {
  local manager manager_path package
  local -a packages=()
  local -a missing=()

  if command -v dnf >/dev/null 2>&1; then
    manager="dnf"
    manager_path="$(command -v dnf)"
    packages=(
      android-tools bash coreutils curl dnscrypt-proxy gawk glibc grep
      iproute nftables polkit python3 redsocks systemd util-linux
    )
  elif command -v apt-get >/dev/null 2>&1; then
    manager="apt"
    manager_path="$(command -v apt-get)"
    packages=(
      adb bash coreutils curl dnscrypt-proxy gawk grep iproute2 libc-bin
      nftables policykit-1 python3 redsocks systemd util-linux
    )
  elif command -v pacman >/dev/null 2>&1; then
    manager="pacman"
    manager_path="$(command -v pacman)"
    packages=(
      android-tools bash coreutils curl dnscrypt-proxy gawk glibc grep
      iproute2 nftables polkit python redsocks systemd util-linux
    )
  else
    die "Supported package manager not found (dnf, apt-get, or pacman)."
  fi

  for package in "${packages[@]}"; do
    package_is_installed "$manager" "$package" || missing+=("$package")
  done

  if (( ${#missing[@]} == 0 )); then
    ok "All required $manager packages are installed."
    return
  fi

  command -v pkexec >/dev/null 2>&1 \
    || die "pkexec is required to install system packages."
  info "Installing missing packages with $manager: ${missing[*]}"
  case "$manager" in
    dnf)
      pkexec "$manager_path" install -y "${missing[@]}"
      ;;
    apt)
      pkexec "$manager_path" update
      pkexec "$manager_path" install -y "${missing[@]}"
      ;;
    pacman)
      pkexec "$manager_path" -S --needed --noconfirm "${missing[@]}"
      ;;
  esac
  ok "Installed required system packages."
}

install_user_files() {
  local command_target="$USER_BIN_DIR/pdanet"
  local helper_target="$USER_LIBEXEC_DIR/pdanet-usb-helper"

  mkdir -p -- "$USER_BIN_DIR" "$USER_LIBEXEC_DIR"

  # GNU Stow may have left a symlink to the former dotfiles package.
  [[ ! -L "$command_target" ]] || unlink -- "$command_target"
  [[ ! -L "$helper_target" ]] || unlink -- "$helper_target"

  install -m 0755 "$PROJECT_DIR/bin/pdanet" "$command_target"
  install -m 0755 \
    "$PROJECT_DIR/libexec/pdanet-usb-helper" \
    "$helper_target"
  ok "Installed pdanet and its USB helper under $HOME/.local."
}

verify_installation() {
  local command_target="$USER_BIN_DIR/pdanet"
  local helper_target="$USER_LIBEXEC_DIR/pdanet-usb-helper"
  local required
  local -a required_commands=(
    adb awk bash curl dnscrypt-proxy getent grep ip journalctl logger nft
    nohup python3 redsocks resolvectl ss systemctl timeout
  )
  local -a missing_commands=()

  for required in "${required_commands[@]}"; do
    command -v "$required" >/dev/null 2>&1 \
      || missing_commands+=("$required")
  done
  (( ${#missing_commands[@]} == 0 )) \
    || die "Required commands are still missing: ${missing_commands[*]}"

  bash -n "$command_target"
  "$helper_target" --self-test
  ok "CLI syntax and USB protocol self-test passed."
}

skip_packages=0
skip_system=0
while (( $# > 0 )); do
  case "$1" in
    --skip-packages) skip_packages=1 ;;
    --skip-system) skip_system=1 ;;
    -h|--help)
      usage
      exit
      ;;
    *)
      usage >&2
      die "Unknown option: $1"
      ;;
  esac
  shift
done

info "Installing PdaNet"
(( skip_packages == 1 )) || install_dependencies
install_user_files

if (( skip_system == 0 )); then
  command -v pkexec >/dev/null 2>&1 \
    || die "pkexec is required to install files under /etc."
  info "Installing system configuration through PolicyKit"
  pkexec /usr/bin/bash "$PROJECT_DIR/install.sh" --install-system
fi

verify_installation

case ":$PATH:" in
  *":$USER_BIN_DIR:"*) ;;
  *) printf 'NOTE: Add %s to PATH to run pdanet directly.\n' "$USER_BIN_DIR" ;;
esac

printf '\nPdaNet installation complete.\n'
printf 'Safe USB check: pdanet usb test\n'
printf 'Enable USB:     pdanet usb\n'
printf 'Disable USB:    pdanet usb off\n'
