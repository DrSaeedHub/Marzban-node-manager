#!/usr/bin/env bash
# =============================================================================
# Marzban Node Manager - Port Management
# =============================================================================
# Provides port availability checking and auto-allocation functionality
# =============================================================================

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/database.sh" 2>/dev/null || true

# =============================================================================
# System Port Detection
# =============================================================================

# Get list of ports currently in use on the system
get_system_ports() {
    local ports=""
    
    if command -v ss &>/dev/null; then
        # Using ss (preferred, faster)
        ports=$(ss -tuln 2>/dev/null | awk 'NR>1 {print $5}' | grep -oE '[0-9]+$' | sort -n | uniq)
    elif command -v netstat &>/dev/null; then
        # Fallback to netstat
        ports=$(netstat -tuln 2>/dev/null | awk '{print $4}' | grep -oE '[0-9]+$' | sort -n | uniq)
    else
        # Try to install net-tools
        print_warning "Neither ss nor netstat found. Installing net-tools..."
        install_package net-tools >/dev/null 2>&1
        
        if command -v netstat &>/dev/null; then
            ports=$(netstat -tuln 2>/dev/null | awk '{print $4}' | grep -oE '[0-9]+$' | sort -n | uniq)
        else
            print_error "Cannot detect system ports. Please install ss or netstat."
            return 1
        fi
    fi
    
    echo "$ports"
}

# Check if a port is in use on the system
is_port_in_use_system() {
    local port="$1"
    local system_ports
    
    system_ports=$(get_system_ports)
    
    if echo "$system_ports" | grep -qw "^${port}$"; then
        return 0  # Port is in use
    fi
    
    return 1  # Port is free
}

# Alternative method using direct connection test
is_port_listening() {
    local port="$1"
    local host="${2:-127.0.0.1}"
    
    if command -v nc &>/dev/null; then
        nc -z "$host" "$port" 2>/dev/null
        return $?
    elif command -v timeout &>/dev/null; then
        timeout 1 bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null
        return $?
    else
        # Fallback: use /dev/tcp
        (echo >/dev/tcp/"$host"/"$port") 2>/dev/null
        return $?
    fi
}

# =============================================================================
# Combined Port Checking
# =============================================================================

# Check if port is available (not in system AND not in our database)
# Returns: 0 if available, 1 if not
is_port_available() {
    local port="$1"
    local exclude_node="${2:-}"  # Optional: exclude this node name from DB check
    
    # First, validate port
    if ! validate_port "$port" 2>/dev/null; then
        return 1
    fi
    
    # Check if port is in use on system
    if is_port_in_use_system "$port"; then
        return 1
    fi
    
    # Check if port exists in our database
    if [[ -n "$exclude_node" ]]; then
        if db_port_exists_except "$port" "$exclude_node"; then
            return 1
        fi
    else
        if db_port_exists "$port"; then
            return 1
        fi
    fi
    
    return 0  # Port is available
}

# Check port and return detailed status
# Usage: check_port_status <port> [exclude_node]
# Output: available|system|database|invalid
check_port_status() {
    local port="$1"
    local exclude_node="${2:-}"
    
    # Validate port
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [[ "$port" -lt 1 || "$port" -gt 65535 ]]; then
        echo "invalid"
        return
    fi
    
    # Check system
    if is_port_in_use_system "$port"; then
        echo "system"
        return
    fi
    
    # Check database
    if [[ -n "$exclude_node" ]]; then
        if db_port_exists_except "$port" "$exclude_node"; then
            echo "database"
            return
        fi
    else
        if db_port_exists "$port"; then
            echo "database"
            return
        fi
    fi
    
    echo "available"
}

# Get detailed port conflict information
get_port_conflict_info() {
    local port="$1"
    
    local status=$(check_port_status "$port")
    
    case "$status" in
        invalid)
            echo "Port $port is invalid (must be 1-65535)"
            ;;
        system)
            echo "Port $port is already in use on the system"
            ;;
        database)
            local node_name=$(db_get_node_by_port "$port")
            echo "Port $port is allocated to node '$node_name'"
            ;;
        available)
            echo "Port $port is available"
            ;;
    esac
}

# =============================================================================
# Port Allocation
# =============================================================================

# Find next available port starting from a given port
# Usage: find_available_port <start_port> [exclude_node]
find_available_port() {
    local start_port="$1"
    local exclude_node="${2:-}"
    local max_attempts=100
    local port="$start_port"
    
    for ((i=0; i<max_attempts; i++)); do
        if is_port_available "$port" "$exclude_node"; then
            echo "$port"
            return 0
        fi
        port=$((port + 1))
    done
    
    # If still no port found, try random ports in high range
    for ((i=0; i<max_attempts; i++)); do
        port=$((RANDOM % 10000 + 50000))  # Range: 50000-60000
        if is_port_available "$port" "$exclude_node"; then
            echo "$port"
            return 0
        fi
    done
    
    return 1  # No available port found
}

