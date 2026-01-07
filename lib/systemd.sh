#!/usr/bin/env bash
# =============================================================================
# Marzban Node Manager - Systemd Operations
# =============================================================================
# Provides systemd service operations for normal (non-Docker) installation
# =============================================================================

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/colors.sh" 2>/dev/null || true

# =============================================================================
# Service File Generation
# =============================================================================

# Generate systemd service file content
# Usage: generate_service_file <node_name> <install_dir>
generate_service_file() {
    local node_name="$1"
    local install_dir="$2"
    
    cat <<EOF
[Unit]
Description=Marzban Node Service - ${node_name}
Documentation=https://github.com/Gozargah/Marzban-node
After=network.target nss-lookup.target

[Service]
Type=simple
User=root
WorkingDirectory=${install_dir}
ExecStart=${install_dir}/venv/bin/python ${install_dir}/main.py
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
}

# Generate .env file content
# Usage: generate_env_file <service_port> <xray_port> <data_dir> <cert_file> [inbounds]
generate_env_file() {
    local service_port="$1"
    local xray_port="$2"
    local data_dir="$3"
    local cert_file="$4"
    local inbounds="${5:-}"
    
    cat <<EOF
# Marzban Node Configuration
SERVICE_HOST=0.0.0.0
SERVICE_PORT=${service_port}
XRAY_API_HOST=0.0.0.0
XRAY_API_PORT=${xray_port}

# SSL Configuration
SSL_CERT_FILE=${data_dir}/ssl_cert.pem
SSL_KEY_FILE=${data_dir}/ssl_key.pem
SSL_CLIENT_CERT_FILE=${cert_file}

# Service Protocol
SERVICE_PROTOCOL=rest

# Xray Configuration
XRAY_EXECUTABLE_PATH=/usr/local/bin/xray
XRAY_ASSETS_PATH=/usr/local/share/xray

# Inbound Filter (comma-separated, case-sensitive)
INBOUNDS=${inbounds}

# Debug Mode
DEBUG=false
EOF
}

# Create systemd service file
create_service_file() {
    local node_name="$1"
    local install_dir="$2"
    local service_file="/etc/systemd/system/${node_name}.service"
    
    generate_service_file "$node_name" "$install_dir" > "$service_file"
    chmod 644 "$service_file"
    
    systemd_reload
    
    log_info "Created systemd service: $service_file"
    return 0
}

# Create .env file
create_env_file() {
    local install_dir="$1"
    local service_port="$2"
    local xray_port="$3"
    local data_dir="$4"
    local cert_file="$5"
    local inbounds="${6:-}"
    
    local env_file="${install_dir}/.env"
    
    generate_env_file "$service_port" "$xray_port" "$data_dir" "$cert_file" "$inbounds" > "$env_file"
    chmod 600 "$env_file"
    
    log_info "Created .env file: $env_file"
    return 0
}

# Update .env file ports
update_env_ports() {
    local env_file="$1"
    local service_port="$2"
    local xray_port="$3"
    
    if [[ ! -f "$env_file" ]]; then
        print_error "Env file not found: $env_file"
        return 1
    fi
    
    sed -i "s/^SERVICE_PORT=.*/SERVICE_PORT=${service_port}/" "$env_file"
    sed -i "s/^XRAY_API_PORT=.*/XRAY_API_PORT=${xray_port}/" "$env_file"
    
    log_info "Updated env file ports: SERVICE=$service_port, XRAY=$xray_port"
    return 0
}

# Update .env file inbounds
update_env_inbounds() {
    local env_file="$1"
    local inbounds="$2"
    
    if [[ ! -f "$env_file" ]]; then
        print_error "Env file not found: $env_file"
        return 1
    fi
    
    # Update or add INBOUNDS line
    if grep -q "^INBOUNDS=" "$env_file"; then
        sed -i "s/^INBOUNDS=.*/INBOUNDS=${inbounds}/" "$env_file"
    else
        echo "INBOUNDS=${inbounds}" >> "$env_file"
    fi
    
    log_info "Updated env file inbounds: $inbounds"
    return 0
}

# =============================================================================
# Systemd Service Operations
# =============================================================================

# Start a systemd node
systemd_node_start() {
    local node_name="$1"
    
    print_info "Starting service ${node_name}..."
    
    if systemctl start "$node_name" 2>&1; then
        print_success "Service ${node_name} started"
        log_info "Started service: $node_name"
        return 0
    else
        print_error "Failed to start service ${node_name}"
        log_error "Failed to start service: $node_name"
        return 1
    fi
}

