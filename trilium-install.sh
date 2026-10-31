#!/usr/bin/env bash
#
# Trilium Notes server installer / uninstaller (official server tarball)
# Detects distro, downloads the latest Linux server release, installs it,
# and creates a systemd service.
#
# Usage:
#   bash trilium-install.sh            # install
#   bash trilium-install.sh uninstall  # remove service, files, and optionally packages
#

set -euo pipefail

START_TIME=$(date +%s)
REPO="TriliumNext/Trilium"
DEFAULT_DIR="/opt/trilium"
DEFAULT_DATA="/opt/trilium/data"
SERVICE_NAME="trilium"
DEFAULT_PORT=8083
BIN_NAME="trilium.sh"

# ── helpers (logs to stderr) ───────────────────────────────────────────────
die() { echo -e "\n\033[1;31mError:\033[0m $*" >&2; exit 1; }
info() { echo -e "\033[1;34m==>\033[0m $*" >&2; }
ok() { echo -e "\033[1;32m==>\033[0m $*" >&2; }
warn() { echo -e "\033[1;33m==>\033[0m $*" >&2; }
prompt() { local var="$1" msg="$2" default="$3"; read -rp "$msg [$default]: " input; printf -v "$var" '%s' "${input:-$default}"; }
ask_yn() { local msg="$1" default="${2:-n}"; local ans; read -rp "$msg [y/N]: " ans; ans="${ans:-$default}"; [[ "$ans" =~ ^[Yy] ]]; }

elapsed() {
  local end=$(date +%s)
  local secs=$((end - START_TIME))
  printf '%dm %ds' $((secs/60)) $((secs%60))
}

# ── distro detection ───────────────────────────────────────────────────────
detect_distro() {
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    ID="${ID:-}"
    ID_LIKE="${ID_LIKE:-}"
  else
    die "Cannot detect distro (/etc/os-release missing)."
  fi

  case "$ID" in
    debian|ubuntu|linuxmint|pop|elementary|zorin) PKG="apt" ;;
    fedora|rhel|rocky|almalinux|centos|ol)         PKG="dnf" ;;
    arch|manjaro|endeavouros|garuda)               PKG="pacman" ;;
    opensuse*|sles)                                PKG="zypper" ;;
    alpine)                                        PKG="apk" ;;
    *)
      case "$ID_LIKE" in
        *debian*|*ubuntu*) PKG="apt" ;;
        *rhel*|*fedora*)   PKG="dnf" ;;
        *arch*)            PKG="pacman" ;;
        *suse*)            PKG="zypper" ;;
        *) die "Unsupported distro: $ID (ID_LIKE=$ID_LIKE). Supported: Debian/Ubuntu, Fedora/RHEL, Arch, openSUSE, Alpine." ;;
      esac
      ;;
  esac
  info "Detected: $ID ($PKG)"
}

# ── latest release check ───────────────────────────────────────────────────
check_latest() {
  info "Checking for latest release..."
  local api="https://api.github.com/repos/$REPO/releases/latest"
  TRI_LATEST=$(curl -fsSL "$api" 2>/dev/null | grep -oE '"tag_name":[[:space:]]*"[^"]+"' | head -1 | cut -d'"' -f4 || true)
  if [[ -n "${TRI_LATEST:-}" ]]; then
    ok "Latest Trilium: $TRI_LATEST"
  else
    warn "Could not query releases, using v0.106.1"
    TRI_LATEST="v0.106.1"
  fi
  echo
}

# ── packages ───────────────────────────────────────────────────────────────
install_packages() {
  info "Installing dependencies..."
  case "$PKG" in
    apt)
      sudo apt-get update -qq
      sudo DEBIAN_FRONTEND=noninteractive apt-get install -y curl ca-certificates tar xz-utils
      ;;
    dnf)
      sudo dnf install -y curl ca-certificates tar xz
      ;;
    pacman)
      sudo pacman -Sy --noconfirm curl ca-certificates tar xz
      ;;
    zypper)
      sudo zypper --non-interactive install curl ca-certificates tar xz
      ;;
    apk)
      sudo apk add --no-cache curl ca-certificates tar xz
      ;;
  esac
  ok "Dependencies ready."
}

# ── download and install ───────────────────────────────────────────────────
install_trilium() {
  local arch
  case "$(uname -m)" in
    x86_64|amd64) arch="x64" ;;
    aarch64|arm64) arch="arm64" ;;
    *) die "Unsupported arch: $(uname -m)" ;;
  esac

  local asset="TriliumNotes-Server-${TRI_LATEST}-linux-${arch}.tar.xz"
  local url="https://github.com/$REPO/releases/download/${TRI_LATEST}/${asset}"
  local tmp="/tmp/${asset}"

  info "Downloading $url"
  curl -fsSL -o "$tmp" -L "$url" || die "Download failed. Check the asset name for $TRI_LATEST."

  info "Installing to $INSTALL_DIR ..."
  sudo mkdir -p "$INSTALL_DIR"
  # extract; the tarball has a top-level dir
  local extract="/tmp/trilium-extract"
  rm -rf "$extract"
  mkdir -p "$extract"
  tar -xJf "$tmp" -C "$extract"
  # move contents into INSTALL_DIR
  local inner
  inner=$(find "$extract" -mindepth 1 -maxdepth 1 -type d | head -1)
  if [[ -n "$inner" ]]; then
    sudo rm -rf "$INSTALL_DIR/app"
    sudo mv "$inner" "$INSTALL_DIR/app"
  else
    die "Unexpected archive layout."
  fi
  rm -f "$tmp"
  rm -rf "$extract"

  sudo mkdir -p "$DATA_DIR"
  # make sure the launcher is executable
  sudo chmod +x "$INSTALL_DIR/app/$BIN_NAME" 2>/dev/null || true
  sudo find "$INSTALL_DIR/app" -type f -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
  # Fedora SELinux blocks executables in /opt
  if command -v getenforce >/dev/null 2>&1 && [[ "$(getenforce 2>/dev/null)" != "Disabled" ]]; then
    info "SELinux is enforcing — setting bin_t context on $INSTALL_DIR/app"
    sudo chcon -R -t bin_t "$INSTALL_DIR/app" || true
  fi
  sudo chown -R "$USER:$USER" "$INSTALL_DIR" "$DATA_DIR" 2>/dev/null || true
  ok "Files installed."
}

