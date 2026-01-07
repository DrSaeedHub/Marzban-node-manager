#!/usr/bin/env bash
# =============================================================================
# Marzban Node Manager - Database Operations
# =============================================================================
# Provides SQLite database operations for node management
# =============================================================================

# Source utils for constants
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh" 2>/dev/null || true

# Database file location
DB_FILE="${MANAGER_DB_FILE:-/var/lib/marzban-node-manager/nodes.db}"

# =============================================================================
# Database Initialization
# =============================================================================

# Initialize the database schema
db_init() {
    ensure_dir "$(dirname "$DB_FILE")"
    
    sqlite3 "$DB_FILE" <<EOF
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
    
    if [[ $? -eq 0 ]]; then
        log_info "Database initialized at $DB_FILE"
        return 0
    else
        log_error "Failed to initialize database"
        return 1
    fi
}

# Check if database exists
db_exists() {
    [[ -f "$DB_FILE" ]]
}

# Ensure database is initialized
db_ensure() {
    if ! db_exists; then
        db_init
    fi
}

# =============================================================================
# Node CRUD Operations
# =============================================================================

# Create a new node record
# Usage: db_node_create <name> <service_port> <xray_api_port> <method> <install_dir> <data_dir> [cert_file]
db_node_create() {
    local name="$1"
    local service_port="$2"
    local xray_api_port="$3"
    local method="$4"
    local install_dir="$5"
    local data_dir="$6"
    local cert_file="${7:-}"
    
    db_ensure
    
    sqlite3 "$DB_FILE" <<EOF
INSERT INTO nodes (name, service_port, xray_api_port, method, install_dir, data_dir, cert_file)
VALUES ('$name', $service_port, $xray_api_port, '$method', '$install_dir', '$data_dir', '$cert_file');
EOF
    
    if [[ $? -eq 0 ]]; then
        log_info "Created node record: $name"
        return 0
    else
        log_error "Failed to create node record: $name"
        return 1
    fi
}

# Get node by name
# Usage: db_node_get <name>
# Output: id|name|service_port|xray_api_port|method|install_dir|data_dir|cert_file|created_at|updated_at|status
db_node_get() {
    local name="$1"
    
    db_ensure
    
    sqlite3 -separator '|' "$DB_FILE" <<EOF
SELECT id, name, service_port, xray_api_port, method, install_dir, data_dir, cert_file, created_at, updated_at, status
FROM nodes
WHERE name = '$name';
EOF
}

# Get node by ID
db_node_get_by_id() {
    local id="$1"
    
    db_ensure
    
    sqlite3 -separator '|' "$DB_FILE" <<EOF
SELECT id, name, service_port, xray_api_port, method, install_dir, data_dir, cert_file, created_at, updated_at, status
FROM nodes
WHERE id = $id;
EOF
}

# Check if node exists
db_node_exists() {
    local name="$1"
    
    db_ensure
    
    local count=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM nodes WHERE name = '$name';")
    [[ "$count" -gt 0 ]]
}

# List all nodes
# Output: name|service_port|xray_api_port|method|status (one per line)
db_node_list() {
    db_ensure
    
    sqlite3 -separator '|' "$DB_FILE" <<EOF
SELECT name, service_port, xray_api_port, method, install_dir, data_dir, status
FROM nodes
ORDER BY created_at;
EOF
}

# Get node count
db_node_count() {
    db_ensure
    
    sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM nodes;"
}

# Update node
# Usage: db_node_update <name> <field> <value>
db_node_update() {
    local name="$1"
    local field="$2"
    local value="$3"
    
    db_ensure
    
    # Validate field name to prevent SQL injection
    case "$field" in
        service_port|xray_api_port|method|install_dir|data_dir|cert_file|status)
            ;;
        *)
            log_error "Invalid field: $field"
            return 1
            ;;
    esac
    
    # Handle numeric vs string values
    local sql_value
    if [[ "$field" == "service_port" || "$field" == "xray_api_port" ]]; then
        sql_value="$value"
    else
        sql_value="'$value'"
    fi
    
    sqlite3 "$DB_FILE" <<EOF
UPDATE nodes
SET $field = $sql_value, updated_at = CURRENT_TIMESTAMP
WHERE name = '$name';
EOF
    
    if [[ $? -eq 0 ]]; then
        log_info "Updated node $name: $field = $value"
        return 0
    else
        log_error "Failed to update node: $name"
        return 1
    fi
}

# Update multiple node fields
# Usage: db_node_update_multi <name> <service_port> <xray_api_port>
db_node_update_ports() {
    local name="$1"
    local service_port="$2"
    local xray_api_port="$3"
    
    db_ensure
    
    sqlite3 "$DB_FILE" <<EOF
UPDATE nodes
SET service_port = $service_port, xray_api_port = $xray_api_port, updated_at = CURRENT_TIMESTAMP
WHERE name = '$name';
EOF
    
    if [[ $? -eq 0 ]]; then
        log_info "Updated node $name ports: service=$service_port, xray=$xray_api_port"
        return 0
    else
        log_error "Failed to update node ports: $name"
        return 1
    fi
}