# Stop a systemd node
systemd_node_stop() {
    local node_name="$1"
    
    print_info "Stopping service ${node_name}..."
    
    if systemctl stop "$node_name" 2>&1; then
        print_success "Service ${node_name} stopped"
        log_info "Stopped service: $node_name"
        return 0
    else
        print_error "Failed to stop service ${node_name}"
        log_error "Failed to stop service: $node_name"
        return 1
    fi
}

# Restart a systemd node
systemd_node_restart() {
    local node_name="$1"
    
    print_info "Restarting service ${node_name}..."
    
    if systemctl restart "$node_name" 2>&1; then
        print_success "Service ${node_name} restarted"
        log_info "Restarted service: $node_name"
        return 0
    else
        print_error "Failed to restart service ${node_name}"
        log_error "Failed to restart service: $node_name"
        return 1
    fi
}

# Enable service to start on boot
systemd_node_enable() {
    local node_name="$1"
    
    systemctl enable "$node_name" >/dev/null 2>&1
    log_info "Enabled service: $node_name"
}

# Disable service from starting on boot
systemd_node_disable() {
    local node_name="$1"
    
    systemctl disable "$node_name" >/dev/null 2>&1
    log_info "Disabled service: $node_name"
}

# Get service logs
systemd_node_logs() {
    local node_name="$1"
    local follow="${2:-false}"
    local lines="${3:-100}"
    
    if [[ "$follow" == "true" ]]; then
        journalctl -u "$node_name" -f
    else
        journalctl -u "$node_name" -n "$lines" --no-pager
    fi
}

# =============================================================================
# Service Status
# =============================================================================

# Check if a systemd node is running
systemd_node_is_running() {
    local node_name="$1"
    
    systemctl is-active --quiet "$node_name"
}

# Check if service exists
systemd_node_exists() {
    local node_name="$1"
    
    [[ -f "/etc/systemd/system/${node_name}.service" ]]
}

# Get service status
systemd_node_status() {
    local node_name="$1"
    
    systemctl status "$node_name" --no-pager 2>/dev/null
}

# Get service PID
systemd_node_get_pid() {
    local node_name="$1"
    
    systemctl show -p MainPID --value "$node_name" 2>/dev/null
}

# Get detailed service info
systemd_node_info() {
    local node_name="$1"
    
    systemctl show "$node_name" 2>/dev/null
}

# =============================================================================
# Installation and Removal
# =============================================================================

# Install Xray core for normal installation
install_xray_core() {
    local install_path="${1:-/usr/local/bin}"
    
    print_info "Installing Xray core..."
    
    # Download and run the official install script
    if curl -L https://github.com/Gozargah/Marzban-scripts/raw/master/install_latest_xray.sh | bash; then
        print_success "Xray core installed"
        log_info "Installed Xray core"
        return 0
    else
        print_error "Failed to install Xray core"
        log_error "Failed to install Xray core"
        return 1
    fi
}

# Setup Python virtual environment
setup_venv() {
    local install_dir="$1"
    
    print_info "Setting up Python virtual environment..."
    
    # Ensure python3-venv is installed
    if ! command_exists python3; then
        install_package python3
    fi
    
    # Install venv package if needed
    if ! python3 -m venv --help >/dev/null 2>&1; then
        install_package python3-venv
    fi
    
    # Create venv
    python3 -m venv "${install_dir}/venv"
    
    # Upgrade pip
    "${install_dir}/venv/bin/pip" install --upgrade pip >/dev/null 2>&1
    
    log_info "Created virtual environment at ${install_dir}/venv"
    return 0
}

# Install Python dependencies
install_python_deps() {
    local install_dir="$1"
    local requirements="${install_dir}/requirements.txt"
    
    if [[ ! -f "$requirements" ]]; then
        print_error "requirements.txt not found"
        return 1
    fi
    
    print_info "Installing Python dependencies..."
    
    if "${install_dir}/venv/bin/pip" install -r "$requirements" >/dev/null 2>&1; then
        print_success "Python dependencies installed"
        log_info "Installed Python dependencies"
        return 0
    else
        print_error "Failed to install Python dependencies"
        log_error "Failed to install Python dependencies"
        return 1
    fi
}

