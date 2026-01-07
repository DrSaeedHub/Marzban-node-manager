#!/usr/bin/env bash
# =============================================================================
# Marzban Node Manager - Installer Script
# =============================================================================
# Installs the Marzban Node Manager CLI tool and all dependencies
# 
# Usage:
#   bash <(curl -Ls https://raw.githubusercontent.com/DrSaeedHub/Marzban-node-manager/main/install-cli.sh)
#
# Options:
#   --name <name>     Custom CLI command name (default: marzban-node-manager)
#   --uninstall       Uninstall the CLI
#   --update          Update to latest version
# =============================================================================

set -e

# =============================================================================
# Configuration Variables (Customizable)
# =============================================================================

# CLI command name - change this to customize the command name
CLI_NAME="${CLI_NAME:-marzban-node-manager}"

# Installation directories
INSTALL_DIR="/opt/marzban-node-manager"
DATA_DIR="/var/lib/marzban-node-manager"
BIN_LINK="/usr/local/bin/${CLI_NAME}"

# Repository URL
REPO_URL="https://github.com/DrSaeedHub/Marzban-node-manager"
RAW_URL="https://raw.githubusercontent.com/DrSaeedHub/Marzban-node-manager/main"

# =============================================================================
# Color Codes
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# =============================================================================
# Output Functions
# =============================================================================