create_service() {
  local bin="$INSTALL_DIR/app/$BIN_NAME"
  [[ -x "$bin" ]] || die "Trilium launcher not found at $bin"

  if command -v systemctl >/dev/null 2>&1; then
    info "Creating systemd service..."
    sudo tee "/etc/systemd/system/${SERVICE_NAME}.service" >/dev/null <<UNIT
[Unit]
Description=Trilium Notes Server
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$INSTALL_DIR/app
Environment=TRILIUM_DATA_DIR=$DATA_DIR
Environment=TRILIUM_PORT=$PORT
ExecStart=$bin
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT
    sudo systemctl daemon-reload
    sudo systemctl enable --now "$SERVICE_NAME"
    ok "systemd service enabled and started."

    if systemctl is-active --quiet firewalld 2>/dev/null; then
      info "Opening firewall port ${PORT}/tcp..."
      sudo firewall-cmd --permanent --add-port="${PORT}/tcp" || true
      sudo firewall-cmd --reload || true
      ok "Firewall updated."
    fi

    sleep 3
    if ss -tlnp 2>/dev/null | grep -q ":${PORT} "; then
      ok "Web UI is listening on port ${PORT}"
    else
      warn "Web UI is not listening on port ${PORT} yet."
      warn "Last log lines:"
      sudo journalctl -u "$SERVICE_NAME" -n 20 --no-pager || true
    fi
  else
    warn "No systemd detected. Start manually with: TRILIUM_DATA_DIR=$DATA_DIR TRILIUM_PORT=$PORT $bin"
  fi
}

# ── uninstall ──────────────────────────────────────────────────────────────
remove_service() {
  info "Removing service..."
  if command -v systemctl >/dev/null 2>&1; then
    sudo systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    sudo systemctl disable "$SERVICE_NAME" 2>/dev/null || true
    sudo rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
    sudo systemctl daemon-reload
    ok "systemd service removed."
  fi
}

uninstall() {
  echo "Trilium uninstaller"
  echo "==================="
  detect_distro
  remove_service

  echo
  prompt INSTALL_DIR "Install directory to remove" "$DEFAULT_DIR"
  if [[ -d "$INSTALL_DIR" ]]; then
    if ask_yn "Remove install directory $INSTALL_DIR (includes notes data)?"; then
      sudo rm -rf "$INSTALL_DIR"
      ok "Directory removed."
    else
      info "Kept $INSTALL_DIR"
    fi
  else
    warn "Install directory $INSTALL_DIR not found."
  fi

  if ask_yn "Also remove packages (curl, tar, xz)? (may affect other software)"; then
    info "Removing packages..."
    case "$PKG" in
      apt)    sudo apt-get remove -y curl tar xz-utils || true ;;
      dnf)    sudo dnf remove -y curl tar xz || true ;;
      pacman) sudo pacman -Rns --noconfirm curl tar xz || true ;;
      zypper) sudo zypper --non-interactive remove curl tar xz || true ;;
      apk)    sudo apk del curl tar xz || true ;;
    esac
    ok "Package removal finished."
  fi

  echo
  ok "Uninstall finished in $(elapsed)"
}

# ── main ───────────────────────────────────────────────────────────────────
main() {
  local mode="${1:-install}"

  case "$mode" in
    uninstall|remove|--uninstall|-u)
      uninstall
      ;;
    install|"")
      echo "Trilium Notes installer (server tarball)"
      echo "========================================"
      detect_distro
      check_latest
      install_packages

      echo
      prompt INSTALL_DIR "Install directory" "$DEFAULT_DIR"
      prompt DATA_DIR "Data directory" "$DEFAULT_DATA"
      prompt PORT "Listen port" "$DEFAULT_PORT"

      [[ "$PORT" =~ ^[0-9]+$ ]] || die "Port must be a number."

      install_trilium
      create_service

      local ip
      ip=$(hostname -I 2>/dev/null | awk '{print $1}') || ip="localhost"

      echo
      ok "Done in $(elapsed)"
      echo
      echo "  Open:  http://${ip:-localhost}:${PORT}"
      echo "  Files: $INSTALL_DIR"
      echo "  Data:  $DATA_DIR"
      echo
      echo "First visit creates your account and password."
      echo
      echo "Service commands:"
      if command -v systemctl >/dev/null 2>&1; then
        echo "  sudo systemctl status $SERVICE_NAME"
        echo "  sudo systemctl restart $SERVICE_NAME"
      fi
      echo
      echo "To uninstall later: bash $0 uninstall"
      ;;
    *)
      die "Unknown option: $mode. Use: $0 [install|uninstall]"
      ;;
  esac
}

main "$@"
