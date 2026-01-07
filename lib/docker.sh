#!/usr/bin/env bash
# =============================================================================
# Marzban Node Manager - Docker Operations
# =============================================================================
# Provides Docker and Docker Compose operations for node management
# =============================================================================

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/colors.sh" 2>/dev/null || true

# =============================================================================
# Docker Compose Detection (V2 preferred)
# =============================================================================

# Detect and validate docker compose command
# Prefers Docker Compose V2 (docker compose) over legacy V1 (docker-compose)
detect_compose() {
    # First, try Docker Compose V2 (plugin)
    if docker compose version >/dev/null 2>&1; then
        COMPOSE_CMD="docker compose"
        export COMPOSE_CMD
        return 0
    fi
    
    # Check for legacy docker-compose (V1)
    if command -v docker-compose >/dev/null 2>&1; then
        local version=$(docker-compose version --short 2>/dev/null || echo "0")
        
        # V1 versions < 2.0 have compatibility issues with newer Docker
        if [[ "$version" == 1.* ]]; then
            print_warning "Legacy docker-compose v${version} detected"
            print_warning "This version has known compatibility issues with newer Docker"
            print_info "Installing Docker Compose V2 plugin..."
            
            if install_compose_v2; then
                COMPOSE_CMD="docker compose"
                export COMPOSE_CMD
                return 0
            else
                print_error "Failed to install Docker Compose V2"
                print_error "Please install manually: https://docs.docker.com/compose/install/"
                return 1
            fi
        fi
        
        COMPOSE_CMD="docker-compose"
        export COMPOSE_CMD
        return 0
    fi
    
    # Neither found, try to install V2
    print_info "Docker Compose not found, installing..."
    if install_compose_v2; then
        COMPOSE_CMD="docker compose"
        export COMPOSE_CMD
        return 0
    fi
    
    print_error "Docker Compose not found and installation failed"
    return 1
}

# Install Docker Compose V2 plugin
install_compose_v2() {
    # Method 1: Try package manager first (if Docker repo is configured)
    if command -v apt-get >/dev/null 2>&1; then
        # Ensure Docker repo is set up
        if [[ ! -f /etc/apt/sources.list.d/docker.list ]]; then
            setup_docker_apt_repo_minimal
        fi
        
        if apt-get install -y docker-compose-plugin >/dev/null 2>&1; then
            if docker compose version >/dev/null 2>&1; then
                print_success "Docker Compose V2 installed via apt"
                return 0
            fi
        fi
    elif command -v yum >/dev/null 2>&1; then
        if yum install -y docker-compose-plugin >/dev/null 2>&1; then
            if docker compose version >/dev/null 2>&1; then
                print_success "Docker Compose V2 installed via yum"
                return 0
            fi
        fi
    fi
    
    # Method 2: Direct download from GitHub
    print_info "Downloading Docker Compose V2 from GitHub..."
    
    local arch=$(uname -m)
    case "$arch" in
        x86_64) arch="x86_64" ;;
        aarch64|arm64) arch="aarch64" ;;
        armv7l|armhf) arch="armv7" ;;
        *) arch="x86_64" ;;
    esac
    
    local compose_url="https://github.com/docker/compose/releases/latest/download/docker-compose-linux-${arch}"
    
    # Try multiple plugin directories
    local plugin_dirs=(
        "/usr/local/lib/docker/cli-plugins"
        "/usr/lib/docker/cli-plugins"
        "/usr/libexec/docker/cli-plugins"
    )
    
    for plugin_dir in "${plugin_dirs[@]}"; do
        mkdir -p "$plugin_dir" 2>/dev/null || continue
        
        if curl -SL "$compose_url" -o "${plugin_dir}/docker-compose" 2>/dev/null; then
            chmod +x "${plugin_dir}/docker-compose"
            
            if docker compose version >/dev/null 2>&1; then
                print_success "Docker Compose V2 installed"
                return 0
            fi
        fi
    done
    
    return 1
}

# Minimal Docker APT repo setup for compose plugin installation
setup_docker_apt_repo_minimal() {
    # Install prerequisites quietly
    apt-get install -y ca-certificates curl gnupg >/dev/null 2>&1
    
    # Create keyrings directory
    install -m 0755 -d /etc/apt/keyrings 2>/dev/null
    
    # Add Docker's official GPG key
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg 2>/dev/null | gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null
    chmod a+r /etc/apt/keyrings/docker.gpg 2>/dev/null
    
    # Get codename
    local codename=""
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        codename="${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}"
    fi
    [[ -z "$codename" ]] && codename=$(lsb_release -cs 2>/dev/null || echo "jammy")
    
    # Add repo
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${codename} stable" > /etc/apt/sources.list.d/docker.list 2>/dev/null
    
    apt-get update -qq >/dev/null 2>&1
}