print_banner() {
    echo -e "${BOLD}${CYAN}"
    cat << 'EOF'
  __  __                _                     _   _           _      
 |  \/  | __ _ _ __ ___| |__   __ _ _ __     | \ | | ___   __| | ___ 
 | |\/| |/ _` | '__/_  | '_ \ / _` | '_ \    |  \| |/ _ \ / _` |/ _ \
 | |  | | (_| | |   / /| |_) | (_| | | | |   | |\  | (_) | (_| |  __/
 |_|  |_|\__,_|_|  /___|_.__/ \__,_|_| |_|   |_| \_|\___/ \__,_|\___|
                                                                      
   __  __                                   
  |  \/  | __ _ _ __   __ _  __ _  ___ _ __ 
  | |\/| |/ _` | '_ \ / _` |/ _` |/ _ | '__|
  | |  | | (_| | | | | (_| | (_| |  __| |   
  |_|  |_|\__,_|_| |_|\__,_|\__, |\___|_|   
                            |___/            
EOF
    echo -e "${RESET}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${BOLD}  Installer Script${RESET}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo ""
}

print_success() {
    echo -e "${GREEN}✓ $1${RESET}"
}

print_error() {
    echo -e "${RED}✗ $1${RESET}" >&2
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${RESET}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${RESET}"
}

print_step() {
    echo -e "${CYAN}[${1}]${RESET} ${2}"
}

# =============================================================================
# System Checks
# =============================================================================

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        echo "Please run: sudo bash $0"
        exit 1
    fi
}

detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS="$ID"
        OS_VERSION="$VERSION_ID"
    elif [[ -f /etc/lsb-release ]]; then
        . /etc/lsb-release
        OS="$DISTRIB_ID"
        OS_VERSION="$DISTRIB_RELEASE"
    else
        print_error "Unable to detect operating system"
        exit 1
    fi
    
    OS=$(echo "$OS" | tr '[:upper:]' '[:lower:]')
    
    print_info "Detected OS: $OS $OS_VERSION"
}

get_package_manager() {
    case "$OS" in
        ubuntu|debian|linuxmint)
            PKG_MANAGER="apt-get"
            PKG_UPDATE="apt-get update -qq"
            PKG_INSTALL="apt-get install -y -qq"
            ;;
        centos|rhel|rocky|almalinux)
            PKG_MANAGER="yum"
            PKG_UPDATE="yum update -y -q"
            PKG_INSTALL="yum install -y -q"
            ;;
        fedora)
            PKG_MANAGER="dnf"
            PKG_UPDATE="dnf update -y -q"
            PKG_INSTALL="dnf install -y -q"
            ;;
        arch|manjaro)
            PKG_MANAGER="pacman"
            PKG_UPDATE="pacman -Sy --noconfirm"
            PKG_INSTALL="pacman -S --noconfirm"
            ;;
        opensuse*|sles)
            PKG_MANAGER="zypper"
            PKG_UPDATE="zypper refresh"
            PKG_INSTALL="zypper install -y"
            ;;
        *)
            print_error "Unsupported operating system: $OS"
            exit 1
            ;;
    esac
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# =============================================================================
# Dependency Installation
# =============================================================================

update_package_manager() {
    print_step "1/7" "Updating package manager..."
    eval "$PKG_UPDATE" >/dev/null 2>&1
    print_success "Package manager updated"
}

install_package() {
    local package="$1"
    
    if ! eval "$PKG_INSTALL $package" >/dev/null 2>&1; then
        print_error "Failed to install $package"
        return 1
    fi
    return 0
}

install_sqlite() {
    print_step "2/7" "Checking SQLite..."
    
    if command_exists sqlite3; then
        print_success "SQLite already installed ($(sqlite3 --version | awk '{print $1}'))"
        return 0
    fi
    
    print_info "Installing SQLite..."
    
    case "$OS" in
        ubuntu|debian|linuxmint)
            install_package sqlite3
            ;;
        centos|rhel|rocky|almalinux|fedora)
            install_package sqlite
            ;;
        arch|manjaro)
            install_package sqlite
            ;;
        opensuse*|sles)
            install_package sqlite3
            ;;
    esac
    
    if command_exists sqlite3; then
        print_success "SQLite installed"
    else
        print_error "Failed to install SQLite"
        exit 1
    fi
}

install_curl() {
    print_step "3/7" "Checking curl..."
    
    if command_exists curl; then
        print_success "curl already installed"
        return 0
    fi
    
    print_info "Installing curl..."
    install_package curl
    
    if command_exists curl; then
        print_success "curl installed"
    else
        print_error "Failed to install curl"
        exit 1
    fi
}

install_jq() {
    print_step "4/7" "Checking jq..."
    
    if command_exists jq; then
        print_success "jq already installed"
        return 0
    fi
    
    print_info "Installing jq..."
    install_package jq
    
    if command_exists jq; then
        print_success "jq installed"
    else
        print_warning "jq installation failed (optional dependency)"
    fi
}

install_git() {
    print_step "5/7" "Checking git..."
    
    if command_exists git; then
        print_success "git already installed"
        return 0
    fi
    
    print_info "Installing git..."
    install_package git
    
    if command_exists git; then
        print_success "git installed"
    else
        print_warning "git installation failed (required for normal installation method)"
    fi
}

install_docker() {
    echo ""
    print_step "6/7" "Checking Docker..."
    
    if command_exists docker; then
        print_success "Docker already installed ($(docker --version | awk '{print $3}' | tr -d ','))"
        
        # Check if Docker is running
        if docker info >/dev/null 2>&1; then
            print_success "Docker is running"
        else
            print_warning "Docker is installed but not running"
            print_info "Starting Docker..."
            systemctl start docker >/dev/null 2>&1 || true
            systemctl enable docker >/dev/null 2>&1 || true
        fi
        
        # Ensure Docker's official repo is configured for compose plugin
        setup_docker_repo
    else
        print_info "Installing Docker from official repository..."
        
        # Setup Docker's official repo and install
        if setup_docker_repo && install_docker_from_repo; then
            systemctl start docker >/dev/null 2>&1 || true
            systemctl enable docker >/dev/null 2>&1 || true
            print_success "Docker installed and started"
        else
            # Fallback to convenience script
            print_warning "Repo setup failed, trying convenience script..."
            if curl -fsSL https://get.docker.com | sh >/dev/null 2>&1; then
                systemctl start docker >/dev/null 2>&1 || true
                systemctl enable docker >/dev/null 2>&1 || true
                print_success "Docker installed and started"
            else
                print_error "Failed to install Docker"
                print_info "You can still use the 'normal' installation method without Docker"
                return 0
            fi
        fi
    fi
    
    # Check and install Docker Compose V2
    install_docker_compose_v2
}

# Setup Docker's official APT/YUM repository
setup_docker_repo() {
    case "$OS" in
        ubuntu|debian|linuxmint)
            setup_docker_apt_repo
            ;;
        centos|rhel|rocky|almalinux|fedora)
            setup_docker_yum_repo
            ;;
        *)
            return 1
            ;;
    esac
}

setup_docker_apt_repo() {
    # Install prerequisites
    apt-get install -y ca-certificates curl gnupg >/dev/null 2>&1
    
    # Create keyrings directory
    install -m 0755 -d /etc/apt/keyrings
    
    # Remove old key if exists
    rm -f /etc/apt/keyrings/docker.gpg
    
    # Add Docker's official GPG key
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg 2>/dev/null | gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null
    chmod a+r /etc/apt/keyrings/docker.gpg
    
    # Determine the correct codename
    local codename=""
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        codename="${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}"
    fi
    
    # Fallback codenames for newer Ubuntu versions
    if [[ -z "$codename" ]] || ! curl -fsSL "https://download.docker.com/linux/ubuntu/dists/${codename}/Release" >/dev/null 2>&1; then
        # Try to detect from lsb_release
        codename=$(lsb_release -cs 2>/dev/null || echo "")
    fi
    
    # If still no codename or not supported, use a known working one
    if [[ -z "$codename" ]]; then
        codename="jammy"  # Ubuntu 22.04 as fallback
    fi
    
    # Add Docker's repo
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${codename} stable" > /etc/apt/sources.list.d/docker.list
    
    # Update package list
    apt-get update -qq >/dev/null 2>&1
    
    return 0
}

setup_docker_yum_repo() {
    # Install prerequisites
    yum install -y yum-utils >/dev/null 2>&1
    
    # Add Docker repo
    yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo >/dev/null 2>&1
    
    return 0
}

install_docker_from_repo() {
    case "$OS" in
        ubuntu|debian|linuxmint)
            apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null 2>&1
            ;;
        centos|rhel|rocky|almalinux|fedora)
            yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null 2>&1
            ;;
        *)
            return 1
            ;;
    esac
}

install_docker_compose_v2() {
    print_step "7/7" "Checking Docker Compose V2..."
    
    # Check if docker compose (V2) is available
    if docker compose version >/dev/null 2>&1; then
        local version=$(docker compose version --short 2>/dev/null)
        print_success "Docker Compose V2 already installed (${version})"
        return 0
    fi
    
    # Check for legacy docker-compose and warn about it
    if command_exists docker-compose; then
        local legacy_version=$(docker-compose version --short 2>/dev/null || echo "unknown")
        print_warning "Legacy docker-compose ${legacy_version} found"
        print_warning "This version has compatibility issues with newer Docker"
    fi
    
    print_info "Installing Docker Compose V2 plugin..."
    
    # Method 1: Try package manager (requires Docker's official repo)
    case "$OS" in
        ubuntu|debian|linuxmint)
            if apt-get install -y docker-compose-plugin >/dev/null 2>&1; then
                if docker compose version >/dev/null 2>&1; then
                    local version=$(docker compose version --short 2>/dev/null)
                    print_success "Docker Compose V2 installed via apt (${version})"
                    return 0
                fi
            fi
            ;;
        centos|rhel|rocky|almalinux|fedora)
            if yum install -y docker-compose-plugin >/dev/null 2>&1; then
                if docker compose version >/dev/null 2>&1; then
                    local version=$(docker compose version --short 2>/dev/null)
                    print_success "Docker Compose V2 installed via yum (${version})"
                    return 0
                fi
            fi
            ;;
    esac
    
    # Method 2: Direct download from GitHub
    print_info "Package not available, downloading from GitHub..."
    
    # Detect architecture
    local arch=$(uname -m)
    case "$arch" in
        x86_64)
            arch="x86_64"
            ;;
        aarch64|arm64)
            arch="aarch64"
            ;;
        armv7l|armhf)
            arch="armv7"
            ;;
        *)
            print_warning "Unknown architecture: $arch, trying x86_64"
            arch="x86_64"
            ;;
    esac
    
    local compose_url="https://github.com/docker/compose/releases/latest/download/docker-compose-linux-${arch}"
    
    # Try multiple plugin directories
    local plugin_dirs=(
        "/usr/local/lib/docker/cli-plugins"
        "/usr/lib/docker/cli-plugins"
        "/usr/libexec/docker/cli-plugins"
        "${HOME}/.docker/cli-plugins"
    )
    
    for plugin_dir in "${plugin_dirs[@]}"; do
        mkdir -p "$plugin_dir" 2>/dev/null || continue
        
        if curl -SL "$compose_url" -o "${plugin_dir}/docker-compose" 2>/dev/null; then
            chmod +x "${plugin_dir}/docker-compose"
            
            # Verify installation
            if docker compose version >/dev/null 2>&1; then
                local version=$(docker compose version --short 2>/dev/null)
                print_success "Docker Compose V2 installed (${version})"
                return 0
            fi
        fi
    done
    
    # Final check
    if docker compose version >/dev/null 2>&1; then
        print_success "Docker Compose V2 installed"
        return 0
    fi
    
    print_error "Failed to install Docker Compose V2"
    print_info "Please run these commands manually:"
    echo ""
    echo "  # Add Docker's official repo"
    echo "  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg"
    echo "  echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \$(lsb_release -cs) stable\" | sudo tee /etc/apt/sources.list.d/docker.list"
    echo "  sudo apt-get update && sudo apt-get install -y docker-compose-plugin"
    echo ""
    return 1
}

# =============================================================================
# CLI Installation
# =============================================================================

check_existing_installation() {
    if [[ -d "$INSTALL_DIR" || -f "$BIN_LINK" ]]; then
        return 0
    fi
    return 1
}

prompt_existing_installation() {
    echo ""
    print_warning "Marzban Node Manager appears to be already installed"
    echo ""
    echo "  What would you like to do?"
    echo "    1) Fresh install (remove existing and reinstall)"
    echo "    2) Update to latest version"
    echo "    3) Skip installation"
    echo ""
    
    read -p "  Enter choice [1-3]: " choice
    
    case "$choice" in
        1)
            print_info "Removing existing installation..."
            rm -rf "$INSTALL_DIR"
            rm -f "$BIN_LINK"
            return 0
            ;;
        2)
            do_update
            exit 0
            ;;
        3)
            print_info "Skipping installation"
            exit 0
            ;;
        *)
            print_error "Invalid choice"
            exit 1
            ;;
    esac
}

download_cli() {
    echo ""
    print_info "Downloading Marzban Node Manager..."
    
    mkdir -p "$INSTALL_DIR"
    mkdir -p "${INSTALL_DIR}/lib"
    mkdir -p "$DATA_DIR"
    
    # Download main script
    echo -n "  Downloading main script... "
    if curl -sSL "${RAW_URL}/marzban-node-manager.sh" -o "${INSTALL_DIR}/marzban-node-manager.sh" 2>/dev/null; then
        chmod +x "${INSTALL_DIR}/marzban-node-manager.sh"
        echo -e "${GREEN}✓${RESET}"
    else
        echo -e "${RED}✗${RESET}"
        print_error "Failed to download main script"
        return 1
    fi
    
    # Download library files
    local libs=("colors.sh" "utils.sh" "database.sh" "ports.sh" "docker.sh" "systemd.sh")
    
    for lib in "${libs[@]}"; do
        echo -n "  Downloading ${lib}... "
        if curl -sSL "${RAW_URL}/lib/${lib}" -o "${INSTALL_DIR}/lib/${lib}" 2>/dev/null; then
            echo -e "${GREEN}✓${RESET}"
        else
            echo -e "${RED}✗${RESET}"
            print_error "Failed to download ${lib}"
            return 1
        fi
    done
    
    # Set permissions
    chmod +x "${INSTALL_DIR}/lib/"*.sh
    
    print_success "Download complete"
}

create_symlink() {
    echo ""
    print_info "Creating symlink..."
    
    # Remove existing symlink if exists
    rm -f "$BIN_LINK"
    
    # Create new symlink
    ln -s "${INSTALL_DIR}/marzban-node-manager.sh" "$BIN_LINK"
    
    print_success "CLI available as: ${CLI_NAME}"
}

init_database() {
    echo ""
    print_info "Initializing database..."
    
    # Initialize database by sourcing utils and running init
    if command_exists sqlite3; then
        sqlite3 "${DATA_DIR}/nodes.db" <<EOF
CREATE TABLE IF NOT EXISTS nodes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT UNIQUE NOT NULL,
    service_port INTEGER NOT NULL,
    xray_api_port INTEGER NOT NULL,
    method TEXT NOT NULL DEFAULT 'docker',
    install_dir TEXT NOT NULL,
    data_dir TEXT NOT NULL,
    cert_file TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    status TEXT DEFAULT 'installed'
);

CREATE TABLE IF NOT EXISTS config (
    key TEXT PRIMARY KEY,
    value TEXT
);

CREATE INDEX IF NOT EXISTS idx_nodes_name ON nodes(name);
CREATE INDEX IF NOT EXISTS idx_nodes_service_port ON nodes(service_port);
CREATE INDEX IF NOT EXISTS idx_nodes_xray_api_port ON nodes(xray_api_port);
EOF
        print_success "Database initialized"
    else
        print_warning "Could not initialize database (sqlite3 not found)"
    fi
}

# =============================================================================
# Update Function
# =============================================================================

do_update() {
    echo ""
    print_info "Updating Marzban Node Manager..."
    
    if [[ ! -d "$INSTALL_DIR" ]]; then
        print_error "Marzban Node Manager is not installed"
        print_info "Run the installer without --update to install"
        exit 1
    fi
    
    download_cli
    
    print_success "Update complete!"
    echo ""
    print_info "Run '${CLI_NAME} --version' to verify"
}

# =============================================================================
# Uninstall Function
# =============================================================================

do_uninstall() {
    print_banner
    
    print_warning "This will uninstall Marzban Node Manager CLI"
    echo ""
    
    read -p "Are you sure? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_info "Uninstall cancelled"
        exit 0
    fi
    
    echo ""
    
    # Ask about database
    read -p "Remove database (node records will be lost)? [y/N]: " remove_db
    
    # Ask about managed nodes
    local node_count=0
    if [[ -f "${DATA_DIR}/nodes.db" ]] && command_exists sqlite3; then
        node_count=$(sqlite3 "${DATA_DIR}/nodes.db" "SELECT COUNT(*) FROM nodes;" 2>/dev/null || echo 0)
    fi
    
    local remove_nodes="n"
    if [[ "$node_count" -gt 0 ]]; then
        read -p "Remove all $node_count managed nodes? [y/N]: " remove_nodes
    fi
    
    echo ""
    
    # Remove nodes if requested
    if [[ "$remove_nodes" =~ ^[Yy]$ ]]; then
        print_info "Use '${CLI_NAME} uninstall-cli -y' to remove nodes"
        print_info "Running CLI uninstall..."
        "$BIN_LINK" uninstall-cli -y 2>/dev/null || true
    fi
    
    # Remove symlink
    print_info "Removing CLI symlink..."
    rm -f "$BIN_LINK"
    
    # Remove installation directory
    print_info "Removing installation directory..."
    rm -rf "$INSTALL_DIR"
    
    # Remove database if requested
    if [[ "$remove_db" =~ ^[Yy]$ ]]; then
        print_info "Removing database..."
        rm -rf "$DATA_DIR"
    fi
    
    print_success "Marzban Node Manager uninstalled"
}

# =============================================================================
# Main Installation
# =============================================================================

do_install() {
    print_banner
    
    print_info "Starting installation..."
    echo ""
    
    # Check for root
    check_root
    
    # Detect OS
    detect_os
    get_package_manager
    
    # Check for existing installation
    if check_existing_installation; then
        prompt_existing_installation
    fi
    
    echo ""
    print_info "Installing dependencies..."
    echo ""
    
    # Install dependencies
    update_package_manager
    install_sqlite
    install_curl
    install_jq
    install_git
    install_docker
    
    # Download and install CLI
    download_cli
    create_symlink
    init_database
    
    # Done!
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${BOLD}${GREEN}  Installation Complete!${RESET}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo ""
    echo -e "  ${CYAN}CLI Command:${RESET} ${BOLD}${CLI_NAME}${RESET}"
    echo -e "  ${CYAN}Install Dir:${RESET} ${INSTALL_DIR}"
    echo -e "  ${CYAN}Data Dir:${RESET}    ${DATA_DIR}"
    echo ""
    echo -e "  ${YELLOW}Quick Start:${RESET}"
    echo -e "    ${CLI_NAME} --help          Show help"
    echo -e "    ${CLI_NAME} install -n node1   Install a new node"
    echo -e "    ${CLI_NAME} status          Show node status"
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo ""
}

# =============================================================================
# Argument Parsing
# =============================================================================

ACTION="install"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --name)
            CLI_NAME="$2"
            BIN_LINK="/usr/local/bin/${CLI_NAME}"
            shift 2
            ;;
        --uninstall)
            ACTION="uninstall"
            shift
            ;;
        --update)
            ACTION="update"
            shift
            ;;
        -h|--help)
            echo "Marzban Node Manager Installer"
            echo ""
            echo "Usage:"
            echo "  bash install-cli.sh [options]"
            echo ""
            echo "Options:"
            echo "  --name <name>   Custom CLI command name (default: marzban-node-manager)"
            echo "  --update        Update to latest version"
            echo "  --uninstall     Uninstall the CLI"
            echo "  -h, --help      Show this help"
            echo ""
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# =============================================================================
# Run
# =============================================================================

case "$ACTION" in
    install)
        do_install
        ;;
    update)
        check_root
        do_update
        ;;
    uninstall)
        check_root
        do_uninstall
        ;;
esac