# Allocate a pair of ports for a new node
# Usage: allocate_node_ports [exclude_node]
# Sets: ALLOCATED_SERVICE_PORT, ALLOCATED_XRAY_PORT
allocate_node_ports() {
    local exclude_node="${1:-}"
    
    # Get suggested ports from database
    local suggested_service=$(db_get_next_service_port)
    local suggested_xray=$(db_get_next_xray_port)
    
    # Find available service port
    ALLOCATED_SERVICE_PORT=$(find_available_port "$suggested_service" "$exclude_node")
    if [[ -z "$ALLOCATED_SERVICE_PORT" ]]; then
        print_error "Could not find available SERVICE_PORT"
        return 1
    fi
    
    # Find available xray port (ensure it's different from service port)
    suggested_xray=$((ALLOCATED_SERVICE_PORT + 1))
    ALLOCATED_XRAY_PORT=$(find_available_port "$suggested_xray" "$exclude_node")
    if [[ -z "$ALLOCATED_XRAY_PORT" ]]; then
        print_error "Could not find available XRAY_API_PORT"
        return 1
    fi
    
    # Ensure ports are different
    if [[ "$ALLOCATED_SERVICE_PORT" -eq "$ALLOCATED_XRAY_PORT" ]]; then
        ALLOCATED_XRAY_PORT=$(find_available_port "$((ALLOCATED_XRAY_PORT + 1))" "$exclude_node")
    fi
    
    export ALLOCATED_SERVICE_PORT ALLOCATED_XRAY_PORT
    return 0
}

# =============================================================================
# Port Validation for User Input
# =============================================================================

# Validate user-provided port (checks system and database)
# Usage: validate_user_port <port> [exclude_node] [port_type]
# Returns: 0 if valid and available, 1 otherwise
validate_user_port() {
    local port="$1"
    local exclude_node="${2:-}"
    local port_type="${3:-port}"  # For error messages
    
    # Basic validation
    if ! validate_port "$port"; then
        return 1
    fi
    
    # Check availability
    local status=$(check_port_status "$port" "$exclude_node")
    
    case "$status" in
        available)
            return 0
            ;;
        system)
            print_error "$port_type $port is already in use on the system"
            return 1
            ;;
        database)
            local node_name=$(db_get_node_by_port "$port")
            print_error "$port_type $port is already allocated to node '$node_name'"
            return 1
            ;;
        invalid)
            print_error "$port_type $port is invalid"
            return 1
            ;;
    esac
}

# Validate a pair of ports
# Usage: validate_port_pair <service_port> <xray_port> [exclude_node]
validate_port_pair() {
    local service_port="$1"
    local xray_port="$2"
    local exclude_node="${3:-}"
    
    # Check both ports
    if ! validate_user_port "$service_port" "$exclude_node" "SERVICE_PORT"; then
        return 1
    fi
    
    if ! validate_user_port "$xray_port" "$exclude_node" "XRAY_API_PORT"; then
        return 1
    fi
    
    # Ensure ports are different
    if [[ "$service_port" -eq "$xray_port" ]]; then
        print_error "SERVICE_PORT and XRAY_API_PORT cannot be the same"
        return 1
    fi
    
    return 0
}

# =============================================================================
# Interactive Port Selection
# =============================================================================

# Prompt user for port with validation
# Usage: prompt_port <prompt_message> <default> [exclude_node] [port_type]
# Sets: SELECTED_PORT
prompt_port() {
    local message="$1"
    local default="$2"
    local exclude_node="${3:-}"
    local port_type="${4:-Port}"
    
    while true; do
        prompt_input "$message" "$default"
        local port="$REPLY"
        
        if [[ -z "$port" ]]; then
            port="$default"
        fi
        
        if validate_user_port "$port" "$exclude_node" "$port_type"; then
            SELECTED_PORT="$port"
            export SELECTED_PORT
            return 0
        fi
        
        print_info "Please choose a different port"
    done
}

# =============================================================================
# Port Information Display
# =============================================================================

# Display port usage summary
show_port_usage() {
    print_subheader "Port Usage Summary"
    
    # Get all nodes and their ports
    local nodes=$(db_node_list)
    
    if [[ -z "$nodes" ]]; then
        print_info "No nodes registered"
        return
    fi
    
    echo "Ports allocated to managed nodes:"
    echo ""
    
    while IFS='|' read -r name service_port xray_port method install_dir data_dir status; do
        printf "  ${COLOR_CYAN}%-20s${COLOR_RESET} SERVICE: %-6s  XRAY: %-6s\n" "$name" "$service_port" "$xray_port"
    done <<< "$nodes"
    
    echo ""
}

# Show port range suggestion
suggest_port_range() {
    local suggested_service=$(db_get_next_service_port)
    local suggested_xray=$(db_get_next_xray_port)
    
    print_info "Suggested ports for next node:"
    printf "  SERVICE_PORT:  ${COLOR_GREEN}%s${COLOR_RESET}\n" "$suggested_service"
    printf "  XRAY_API_PORT: ${COLOR_GREEN}%s${COLOR_RESET}\n" "$suggested_xray"
}

