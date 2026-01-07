#!/usr/bin/env bash
# =============================================================================
# Marzban Node Manager - Main CLI
# =============================================================================
# A professional CLI tool for managing multiple Marzban-node instances
# Repository: https://github.com/DrSaeedHub/Marzban-node-manager
# =============================================================================

set -e

# Get script directory (works even with symlinks)
get_script_dir() {
    local source="${BASH_SOURCE[0]}"
    while [ -h "$source" ]; do
        local dir="$(cd -P "$(dirname "$source")" && pwd)"
        source="$(readlink "$source")"
        [[ $source != /* ]] && source="$dir/$source"
    done
    echo "$(cd -P "$(dirname "$source")" && pwd)"
}

SCRIPT_DIR="$(get_script_dir)"
LIB_DIR="${SCRIPT_DIR}/lib"

# Source library files
source "${LIB_DIR}/colors.sh"
source "${LIB_DIR}/utils.sh"
source "${LIB_DIR}/database.sh"
source "${LIB_DIR}/ports.sh"
source "${LIB_DIR}/docker.sh"
source "${LIB_DIR}/systemd.sh"

# =============================================================================
# Global Variables
# =============================================================================

OPERATION=""
NODE_NAME=""
SERVICE_PORT=""
XRAY_PORT=""
METHOD="docker"
CERT_PATH=""
CERT_CONTENT=""
INBOUNDS=""
YES_MODE=false
FOLLOW_LOGS=false

# =============================================================================
# Help and Usage
# =============================================================================

show_help() {
    print_mini_banner
    echo ""
    color_echo cyan "Usage:"
    echo "  marzban-node-manager <operation> [options]"
    echo ""
    color_echo cyan "Operations:"
    echo "  install         Install a new Marzban node"
    echo "  uninstall       Remove a Marzban node"
    echo "  edit            Modify node configuration"
    echo "  status          Show node(s) status"
    echo "  start           Start a node"
    echo "  stop            Stop a node"
    echo "  restart         Restart a node"
    echo "  logs            View node logs"
    echo "  list            List all managed nodes"
    echo "  update          Update node image/code"
    echo "  update-cli      Update CLI to latest version"
    echo "  uninstall-cli   Remove the CLI tool itself"
    echo ""
    color_echo cyan "Options:"
    echo "  -n, --name          Node name (required for most operations)"
    echo "  -s, --service-port  SERVICE_PORT (auto-assigned if not provided)"
    echo "  -x, --xray-port     XRAY_API_PORT (auto-assigned if not provided)"
    echo "  -m, --method        Installation method: docker (default) or normal"
    echo "  -c, --cert          Path to ssl_client_cert.pem file"
    echo "  --cert-content      Certificate content directly (for automation)"
    echo "  -i, --inbounds      Comma-separated inbound names (case-sensitive)"
    echo "  -y, --yes           Non-interactive mode (skip confirmations)"
    echo "  -f, --follow        Follow logs (for logs operation)"
    echo "  -h, --help          Show this help message"
    echo ""
    color_echo cyan "Examples:"
    echo "  # Install a new node with Docker"
    echo "  marzban-node-manager install -n mynode -c /path/to/cert.pem"
    echo ""
    echo "  # Install with custom ports"
    echo "  marzban-node-manager install -n mynode -s 62060 -x 62061 -c cert.pem"
    echo ""
    echo "  # Install with specific inbounds (case-sensitive)"
    echo "  marzban-node-manager install -n mynode -c cert.pem -i 'VLESS TCP REALITY, VMESS TCP'"
    echo ""
    echo "  # Install using normal (systemd) method"
    echo "  marzban-node-manager install -n mynode -m normal -c cert.pem"
    echo ""
    echo "  # Show status of all nodes"
    echo "  marzban-node-manager status"
    echo ""
    echo "  # Show status of specific node"
    echo "  marzban-node-manager status -n mynode"
    echo ""
    echo "  # View logs"
    echo "  marzban-node-manager logs -n mynode -f"
    echo ""
    echo "  # Update CLI to latest version"
    echo "  marzban-node-manager update-cli"
    echo ""
}

show_version() {
    echo "Marzban Node Manager v${MANAGER_VERSION}"
}

# =============================================================================
# Argument Parsing
# =============================================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            install|uninstall|edit|status|start|stop|restart|logs|list|update|update-cli|uninstall-cli)
                OPERATION="$1"
                shift
                ;;
            -n|--name)
                NODE_NAME="$2"
                shift 2
                ;;
            -s|--service-port)
                SERVICE_PORT="$2"
                shift 2
                ;;
            -x|--xray-port)
                XRAY_PORT="$2"
                shift 2
                ;;
            -m|--method)
                METHOD="$2"
                shift 2
                ;;
            -c|--cert)
                CERT_PATH="$2"
                shift 2
                ;;
            --cert-content)
                CERT_CONTENT="$2"
                shift 2
                ;;
            -i|--inbounds)
                INBOUNDS="$2"
                shift 2
                ;;
            -y|--yes)
                YES_MODE=true
                shift
                ;;
            -f|--follow)
                FOLLOW_LOGS=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--version)
                show_version
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
}

# =============================================================================
# Install Operation
# =============================================================================

cmd_install() {
    check_root
    
    print_header "Install Marzban Node"
    
    # Validate method
    if ! validate_method "$METHOD"; then
        exit 1
    fi
    
    # Get or prompt for node name
    if [[ -z "$NODE_NAME" ]]; then
        prompt_input "Enter node name" "marzban-node"
        NODE_NAME="$REPLY"
    fi
    
    if ! validate_node_name "$NODE_NAME"; then
        exit 1
    fi
    
    # Check if node already exists
    if db_node_exists "$NODE_NAME"; then
        print_error "Node '$NODE_NAME' already exists"
        print_info "Use 'edit' to modify or 'uninstall' to remove it first"
        exit 1
    fi
    
    # Handle ports
    if [[ -z "$SERVICE_PORT" || -z "$XRAY_PORT" ]]; then
        print_info "Auto-allocating ports..."
        allocate_node_ports
        
        if [[ -z "$SERVICE_PORT" ]]; then
            SERVICE_PORT="$ALLOCATED_SERVICE_PORT"
        fi
        if [[ -z "$XRAY_PORT" ]]; then
            XRAY_PORT="$ALLOCATED_XRAY_PORT"
        fi
    fi
    
    # Validate ports
    if ! validate_port_pair "$SERVICE_PORT" "$XRAY_PORT"; then
        exit 1
    fi
    
    print_kv "Node Name" "$NODE_NAME"
    print_kv "Method" "$METHOD"
    print_kv "SERVICE_PORT" "$SERVICE_PORT"
    print_kv "XRAY_API_PORT" "$XRAY_PORT"
    if [[ -n "$INBOUNDS" ]]; then
        print_kv "INBOUNDS" "$INBOUNDS"
    else
        print_kv "INBOUNDS" "(all inbounds)"
    fi
    echo ""
    
    # Handle certificate
    if [[ -z "$CERT_CONTENT" ]]; then
        if [[ -n "$CERT_PATH" ]]; then
            CERT_CONTENT=$(read_cert_file "$CERT_PATH")
            if [[ $? -ne 0 ]]; then
                exit 1
            fi
        else
            if is_interactive; then
                CERT_CONTENT=$(read_cert_interactive)
            else
                print_error "Certificate is required. Use --cert or --cert-content"
                exit 1
            fi
        fi
    fi
    
    # Validate certificate
    if ! validate_certificate "$CERT_CONTENT"; then
        exit 1
    fi
    
    # Confirmation
    if [[ "$YES_MODE" != true ]]; then
        if ! confirm "Proceed with installation?"; then
            print_warning "Installation cancelled"
            exit 0
        fi
    fi
    
    echo ""
    print_subheader "Installing Node"
    
    local install_dir="${NODE_INSTALL_DIR}/${NODE_NAME}"
    local data_dir="${NODE_DATA_BASE_DIR}/${NODE_NAME}"
    local cert_file="${data_dir}/ssl_client_cert.pem"
    
    # Install based on method
    if [[ "$METHOD" == "docker" ]]; then
        docker_node_install "$NODE_NAME" "$SERVICE_PORT" "$XRAY_PORT" "$CERT_CONTENT" "$INBOUNDS"
    else
        systemd_node_install "$NODE_NAME" "$SERVICE_PORT" "$XRAY_PORT" "$CERT_CONTENT" "$INBOUNDS"
    fi
    
    if [[ $? -eq 0 ]]; then
        # Record in database
        db_node_create "$NODE_NAME" "$SERVICE_PORT" "$XRAY_PORT" "$METHOD" "$install_dir" "$data_dir" "$cert_file" "$INBOUNDS"
        
        echo ""
        print_success "Node '$NODE_NAME' installed successfully!"
        echo ""
        print_subheader "Node Information"
        print_kv "Name" "$NODE_NAME"
        print_kv "SERVICE_PORT" "$SERVICE_PORT"
        print_kv "XRAY_API_PORT" "$XRAY_PORT"
        print_kv "Install Dir" "$install_dir"
        print_kv "Data Dir" "$data_dir"
        
        local public_ip=$(get_public_ip)
        if [[ -n "$public_ip" ]]; then
            echo ""
            print_info "Use this IP in your Marzban panel: $public_ip"
        fi
    else
        print_error "Installation failed"
        exit 1
    fi
}

# =============================================================================
# Uninstall Operation
# =============================================================================

cmd_uninstall() {
    check_root
    
    print_header "Uninstall Marzban Node"
    
    if [[ -z "$NODE_NAME" ]]; then
        prompt_input "Enter node name to uninstall"
        NODE_NAME="$REPLY"
    fi
    
    if ! db_node_exists "$NODE_NAME"; then
        print_error "Node '$NODE_NAME' not found"
        exit 1
    fi
    
    # Get node info
    local node_record=$(db_node_get "$NODE_NAME")
    parse_node_record "$node_record"
    
    print_kv "Node Name" "$NODE_NAME"
    print_kv "Method" "$NODE_METHOD"
    print_kv "Install Dir" "$NODE_DIR"
    print_kv "Data Dir" "$NODE_DATA"
    echo ""
    
    # Confirmation
    if [[ "$YES_MODE" != true ]]; then
        if ! confirm "Are you sure you want to uninstall '$NODE_NAME'?" "n"; then
            print_warning "Uninstall cancelled"
            exit 0
        fi
    fi
    
    local remove_data=false
    if [[ "$YES_MODE" != true ]]; then
        if confirm "Also remove data directory (certificates, configs)?" "n"; then
            remove_data=true
        fi
    fi
    
    echo ""
    print_subheader "Uninstalling Node"
    
    # Uninstall based on method
    if [[ "$NODE_METHOD" == "docker" ]]; then
        docker_node_uninstall "$NODE_NAME" "$NODE_DIR" "$NODE_DATA" "$remove_data"
    else
        systemd_node_uninstall "$NODE_NAME" "$NODE_DIR" "$NODE_DATA" "$remove_data"
    fi
    
    # Remove from database
    db_node_delete "$NODE_NAME"
    
    print_success "Node '$NODE_NAME' uninstalled successfully"
}

# =============================================================================
# Edit Operation
# =============================================================================

cmd_edit() {
    check_root
    
    print_header "Edit Marzban Node"
    
    if [[ -z "$NODE_NAME" ]]; then
        prompt_input "Enter node name to edit"
        NODE_NAME="$REPLY"
    fi
    
    if ! db_node_exists "$NODE_NAME"; then
        print_error "Node '$NODE_NAME' not found"
        exit 1
    fi
    
    # Get node info
    local node_record=$(db_node_get "$NODE_NAME")
    parse_node_record "$node_record"
    
    print_subheader "Current Configuration"
    print_kv "Node Name" "$NODE_NAME"
    print_kv "Method" "$NODE_METHOD"
    print_kv "SERVICE_PORT" "$NODE_SERVICE_PORT"
    print_kv "XRAY_API_PORT" "$NODE_XRAY_PORT"
    if [[ -n "$NODE_INBOUNDS" ]]; then
        print_kv "INBOUNDS" "$NODE_INBOUNDS"
    else
        print_kv "INBOUNDS" "(all inbounds)"
    fi
    echo ""
    
    # Get new values
    local new_service_port="$SERVICE_PORT"
    local new_xray_port="$XRAY_PORT"
    local new_inbounds="$INBOUNDS"
    local inbounds_changed=false
    
    if [[ -z "$new_service_port" ]]; then
        prompt_port "Enter new SERVICE_PORT" "$NODE_SERVICE_PORT" "$NODE_NAME" "SERVICE_PORT"
        new_service_port="$SELECTED_PORT"
    fi
    
    if [[ -z "$new_xray_port" ]]; then
        prompt_port "Enter new XRAY_API_PORT" "$NODE_XRAY_PORT" "$NODE_NAME" "XRAY_API_PORT"
        new_xray_port="$SELECTED_PORT"
    fi
    
    # Handle inbounds - if not provided via CLI, prompt interactively
    if [[ -z "$new_inbounds" && "$YES_MODE" != true ]]; then
        local current_inbounds="${NODE_INBOUNDS:-}"
        prompt_input "Enter INBOUNDS (comma-separated, empty for all)" "$current_inbounds"
        new_inbounds="$REPLY"
        if [[ "$new_inbounds" != "$NODE_INBOUNDS" ]]; then
            inbounds_changed=true
        fi
    elif [[ -n "$new_inbounds" && "$new_inbounds" != "$NODE_INBOUNDS" ]]; then
        inbounds_changed=true
    fi
    
    # Validate new port pair
    if ! validate_port_pair "$new_service_port" "$new_xray_port" "$NODE_NAME"; then
        exit 1
    fi
    
    echo ""
    print_subheader "New Configuration"
    print_kv "SERVICE_PORT" "$new_service_port"
    print_kv "XRAY_API_PORT" "$new_xray_port"
    if [[ -n "$new_inbounds" ]]; then
        print_kv "INBOUNDS" "$new_inbounds"
    else
        print_kv "INBOUNDS" "(all inbounds)"
    fi
    echo ""
    
    if [[ "$YES_MODE" != true ]]; then
        if ! confirm "Apply changes?"; then
            print_warning "Edit cancelled"
            exit 0
        fi
    fi
    
    # Update configuration files
    if [[ "$NODE_METHOD" == "docker" ]]; then
        local compose_file="${NODE_DIR}/docker-compose.yml"
        update_compose_ports "$compose_file" "$new_service_port" "$new_xray_port"
        if [[ "$inbounds_changed" == true || -n "$INBOUNDS" ]]; then
            update_compose_inbounds "$compose_file" "$new_inbounds"
        fi
    else
        local env_file="${NODE_DIR}/.env"
        update_env_ports "$env_file" "$new_service_port" "$new_xray_port"
        if [[ "$inbounds_changed" == true || -n "$INBOUNDS" ]]; then
            update_env_inbounds "$env_file" "$new_inbounds"
        fi
    fi
    
    # Update database
    db_node_update_ports "$NODE_NAME" "$new_service_port" "$new_xray_port"
    if [[ "$inbounds_changed" == true || -n "$INBOUNDS" ]]; then
        db_node_update "$NODE_NAME" "inbounds" "$new_inbounds"
    fi
    
    # Restart node
    print_info "Restarting node to apply changes..."
    if [[ "$NODE_METHOD" == "docker" ]]; then
        docker_node_restart "$NODE_DIR" "$NODE_NAME"
    else
        systemd_node_restart "$NODE_NAME"
    fi
    
    print_success "Node '$NODE_NAME' updated successfully"
}

# =============================================================================
# Status Operation
# =============================================================================

cmd_status() {
    print_header "Marzban Node Manager"
    
    if [[ -n "$NODE_NAME" ]]; then
        # Show status for specific node
        if ! db_node_exists "$NODE_NAME"; then
            print_error "Node '$NODE_NAME' not found"
            exit 1
        fi
        
        local node_record=$(db_node_get "$NODE_NAME")
        parse_node_record "$node_record"
        
        local running="down"
        local identifier="-"
        
        if [[ "$NODE_METHOD" == "docker" ]]; then
            if docker_node_is_running "$NODE_NAME"; then
                running="up"
                identifier=$(docker_node_get_container_id "$NODE_NAME")
            fi
        else
            if systemd_node_is_running "$NODE_NAME"; then
                running="up"
                identifier="PID:$(systemd_node_get_pid "$NODE_NAME")"
            fi
        fi
        
        print_subheader "Node: $NODE_NAME"
        print_status "$running" "$NODE_NAME"
        echo ""
        print_kv "Method" "$NODE_METHOD"
        print_kv "SERVICE_PORT" "$NODE_SERVICE_PORT"
        print_kv "XRAY_API_PORT" "$NODE_XRAY_PORT"
        if [[ -n "$NODE_INBOUNDS" ]]; then
            print_kv "INBOUNDS" "$NODE_INBOUNDS"
        else
            print_kv "INBOUNDS" "(all inbounds)"
        fi
        print_kv "Install Dir" "$NODE_DIR"
        print_kv "Data Dir" "$NODE_DATA"
        print_kv "Container/PID" "$identifier"
        print_kv "Created" "$NODE_CREATED"
    else
        # Show status for all nodes
        local node_count=$(db_node_count)
        
        if [[ "$node_count" -eq 0 ]]; then
            print_info "No nodes registered"
            print_info "Use 'marzban-node-manager install' to add a node"
            exit 0
        fi
        
        print_info "Total nodes: $node_count"
        echo ""
        
        print_table_header "Name" "Method" "Ports" "Status" "Container/PID"
        
        local nodes=$(db_node_list)
        
        while IFS='|' read -r name service_port xray_port method install_dir data_dir status; do
            local running="down"
            local identifier="-"
            local ports="${service_port}/${xray_port}"
            
            if [[ "$method" == "docker" ]]; then
                if docker_node_is_running "$name"; then
                    running="up"
                    identifier=$(docker_node_get_container_id "$name")
                fi
            else
                if systemd_node_is_running "$name"; then
                    running="up"
                    identifier="PID:$(systemd_node_get_pid "$name")"
                fi
            fi
            
            local status_symbol
            if [[ "$running" == "up" ]]; then
                status_symbol="${COLOR_GREEN}● Up${COLOR_RESET}"
            else
                status_symbol="${COLOR_DIM}○ Down${COLOR_RESET}"
            fi
            
            printf "│ %-12s │ %-10s │ %-12s │ " "$name" "$method" "$ports"
            printf "${status_symbol}"
            printf " │ %-18s │\n" "$identifier"
        done <<< "$nodes"
        
        print_table_footer
    fi
}

# =============================================================================
# Start/Stop/Restart Operations
# =============================================================================

cmd_start() {
    check_root
    
    if [[ -z "$NODE_NAME" ]]; then
        print_error "Node name required. Use -n <name>"
        exit 1
    fi
    
    if ! db_node_exists "$NODE_NAME"; then
        print_error "Node '$NODE_NAME' not found"
        exit 1
    fi
    
    local node_record=$(db_node_get "$NODE_NAME")
    parse_node_record "$node_record"
    
    if [[ "$NODE_METHOD" == "docker" ]]; then
        docker_node_start "$NODE_DIR" "$NODE_NAME"
    else
        systemd_node_start "$NODE_NAME"
    fi
}

cmd_stop() {
    check_root
    
    if [[ -z "$NODE_NAME" ]]; then
        print_error "Node name required. Use -n <name>"
        exit 1
    fi
    
    if ! db_node_exists "$NODE_NAME"; then
        print_error "Node '$NODE_NAME' not found"
        exit 1
    fi
    
    local node_record=$(db_node_get "$NODE_NAME")
    parse_node_record "$node_record"
    
    if [[ "$NODE_METHOD" == "docker" ]]; then
        docker_node_stop "$NODE_DIR" "$NODE_NAME"
    else
        systemd_node_stop "$NODE_NAME"
    fi
}

cmd_restart() {
    check_root
    
    if [[ -z "$NODE_NAME" ]]; then
        print_error "Node name required. Use -n <name>"
        exit 1
    fi
    
    if ! db_node_exists "$NODE_NAME"; then
        print_error "Node '$NODE_NAME' not found"
        exit 1
    fi
    
    local node_record=$(db_node_get "$NODE_NAME")
    parse_node_record "$node_record"
    
    if [[ "$NODE_METHOD" == "docker" ]]; then
        docker_node_restart "$NODE_DIR" "$NODE_NAME"
    else
        systemd_node_restart "$NODE_NAME"
    fi
}

# =============================================================================
# Logs Operation
# =============================================================================

cmd_logs() {
    if [[ -z "$NODE_NAME" ]]; then
        print_error "Node name required. Use -n <name>"
        exit 1
    fi
    
    if ! db_node_exists "$NODE_NAME"; then
        print_error "Node '$NODE_NAME' not found"
        exit 1
    fi
    
    local node_record=$(db_node_get "$NODE_NAME")
    parse_node_record "$node_record"
    
    if [[ "$NODE_METHOD" == "docker" ]]; then
        docker_node_logs "$NODE_DIR" "$NODE_NAME" "$FOLLOW_LOGS"
    else
        systemd_node_logs "$NODE_NAME" "$FOLLOW_LOGS"
    fi
}

# =============================================================================
# List Operation
# =============================================================================

cmd_list() {
    local nodes=$(db_node_list)
    
    if [[ -z "$nodes" ]]; then
        print_info "No nodes registered"
        exit 0
    fi
    
    echo ""
    while IFS='|' read -r name service_port xray_port method install_dir data_dir status; do
        echo "$name"
    done <<< "$nodes"
}

# =============================================================================
# Update Operation
# =============================================================================

cmd_update() {
    check_root
    
    if [[ -z "$NODE_NAME" ]]; then
        print_error "Node name required. Use -n <name>"
        exit 1
    fi
    
    if ! db_node_exists "$NODE_NAME"; then
        print_error "Node '$NODE_NAME' not found"
        exit 1
    fi
    
    local node_record=$(db_node_get "$NODE_NAME")
    parse_node_record "$node_record"
    
    print_header "Update Node: $NODE_NAME"
    
    if [[ "$NODE_METHOD" == "docker" ]]; then
        docker_node_update "$NODE_DIR" "$NODE_NAME"
        docker_node_restart "$NODE_DIR" "$NODE_NAME"
    else
        print_info "Updating from git repository..."
        cd "$NODE_DIR" && git pull --quiet
        
        print_info "Updating dependencies..."
        install_python_deps "$NODE_DIR"
        
        systemd_node_restart "$NODE_NAME"
    fi
    
    print_success "Node '$NODE_NAME' updated"
}

# =============================================================================
# Update CLI Operation
# =============================================================================

cmd_update_cli() {
    check_root
    
    print_header "Update Marzban Node Manager"
    
    local REPO_RAW_URL="https://raw.githubusercontent.com/DrSaeedHub/Marzban-node-manager/main"
    local CLI_INSTALL_DIR="/opt/marzban-node-manager"
    
    print_info "Current version: ${MANAGER_VERSION}"
    print_info "Checking for updates..."
    echo ""
    
    # Download and check remote version
    local remote_version
    remote_version=$(curl -sSL "https://raw.githubusercontent.com/DrSaeedHub/Marzban-node-manager/main/marzban-node-manager.sh" 2>/dev/null | awk -F'"' '/MANAGER_VERSION=/{print $2; exit}')
    
    if [[ -z "$remote_version" ]]; then
        print_error "Failed to check for updates. Please check your internet connection."
        exit 1
    fi
    
    print_info "Latest version: ${remote_version}"
    echo ""
    
    if [[ "$MANAGER_VERSION" == "$remote_version" ]]; then
        print_success "You are already running the latest version!"
        exit 0
    fi
    
    if [[ "$YES_MODE" != true ]]; then
        if ! confirm "Update to version ${remote_version}?"; then
            print_warning "Update cancelled"
            exit 0
        fi
    fi
    
    echo ""
    print_subheader "Downloading Updates"
    
    # Backup current installation
    print_info "Creating backup..."
    local backup_dir="/tmp/marzban-node-manager-backup-$(date +%Y%m%d_%H%M%S)"
    cp -r "$CLI_INSTALL_DIR" "$backup_dir" 2>/dev/null || true
    
    # Download updated files
    local files=("marzban-node-manager.sh" "lib/colors.sh" "lib/utils.sh" "lib/database.sh" "lib/ports.sh" "lib/docker.sh" "lib/systemd.sh")
    local failed=false
    
    for file in "${files[@]}"; do
        echo -n "  Downloading ${file}... "
        if curl -sSL "${REPO_RAW_URL}/${file}" -o "${CLI_INSTALL_DIR}/${file}" 2>/dev/null; then
            echo -e "${COLOR_GREEN}✓${COLOR_RESET}"
        else
            echo -e "${COLOR_RED}✗${COLOR_RESET}"
            failed=true
        fi
    done
    
    if [[ "$failed" == true ]]; then
        print_error "Some files failed to download"
        print_info "Restoring backup..."
        rm -rf "$CLI_INSTALL_DIR"
        mv "$backup_dir" "$CLI_INSTALL_DIR"
        exit 1
    fi
    
    # Set permissions
    chmod +x "${CLI_INSTALL_DIR}/marzban-node-manager.sh"
    chmod +x "${CLI_INSTALL_DIR}/lib/"*.sh
    
    # Run database migrations
    print_info "Running database migrations..."
    source "${CLI_INSTALL_DIR}/lib/database.sh"
    db_migrate
    
    # Clean up backup
    rm -rf "$backup_dir"
    
    echo ""
    print_success "CLI updated to version ${remote_version}!"
    print_info "Run 'marzban-node-manager --version' to verify"
}

# =============================================================================
# Uninstall CLI Operation
# =============================================================================

cmd_uninstall_cli() {
    check_root
    
    print_header "Uninstall Marzban Node Manager"
    
    print_warning "This will remove the Marzban Node Manager CLI tool"
    echo ""
    
    if [[ "$YES_MODE" != true ]]; then
        if ! confirm "Are you sure you want to uninstall the CLI?" "n"; then
            print_warning "Uninstall cancelled"
            exit 0
        fi
    fi
    
    local remove_db=false
    local remove_nodes=false
    
    if [[ "$YES_MODE" != true ]]; then
        if confirm "Remove database? (node records will be lost)" "n"; then
            remove_db=true
        fi
        
        local node_count=$(db_node_count)
        if [[ "$node_count" -gt 0 ]]; then
            if confirm "Remove all managed nodes ($node_count nodes)?" "n"; then
                remove_nodes=true
            fi
        fi
    fi
    
    echo ""
    
    # Remove nodes if requested
    if [[ "$remove_nodes" == true ]]; then
        print_info "Removing all nodes..."
        local nodes=$(db_node_list)
        
        while IFS='|' read -r name service_port xray_port method install_dir data_dir status; do
            print_info "Removing node: $name"
            
            if [[ "$method" == "docker" ]]; then
                docker_node_uninstall "$name" "$install_dir" "$data_dir" true
            else
                systemd_node_uninstall "$name" "$install_dir" "$data_dir" true
            fi
        done <<< "$nodes"
    fi
    
    # Remove database if requested
    if [[ "$remove_db" == true ]]; then
        print_info "Removing database..."
        db_destroy
        rm -rf "$MANAGER_DATA_DIR"
    fi
    
    # Remove CLI symlink
    print_info "Removing CLI symlink..."
    rm -f "/usr/local/bin/marzban-node-manager"
    
    # Remove installation directory
    print_info "Removing installation directory..."
    rm -rf "$MANAGER_INSTALL_DIR"
    
    print_success "Marzban Node Manager uninstalled"
    
    if [[ "$remove_nodes" != true ]]; then
        local node_count=$(db_node_count 2>/dev/null || echo 0)
        if [[ "$node_count" -gt 0 ]]; then
            print_warning "Note: $node_count node(s) are still running and were not removed"
        fi
    fi
}

# =============================================================================
# Main
# =============================================================================

main() {
    # Parse command line arguments
    parse_args "$@"
    
    # Check if operation is specified
    if [[ -z "$OPERATION" ]]; then
        show_help
        exit 0
    fi
    
    # Ensure database is initialized
    db_ensure
    
    # Execute operation
    case "$OPERATION" in
        install)
            cmd_install
            ;;
        uninstall)
            cmd_uninstall
            ;;
        edit)
            cmd_edit
            ;;
        status)
            cmd_status
            ;;
        start)
            cmd_start
            ;;
        stop)
            cmd_stop
            ;;
        restart)
            cmd_restart
            ;;
        logs)
            cmd_logs
            ;;
        list)
            cmd_list
            ;;
        update)
            cmd_update
            ;;
        update-cli)
            cmd_update_cli
            ;;
        uninstall-cli)
            cmd_uninstall_cli
            ;;
        *)
            print_error "Unknown operation: $OPERATION"
            show_help
            exit 1
            ;;
    esac
}

# Run main function
main "$@"

