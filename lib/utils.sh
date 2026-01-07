#!/usr/bin/env bash
# =============================================================================
# Marzban Node Manager - Common Utilities
# =============================================================================
# Provides common helper functions for OS detection, validation, etc.
# =============================================================================

# Get the directory where the script is located
get_script_dir() {
    local source="${BASH_SOURCE[0]}"
    while [ -h "$source" ]; do
        local dir="$(cd -P "$(dirname "$source")" && pwd)"
        source="$(readlink "$source")"
        [[ $source != /* ]] && source="$dir/$source"
    done
    echo "$(cd -P "$(dirname "$source")" && pwd)"
}

# =============================================================================
# Constants
# =============================================================================

readonly MANAGER_NAME="marzban-node-manager"
readonly MANAGER_VERSION="1.0.3"
readonly MANAGER_INSTALL_DIR="/opt/marzban-node-manager"
readonly MANAGER_DATA_DIR="/var/lib/marzban-node-manager"
readonly MANAGER_DB_FILE="${MANAGER_DATA_DIR}/nodes.db"
readonly MANAGER_LOG_FILE="${MANAGER_DATA_DIR}/manager.log"

readonly NODE_INSTALL_DIR="/opt"
readonly NODE_DATA_BASE_DIR="/var/lib"

readonly MARZBAN_NODE_REPO="https://github.com/Gozargah/Marzban-node.git"
readonly MARZBAN_NODE_IMAGE="gozargah/marzban-node:latest"

readonly DEFAULT_SERVICE_PORT=62050
readonly DEFAULT_XRAY_API_PORT=62051
readonly PORT_INCREMENT=10

# =============================================================================
# System Checks
# =============================================================================

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This command must be run as root (use sudo)"
        exit 1
    fi
}

# Detect operating system
detect_os() {
    OS=""
    OS_VERSION=""
    
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS="$ID"
        OS_VERSION="$VERSION_ID"
    elif [[ -f /etc/lsb-release ]]; then
        . /etc/lsb-release
        OS="$DISTRIB_ID"
        OS_VERSION="$DISTRIB_RELEASE"
    elif [[ -f /etc/redhat-release ]]; then
        OS=$(cat /etc/redhat-release | awk '{print $1}')
        OS_VERSION=$(cat /etc/redhat-release | grep -oE '[0-9]+\.[0-9]+' | head -1)
    else
        print_error "Unable to detect operating system"
        exit 1
    fi
    
    # Normalize OS name to lowercase
    OS=$(echo "$OS" | tr '[:upper:]' '[:lower:]')
    
    export OS OS_VERSION
}

# Get package manager based on OS
get_package_manager() {
    detect_os
    
    case "$OS" in
        ubuntu|debian|linuxmint)
            PKG_MANAGER="apt-get"
            PKG_UPDATE="$PKG_MANAGER update -qq"
            PKG_INSTALL="$PKG_MANAGER install -y -qq"
            ;;
        centos|rhel|rocky|almalinux)
            PKG_MANAGER="yum"
            PKG_UPDATE="$PKG_MANAGER update -y -q"
            PKG_INSTALL="$PKG_MANAGER install -y -q"
            ;;
        fedora)
            PKG_MANAGER="dnf"
            PKG_UPDATE="$PKG_MANAGER update -y -q"
            PKG_INSTALL="$PKG_MANAGER install -y -q"
            ;;
        arch|manjaro)
            PKG_MANAGER="pacman"
            PKG_UPDATE="$PKG_MANAGER -Sy --noconfirm"
            PKG_INSTALL="$PKG_MANAGER -S --noconfirm"
            ;;
        opensuse*|sles)
            PKG_MANAGER="zypper"
            PKG_UPDATE="$PKG_MANAGER refresh"
            PKG_INSTALL="$PKG_MANAGER install -y"
            ;;
        *)
            print_error "Unsupported operating system: $OS"
            exit 1
            ;;
    esac
    
    export PKG_MANAGER PKG_UPDATE PKG_INSTALL
}

# Update package manager cache
update_package_manager() {
    get_package_manager
    print_info "Updating package manager..."
    eval "$PKG_UPDATE" >/dev/null 2>&1
}

# Install a package
install_package() {
    local package="$1"
    get_package_manager
    
    print_info "Installing $package..."
    if ! eval "$PKG_INSTALL $package" >/dev/null 2>&1; then
        print_error "Failed to install $package"
        return 1
    fi
    print_success "$package installed"
    return 0
}

# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Ensure a command is available, install if not
ensure_command() {
    local cmd="$1"
    local package="${2:-$1}"
    
    if ! command_exists "$cmd"; then
        install_package "$package"
    fi
}

# =============================================================================
# Docker Utilities
# =============================================================================

# Check if Docker is installed
is_docker_installed() {
    command_exists docker
}

# Check if Docker is running
is_docker_running() {
    docker info >/dev/null 2>&1
}

# Install Docker
install_docker() {
    print_info "Installing Docker..."
    
    if ! curl -fsSL https://get.docker.com | sh >/dev/null 2>&1; then
        print_error "Failed to install Docker"
        return 1
    fi
    
    # Start and enable Docker
    systemctl start docker >/dev/null 2>&1
    systemctl enable docker >/dev/null 2>&1
    
    print_success "Docker installed and started"
    return 0
}

# Detect docker compose command
# Note: Full implementation is in docker.sh, this is a basic fallback
detect_compose() {
    if docker compose version >/dev/null 2>&1; then
        COMPOSE_CMD="docker compose"
        export COMPOSE_CMD
        return 0
    fi
    
    print_error "Docker Compose V2 not found"
    print_info "Run the installer again or install manually"
    return 1
}

# =============================================================================
# Validation Functions
# =============================================================================

# Validate node name
validate_node_name() {
    local name="$1"
    
    # Check if empty
    if [[ -z "$name" ]]; then
        print_error "Node name cannot be empty"
        return 1
    fi
    
    # Check length
    if [[ ${#name} -lt 2 || ${#name} -gt 50 ]]; then
        print_error "Node name must be between 2 and 50 characters"
        return 1
    fi
    
    # Check for valid characters (alphanumeric, dash, underscore)
    if ! [[ "$name" =~ ^[a-zA-Z][a-zA-Z0-9_-]*$ ]]; then
        print_error "Node name must start with a letter and contain only alphanumeric characters, dashes, and underscores"
        return 1
    fi
    
    return 0
}

# Validate port number
validate_port() {
    local port="$1"
    
    # Check if numeric
    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        print_error "Port must be a number"
        return 1
    fi
    
    # Check range
    if [[ "$port" -lt 1 || "$port" -gt 65535 ]]; then
        print_error "Port must be between 1 and 65535"
        return 1
    fi
    
    # Check if not privileged (unless root)
    if [[ "$port" -lt 1024 && $EUID -ne 0 ]]; then
        print_warning "Ports below 1024 require root privileges"
    fi
    
    return 0
}

# Validate installation method
validate_method() {
    local method="$1"
    
    case "$method" in
        docker|normal)
            return 0
            ;;
        *)
            print_error "Invalid installation method. Must be 'docker' or 'normal'"
            return 1
            ;;
    esac
}

# =============================================================================
# File Operations
# =============================================================================

# Create directory if it doesn't exist
ensure_dir() {
    local dir="$1"
    
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir"
    fi
}

# Backup a file
backup_file() {
    local file="$1"
    local backup="${file}.backup.$(date +%Y%m%d_%H%M%S)"
    
    if [[ -f "$file" ]]; then
        cp "$file" "$backup"
        print_info "Backed up $file to $backup"
    fi
}

# Write content to file
write_file() {
    local file="$1"
    local content="$2"
    
    echo "$content" > "$file"
}

# Append content to file
append_file() {
    local file="$1"
    local content="$2"
    
    echo "$content" >> "$file"
}

# =============================================================================
# Certificate Handling
# =============================================================================

# Read certificate from file
read_cert_file() {
    local cert_path="$1"
    
    if [[ ! -f "$cert_path" ]]; then
        print_error "Certificate file not found: $cert_path"
        return 1
    fi
    
    cat "$cert_path"
}

# Read certificate interactively
read_cert_interactive() {
    # Print prompts to stderr so they display even when stdout is captured
    print_info "Please paste the client certificate content below." >&2
    print_info "Press Enter twice when done (empty line to finish):" >&2
    echo "" >&2
    
    local cert=""
    local line
    
    while IFS= read -r line; do
        if [[ -z "$line" ]]; then
            break
        fi
        cert+="$line"$'\n'
    done
    
    echo "$cert"
}

# Validate certificate format
validate_certificate() {
    local cert="$1"
    
    if [[ ! "$cert" =~ -----BEGIN\ CERTIFICATE----- ]]; then
        print_error "Invalid certificate format: missing BEGIN marker"
        return 1
    fi
    
    if [[ ! "$cert" =~ -----END\ CERTIFICATE----- ]]; then
        print_error "Invalid certificate format: missing END marker"
        return 1
    fi
    
    return 0
}

# Save certificate to file
save_certificate() {
    local cert="$1"
    local dest="$2"
    
    echo "$cert" > "$dest"
    chmod 600 "$dest"
}

# =============================================================================
# Network Utilities
# =============================================================================

# Get server's public IP
get_public_ip() {
    local ip=""
    
    # Try IPv4 first
    ip=$(curl -s -4 --connect-timeout 5 ifconfig.io 2>/dev/null)
    
    # Fall back to IPv6
    if [[ -z "$ip" ]]; then
        ip=$(curl -s -6 --connect-timeout 5 ifconfig.io 2>/dev/null)
    fi
    
    # Fall back to alternative services
    if [[ -z "$ip" ]]; then
        ip=$(curl -s --connect-timeout 5 icanhazip.com 2>/dev/null)
    fi
    
    echo "$ip"
}

# =============================================================================
# Logging
# =============================================================================

# Log message to file
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    ensure_dir "$(dirname "$MANAGER_LOG_FILE")"
    echo "[$timestamp] [$level] $message" >> "$MANAGER_LOG_FILE"
}

log_info() {
    log "INFO" "$1"
}

log_error() {
    log "ERROR" "$1"
}

log_warning() {
    log "WARNING" "$1"
}

# =============================================================================
# Systemd Utilities
# =============================================================================

# Check if systemd is available
is_systemd_available() {
    [[ -d /run/systemd/system ]]
}

# Reload systemd daemon
systemd_reload() {
    systemctl daemon-reload >/dev/null 2>&1
}

# =============================================================================
# Miscellaneous
# =============================================================================

# Generate random string
random_string() {
    local length="${1:-16}"
    tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c "$length"
}

# Check if running in interactive mode
is_interactive() {
    [[ -t 0 ]]
}

# Cleanup function for traps
cleanup() {
    # Remove any temp files
    rm -f /tmp/marzban-node-manager-* 2>/dev/null
}

# Set trap for cleanup
trap cleanup EXIT