# Install a node via normal (systemd) method
# Usage: systemd_node_install <node_name> <service_port> <xray_port> <cert_content> [inbounds]
systemd_node_install() {
    local node_name="$1"
    local service_port="$2"
    local xray_port="$3"
    local cert_content="$4"
    local inbounds="${5:-}"
    
    local install_dir="${NODE_INSTALL_DIR}/${node_name}"
    local data_dir="${NODE_DATA_BASE_DIR}/${node_name}"
    local cert_file="${data_dir}/ssl_client_cert.pem"
    
    # Check systemd availability
    if ! is_systemd_available; then
        print_error "Systemd is not available on this system"
        return 1
    fi
    
    # Step 1: Create directories
    print_step "1/7" "Creating directories..."
    ensure_dir "$install_dir"
    ensure_dir "$data_dir"
    
    # Step 2: Clone Marzban-node repository
    print_step "2/7" "Cloning Marzban-node repository..."
    if [[ -d "${install_dir}/.git" ]]; then
        # Update existing repo
        cd "$install_dir" && git pull --quiet
    else
        # Clone fresh
        if ! git clone --quiet "$MARZBAN_NODE_REPO" "$install_dir" 2>&1; then
            print_error "Failed to clone repository"
            return 1
        fi
    fi
    
    # Step 3: Setup Python virtual environment
    print_step "3/7" "Setting up Python environment..."
    setup_venv "$install_dir"
    
    # Step 4: Install Python dependencies
    print_step "4/7" "Installing dependencies..."
    install_python_deps "$install_dir"
    
    # Step 5: Install Xray core if not present
    print_step "5/7" "Checking Xray core..."
    if ! command_exists xray; then
        install_xray_core
    else
        print_info "Xray core already installed"
    fi
    
    # Step 6: Save certificate and create config
    print_step "6/7" "Configuring node..."
    echo "$cert_content" > "$cert_file"
    chmod 600 "$cert_file"
    
    create_env_file "$install_dir" "$service_port" "$xray_port" "$data_dir" "$cert_file" "$inbounds"
    
    # Step 7: Create and start systemd service
    print_step "7/7" "Setting up systemd service..."
    create_service_file "$node_name" "$install_dir"
    systemd_node_enable "$node_name"
    systemd_node_start "$node_name"
    
    return $?
}

# Uninstall a systemd node
systemd_node_uninstall() {
    local node_name="$1"
    local install_dir="$2"
    local data_dir="$3"
    local remove_data="${4:-false}"
    
    local service_file="/etc/systemd/system/${node_name}.service"
    
    # Stop service if running
    if systemd_node_is_running "$node_name"; then
        print_info "Stopping service..."
        systemd_node_stop "$node_name"
    fi
    
    # Disable and remove service
    if systemd_node_exists "$node_name"; then
        print_info "Removing systemd service..."
        systemd_node_disable "$node_name"
        rm -f "$service_file"
        systemd_reload
    fi
    
    # Remove install directory
    if [[ -d "$install_dir" ]]; then
        print_info "Removing install directory..."
        rm -rf "$install_dir"
    fi
    
    # Optionally remove data directory
    if [[ "$remove_data" == "true" && -d "$data_dir" ]]; then
        print_info "Removing data directory..."
        rm -rf "$data_dir"
    fi
    
    log_info "Uninstalled systemd node: $node_name"
    return 0
}

# =============================================================================
# Status for Multiple Nodes
# =============================================================================

# Get status of all systemd nodes
systemd_nodes_status() {
    local nodes="$1"  # Pipe-separated list from database
    
    while IFS='|' read -r name service_port xray_port method install_dir data_dir status; do
        if [[ "$method" != "normal" ]]; then
            continue
        fi
        
        local running="down"
        local pid="-"
        
        if systemd_node_is_running "$name"; then
            running="up"
            pid=$(systemd_node_get_pid "$name")
            pid="PID:$pid"
        fi
        
        echo "${name}|${service_port}|${xray_port}|${running}|${pid}"
    done <<< "$nodes"
}

# =============================================================================
# Config Edit
# =============================================================================

# Edit .env file interactively
systemd_node_edit_env() {
    local install_dir="$1"
    local env_file="${install_dir}/.env"
    
    if [[ ! -f "$env_file" ]]; then
        print_error "Env file not found: $env_file"
        return 1
    fi
    
    # Determine editor
    local editor="${EDITOR:-nano}"
    if ! command_exists "$editor"; then
        editor="vi"
    fi
    if ! command_exists "$editor"; then
        print_error "No text editor available"
        return 1
    fi
    
    $editor "$env_file"
}

# Get current ports from env file
systemd_get_env_ports() {
    local env_file="$1"
    
    if [[ ! -f "$env_file" ]]; then
        return 1
    fi
    
    local service_port=$(grep -oP '^SERVICE_PORT=\K[0-9]+' "$env_file")
    local xray_port=$(grep -oP '^XRAY_API_PORT=\K[0-9]+' "$env_file")
    
    echo "${service_port}|${xray_port}"
}