# Delete node
db_node_delete() {
    local name="$1"
    
    db_ensure
    
    sqlite3 "$DB_FILE" "DELETE FROM nodes WHERE name = '$name';"
    
    if [[ $? -eq 0 ]]; then
        log_info "Deleted node record: $name"
        return 0
    else
        log_error "Failed to delete node record: $name"
        return 1
    fi
}

# =============================================================================
# Port Operations
# =============================================================================

# Check if port is in database
db_port_exists() {
    local port="$1"
    
    db_ensure
    
    local count=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM nodes WHERE service_port = $port OR xray_api_port = $port;")
    [[ "$count" -gt 0 ]]
}

# Check if port is in database (excluding a specific node)
db_port_exists_except() {
    local port="$1"
    local exclude_name="$2"
    
    db_ensure
    
    local count=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM nodes WHERE (service_port = $port OR xray_api_port = $port) AND name != '$exclude_name';")
    [[ "$count" -gt 0 ]]
}

# Get all used ports from database
db_get_used_ports() {
    db_ensure
    
    sqlite3 "$DB_FILE" <<EOF
SELECT service_port FROM nodes
UNION
SELECT xray_api_port FROM nodes;
EOF
}

# Get node name by port
db_get_node_by_port() {
    local port="$1"
    
    db_ensure
    
    sqlite3 "$DB_FILE" "SELECT name FROM nodes WHERE service_port = $port OR xray_api_port = $port LIMIT 1;"
}

# Get next available service port
db_get_next_service_port() {
    db_ensure
    
    local max_port=$(sqlite3 "$DB_FILE" "SELECT COALESCE(MAX(service_port), $((DEFAULT_SERVICE_PORT - PORT_INCREMENT))) FROM nodes;")
    echo $((max_port + PORT_INCREMENT))
}

# Get next available xray api port
db_get_next_xray_port() {
    db_ensure
    
    local max_port=$(sqlite3 "$DB_FILE" "SELECT COALESCE(MAX(xray_api_port), $((DEFAULT_XRAY_API_PORT - PORT_INCREMENT))) FROM nodes;")
    echo $((max_port + PORT_INCREMENT))
}

# =============================================================================
# Config Operations
# =============================================================================

# Get config value
db_config_get() {
    local key="$1"
    local default="${2:-}"
    
    db_ensure
    
    local value=$(sqlite3 "$DB_FILE" "SELECT value FROM config WHERE key = '$key';")
    
    if [[ -n "$value" ]]; then
        echo "$value"
    else
        echo "$default"
    fi
}

# Set config value
db_config_set() {
    local key="$1"
    local value="$2"
    
    db_ensure
    
    sqlite3 "$DB_FILE" <<EOF
INSERT OR REPLACE INTO config (key, value) VALUES ('$key', '$value');
EOF
}

# Delete config value
db_config_delete() {
    local key="$1"
    
    db_ensure
    
    sqlite3 "$DB_FILE" "DELETE FROM config WHERE key = '$key';"
}

# =============================================================================
# Utility Functions
# =============================================================================

# Parse node record into variables
# Usage: parse_node_record <record>
# Sets: NODE_ID, NODE_NAME, NODE_SERVICE_PORT, NODE_XRAY_PORT, NODE_METHOD, 
#       NODE_INSTALL_DIR, NODE_DATA_DIR, NODE_CERT_FILE, NODE_CREATED, NODE_UPDATED, NODE_STATUS
parse_node_record() {
    local record="$1"
    
    IFS='|' read -r NODE_ID NODE_NAME NODE_SERVICE_PORT NODE_XRAY_PORT NODE_METHOD \
                   NODE_INSTALL_DIR NODE_DATA_DIR NODE_CERT_FILE NODE_CREATED \
                   NODE_UPDATED NODE_STATUS <<< "$record"
    
    export NODE_ID NODE_NAME NODE_SERVICE_PORT NODE_XRAY_PORT NODE_METHOD \
           NODE_INSTALL_DIR NODE_DATA_DIR NODE_CERT_FILE NODE_CREATED \
           NODE_UPDATED NODE_STATUS
}

# Get node field
# Usage: db_node_get_field <name> <field>
db_node_get_field() {
    local name="$1"
    local field="$2"
    
    db_ensure
    
    sqlite3 "$DB_FILE" "SELECT $field FROM nodes WHERE name = '$name';"
}

# Export database to JSON (for backup/debugging)
db_export_json() {
    db_ensure
    
    sqlite3 -json "$DB_FILE" "SELECT * FROM nodes;"
}

# Get database file path
db_get_path() {
    echo "$DB_FILE"
}

# Get database size
db_get_size() {
    if db_exists; then
        du -h "$DB_FILE" | cut -f1
    else
        echo "0"
    fi
}

# Vacuum database (optimize)
db_vacuum() {
    db_ensure
    sqlite3 "$DB_FILE" "VACUUM;"
    log_info "Database vacuumed"
}

# Delete database file
db_destroy() {
    if db_exists; then
        rm -f "$DB_FILE"
        log_info "Database destroyed"
    fi
}