# =============================================================================
# Docker Compose File Generation
# =============================================================================

# Generate docker-compose.yml content for a node
# Usage: generate_compose_file <node_name> <service_port> <xray_port> <data_dir> <cert_file> [inbounds]
generate_compose_file() {
    local node_name="$1"
    local service_port="$2"
    local xray_port="$3"
    local data_dir="$4"
    local cert_file="$5"
    local inbounds="${6:-}"
    
    cat <<EOF
services:
  marzban-node:
    container_name: ${node_name}
    image: ${MARZBAN_NODE_IMAGE}
    restart: always
    network_mode: host
    environment:
      SERVICE_PORT: "${service_port}"
      XRAY_API_PORT: "${xray_port}"
      SSL_CLIENT_CERT_FILE: "/var/lib/marzban-node/ssl_client_cert.pem"
      SSL_CERT_FILE: "/var/lib/marzban-node/ssl_cert.pem"
      SSL_KEY_FILE: "/var/lib/marzban-node/ssl_key.pem"
      SERVICE_PROTOCOL: "rest"
EOF

    # Add INBOUNDS if specified
    if [[ -n "$inbounds" ]]; then
        echo "      INBOUNDS: \"${inbounds}\""
    fi

    cat <<EOF
    volumes:
      - ${data_dir}:/var/lib/marzban-node
EOF
}

# Create docker-compose.yml file
# Usage: create_compose_file <install_dir> <node_name> <service_port> <xray_port> <data_dir> <cert_file> [inbounds]
create_compose_file() {
    local install_dir="$1"
    local node_name="$2"
    local service_port="$3"
    local xray_port="$4"
    local data_dir="$5"
    local cert_file="$6"
    local inbounds="${7:-}"
    
    local compose_file="${install_dir}/docker-compose.yml"
    
    ensure_dir "$install_dir"
    
    generate_compose_file "$node_name" "$service_port" "$xray_port" "$data_dir" "$cert_file" "$inbounds" > "$compose_file"
    
    if [[ $? -eq 0 ]]; then
        log_info "Created docker-compose.yml at $compose_file"
        return 0
    else
        log_error "Failed to create docker-compose.yml"
        return 1
    fi
}

# Update docker-compose.yml ports
update_compose_ports() {
    local compose_file="$1"
    local service_port="$2"
    local xray_port="$3"
    
    if [[ ! -f "$compose_file" ]]; then
        print_error "Compose file not found: $compose_file"
        return 1
    fi
    
    # Use sed to update port values
    sed -i "s/SERVICE_PORT: \"[0-9]*\"/SERVICE_PORT: \"${service_port}\"/" "$compose_file"
    sed -i "s/XRAY_API_PORT: \"[0-9]*\"/XRAY_API_PORT: \"${xray_port}\"/" "$compose_file"
    
    log_info "Updated compose file ports: SERVICE=$service_port, XRAY=$xray_port"
    return 0
}

# Update docker-compose.yml inbounds
update_compose_inbounds() {
    local compose_file="$1"
    local inbounds="$2"
    
    if [[ ! -f "$compose_file" ]]; then
        print_error "Compose file not found: $compose_file"
        return 1
    fi
    
    # Remove existing INBOUNDS line if present
    sed -i '/INBOUNDS:/d' "$compose_file"
    
    # Add INBOUNDS if not empty
    if [[ -n "$inbounds" ]]; then
        # Add INBOUNDS after SERVICE_PROTOCOL line
        sed -i "/SERVICE_PROTOCOL:/a\\      INBOUNDS: \"${inbounds}\"" "$compose_file"
    fi
    
    log_info "Updated compose file inbounds: $inbounds"
    return 0
}

# =============================================================================
# Docker Container Operations
# =============================================================================

# Start a node using docker compose
docker_node_start() {
    local install_dir="$1"
    local node_name="$2"
    local compose_file="${install_dir}/docker-compose.yml"
    
    if [[ ! -f "$compose_file" ]]; then
        print_error "Compose file not found: $compose_file"
        return 1
    fi
    
    detect_compose || return 1
    
    print_info "Starting node ${node_name}..."
    
    if $COMPOSE_CMD -f "$compose_file" -p "$node_name" up -d --remove-orphans 2>&1; then
        print_success "Node ${node_name} started"
        log_info "Started node: $node_name"
        return 0
    else
        print_error "Failed to start node ${node_name}"
        log_error "Failed to start node: $node_name"
        return 1
    fi
}

# Stop a node using docker compose
docker_node_stop() {
    local install_dir="$1"
    local node_name="$2"
    local compose_file="${install_dir}/docker-compose.yml"
    
    if [[ ! -f "$compose_file" ]]; then
        print_error "Compose file not found: $compose_file"
        return 1
    fi
    
    detect_compose || return 1
    
    print_info "Stopping node ${node_name}..."
    
    if $COMPOSE_CMD -f "$compose_file" -p "$node_name" down 2>&1; then
        print_success "Node ${node_name} stopped"
        log_info "Stopped node: $node_name"
        return 0
    else
        print_error "Failed to stop node ${node_name}"
        log_error "Failed to stop node: $node_name"
        return 1
    fi
}

# Restart a node using docker compose
docker_node_restart() {
    local install_dir="$1"
    local node_name="$2"
    local compose_file="${install_dir}/docker-compose.yml"
    
    if [[ ! -f "$compose_file" ]]; then
        print_error "Compose file not found: $compose_file"
        return 1
    fi
    
    detect_compose || return 1
    
    print_info "Restarting node ${node_name}..."
    
    $COMPOSE_CMD -f "$compose_file" -p "$node_name" down 2>&1
    
    if $COMPOSE_CMD -f "$compose_file" -p "$node_name" up -d --remove-orphans 2>&1; then
        print_success "Node ${node_name} restarted"
        log_info "Restarted node: $node_name"
        return 0
    else
        print_error "Failed to restart node ${node_name}"
        log_error "Failed to restart node: $node_name"
        return 1
    fi
}

# Get node logs
docker_node_logs() {
    local install_dir="$1"
    local node_name="$2"
    local follow="${3:-false}"
    local compose_file="${install_dir}/docker-compose.yml"
    
    if [[ ! -f "$compose_file" ]]; then
        print_error "Compose file not found: $compose_file"
        return 1
    fi
    
    detect_compose || return 1
    
    if [[ "$follow" == "true" ]]; then
        $COMPOSE_CMD -f "$compose_file" -p "$node_name" logs -f
    else
        $COMPOSE_CMD -f "$compose_file" -p "$node_name" logs --tail=100
    fi
}

# Pull latest image
docker_node_update() {
    local install_dir="$1"
    local node_name="$2"
    local compose_file="${install_dir}/docker-compose.yml"
    
    if [[ ! -f "$compose_file" ]]; then
        print_error "Compose file not found: $compose_file"
        return 1
    fi
    
    detect_compose || return 1
    
    print_info "Pulling latest image for ${node_name}..."
    
    if $COMPOSE_CMD -f "$compose_file" -p "$node_name" pull 2>&1; then
        print_success "Image updated for ${node_name}"
        log_info "Updated image for node: $node_name"
        return 0
    else
        print_error "Failed to update image for ${node_name}"
        log_error "Failed to update image for node: $node_name"
        return 1
    fi
}

# =============================================================================
# Container Status
# =============================================================================

# Check if a docker node is running
docker_node_is_running() {
    local node_name="$1"
    
    local status=$(docker inspect -f '{{.State.Running}}' "$node_name" 2>/dev/null)
    
    [[ "$status" == "true" ]]
}

# Get container ID for a node
docker_node_get_container_id() {
    local node_name="$1"
    
    docker inspect -f '{{.Id}}' "$node_name" 2>/dev/null | cut -c1-12
}

# Get full container status
docker_node_status() {
    local node_name="$1"
    
    if ! docker ps -a --filter "name=^${node_name}$" --format "{{.Status}}" 2>/dev/null | head -1; then
        echo "not_found"
    fi
}

# Get container health status
docker_node_health() {
    local node_name="$1"
    
    docker inspect -f '{{.State.Health.Status}}' "$node_name" 2>/dev/null || echo "unknown"
}

# Get detailed container info
docker_node_info() {
    local node_name="$1"
    
    if ! docker inspect "$node_name" 2>/dev/null; then
        return 1
    fi
}

# =============================================================================
# Installation and Removal
# =============================================================================

# Install a node via Docker
# Usage: docker_node_install <node_name> <service_port> <xray_port> <cert_content> [inbounds]
docker_node_install() {
    local node_name="$1"
    local service_port="$2"
    local xray_port="$3"
    local cert_content="$4"
    local inbounds="${5:-}"
    
    local install_dir="${NODE_INSTALL_DIR}/${node_name}"
    local data_dir="${NODE_DATA_BASE_DIR}/${node_name}"
    local cert_file="${data_dir}/ssl_client_cert.pem"
    
    # Ensure Docker is available
    if ! is_docker_installed; then
        print_error "Docker is not installed"
        return 1
    fi
    
    if ! is_docker_running; then
        print_error "Docker is not running"
        return 1
    fi
    
    detect_compose || return 1
    
    # Create directories
    print_step "1/4" "Creating directories..."
    ensure_dir "$install_dir"
    ensure_dir "$data_dir"
    
    # Save certificate
    print_step "2/4" "Saving certificate..."
    echo "$cert_content" > "$cert_file"
    chmod 600 "$cert_file"
    
    # Create docker-compose.yml
    print_step "3/4" "Creating docker-compose.yml..."
    create_compose_file "$install_dir" "$node_name" "$service_port" "$xray_port" "$data_dir" "$cert_file" "$inbounds"
    
    # Pull image and start
    print_step "4/4" "Starting container..."
    docker_node_start "$install_dir" "$node_name"
    
    return $?
}

# Uninstall a docker node
docker_node_uninstall() {
    local node_name="$1"
    local install_dir="$2"
    local data_dir="$3"
    local remove_data="${4:-false}"
    
    detect_compose || return 1
    
    # Stop container if running
    if docker_node_is_running "$node_name"; then
        print_info "Stopping container..."
        docker_node_stop "$install_dir" "$node_name"
    fi
    
    # Remove container
    print_info "Removing container..."
    docker rm -f "$node_name" 2>/dev/null
    
    # Remove install directory (docker-compose.yml)
    if [[ -d "$install_dir" ]]; then
        print_info "Removing install directory..."
        rm -rf "$install_dir"
    fi
    
    # Optionally remove data directory
    if [[ "$remove_data" == "true" && -d "$data_dir" ]]; then
        print_info "Removing data directory..."
        rm -rf "$data_dir"
    fi
    
    log_info "Uninstalled docker node: $node_name"
    return 0
}

# =============================================================================
# Docker Image Management
# =============================================================================

# Remove marzban-node images
docker_remove_images() {
    local images=$(docker images | grep marzban-node | awk '{print $3}')
    
    if [[ -n "$images" ]]; then
        print_info "Removing Marzban-node images..."
        for image in $images; do
            if docker rmi "$image" >/dev/null 2>&1; then
                print_success "Removed image: $image"
            fi
        done
    fi
}

# Prune unused docker resources
docker_cleanup() {
    print_info "Cleaning up unused Docker resources..."
    docker system prune -f >/dev/null 2>&1
    print_success "Docker cleanup complete"
}

# =============================================================================
# Docker Compose Status for Multiple Nodes
# =============================================================================

# Get status of all docker nodes
docker_nodes_status() {
    local nodes="$1"  # Pipe-separated list from database
    
    while IFS='|' read -r name service_port xray_port method install_dir data_dir status; do
        if [[ "$method" != "docker" ]]; then
            continue
        fi
        
        local running="down"
        local container_id="-"
        
        if docker_node_is_running "$name"; then
            running="up"
            container_id=$(docker_node_get_container_id "$name")
        fi
        
        echo "${name}|${service_port}|${xray_port}|${running}|${container_id}"
    done <<< "$nodes"
}

# =============================================================================
# Docker Compose Edit
# =============================================================================

# Edit docker-compose.yml interactively
docker_node_edit_compose() {
    local install_dir="$1"
    local compose_file="${install_dir}/docker-compose.yml"
    
    if [[ ! -f "$compose_file" ]]; then
        print_error "Compose file not found: $compose_file"
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
    
    $editor "$compose_file"
}

# Get current ports from compose file
docker_get_compose_ports() {
    local compose_file="$1"
    
    if [[ ! -f "$compose_file" ]]; then
        return 1
    fi
    
    local service_port=$(grep -oP 'SERVICE_PORT:\s*"\K[0-9]+' "$compose_file" | head -1)
    local xray_port=$(grep -oP 'XRAY_API_PORT:\s*"\K[0-9]+' "$compose_file" | head -1)
    
    echo "${service_port}|${xray_port}"
}

