# Marzban Node Manager

A professional CLI tool for installing, configuring, and managing multiple Marzban-node instances on a single server.

## Features

- **Easy Installation**: One-line installation with all dependencies handled automatically
- **Multiple Nodes**: Install and manage multiple Marzban nodes on the same server
- **Two Installation Methods**: 
  - Docker (recommended, default)
  - Normal (systemd service)
- **Automatic Port Management**: Auto-detects and allocates available ports
- **SQLite Database**: Tracks all nodes and their configurations
- **Port Conflict Detection**: Prevents port conflicts between nodes and system services
- **Non-Interactive Mode**: Full automation support with `-y` flag
- **Colored Output**: Easy-to-read terminal output

## Quick Start

### Installation

```bash
bash <(curl -Ls https://raw.githubusercontent.com/DrSaeedHub/Marzban-node-manager/main/install-cli.sh)
```

### Install Your First Node

```bash
# Interactive mode - will prompt for certificate
marzban-node-manager install -n mynode

# With certificate file
marzban-node-manager install -n mynode -c /path/to/ssl_client_cert.pem

# With custom ports
marzban-node-manager install -n mynode -s 62060 -x 62061 -c cert.pem

# Using normal (systemd) method instead of Docker
marzban-node-manager install -n mynode -m normal -c cert.pem
```

### Check Status

```bash
# Show all nodes
marzban-node-manager status

# Show specific node
marzban-node-manager status -n mynode
```

## CLI Reference

### Operations

| Operation | Description |
|-----------|-------------|
| `install` | Install a new Marzban node |
| `uninstall` | Remove a Marzban node |
| `edit` | Modify node configuration (ports) |
| `status` | Show node(s) status |
| `start` | Start a node |
| `stop` | Stop a node |
| `restart` | Restart a node |
| `logs` | View node logs |
| `list` | List all managed nodes |
| `update` | Update node image/code |
| `uninstall-cli` | Remove the CLI tool itself |

### Options

| Option | Short | Description |
|--------|-------|-------------|
| `--name` | `-n` | Node name (required for most operations) |
| `--service-port` | `-s` | SERVICE_PORT (auto-assigned if not provided) |
| `--xray-port` | `-x` | XRAY_API_PORT (auto-assigned if not provided) |
| `--method` | `-m` | Installation method: `docker` (default) or `normal` |
| `--cert` | `-c` | Path to ssl_client_cert.pem file |
| `--cert-content` | | Certificate content directly (for automation) |
| `--inbounds` | `-i` | Comma-separated inbound names (case-sensitive) |
| `--yes` | `-y` | Non-interactive mode (skip confirmations) |
| `--follow` | `-f` | Follow logs (for logs operation) |
| `--help` | `-h` | Show help message |

## Usage Examples

### Installing Multiple Nodes

```bash
# Install first node (ports auto-assigned: 62050, 62051)
marzban-node-manager install -n node1 -c cert1.pem -y

# Install second node (ports auto-assigned: 62060, 62061)
marzban-node-manager install -n node2 -c cert2.pem -y

# Install third node with specific ports
marzban-node-manager install -n node3 -s 63000 -x 63001 -c cert3.pem -y

# Install node with specific inbounds (case-sensitive, comma-separated)
marzban-node-manager install -n node4 -c cert4.pem -i "VLESS TCP REALITY, VMESS TCP" -y
```

### Filtering Inbounds

You can specify which inbounds from the Marzban panel a node should handle. This is useful for:
- Load balancing traffic across multiple nodes
- Dedicating nodes to specific protocols
- Separating high-traffic inbounds

```bash
# Install node that only handles specific inbounds
marzban-node-manager install -n vless-node -c cert.pem -i "VLESS TCP REALITY"

# Update existing node's inbounds
marzban-node-manager edit -n vless-node -i "VLESS TCP REALITY, VLESS WS TLS"

# Remove inbound filter (handle all inbounds)
marzban-node-manager edit -n vless-node -i ""
```

**Note:** Inbound names are case-sensitive and must match exactly with the names in your Marzban panel.

### Managing Nodes

```bash
# Stop a node
marzban-node-manager stop -n mynode

# Start a node
marzban-node-manager start -n mynode

# Restart a node
marzban-node-manager restart -n mynode

# View logs
marzban-node-manager logs -n mynode

# Follow logs in real-time
marzban-node-manager logs -n mynode -f
```

### Modifying Configuration

```bash
# Edit ports interactively
marzban-node-manager edit -n mynode

# Set new ports directly
marzban-node-manager edit -n mynode -s 62080 -x 62081 -y
```

### Automation / CI-CD

```bash
# Fully automated installation with certificate content
marzban-node-manager install \
  -n production-node \
  -s 62050 \
  -x 62051 \
  --cert-content "$(cat /path/to/cert.pem)" \
  -y

# Or with certificate file
marzban-node-manager install -n prod-node -c cert.pem -y
```

### Uninstalling

```bash
# Remove a specific node
marzban-node-manager uninstall -n mynode

# Remove node with data (non-interactive)
marzban-node-manager uninstall -n mynode -y

# Uninstall the CLI itself
marzban-node-manager uninstall-cli
```

## Port Allocation

The manager automatically handles port allocation:

- **Default starting ports**: 62050 (SERVICE_PORT), 62051 (XRAY_API_PORT)
- **Port increment**: 10 per node
- **Automatic detection**: Checks both system ports and managed nodes
- **Conflict prevention**: Refuses to use ports already in use

### Port Detection Logic

1. Check if user-provided port is in use on the system (`ss` or `netstat`)
2. Check if port is already allocated to another managed node (SQLite DB)
3. If no port provided, auto-allocate next available port

## Installation Methods

### Docker (Default)

- Uses official `gozargah/marzban-node:latest` image
- Creates docker-compose.yml in `/opt/{node-name}/`
- Data stored in `/var/lib/{node-name}/`
- Recommended for most users

### Normal (Systemd)

- Clones official Marzban-node repository
- Creates Python virtual environment
- Installs as systemd service
- Useful when Docker is not available

```bash
marzban-node-manager install -n mynode -m normal -c cert.pem
```

## Database

The manager uses SQLite to track nodes:

- **Location**: `/var/lib/marzban-node-manager/nodes.db`
- **Tables**: `nodes`, `config`
- Stores: node name, ports, method, directories, certificate paths

## Directory Structure

```
/opt/marzban-node-manager/           # CLI installation
├── marzban-node-manager.sh          # Main CLI script
└── lib/
    ├── colors.sh                    # Color output
    ├── utils.sh                     # Utilities
    ├── database.sh                  # SQLite operations
    ├── ports.sh                     # Port management
    ├── docker.sh                    # Docker operations
    └── systemd.sh                   # Systemd operations

/var/lib/marzban-node-manager/       # CLI data
└── nodes.db                         # SQLite database

/opt/{node-name}/                    # Node installation
├── docker-compose.yml               # (Docker method)
└── ...                              # (or repo files for normal method)

/var/lib/{node-name}/                # Node data
├── ssl_client_cert.pem              # Client certificate
├── ssl_cert.pem                     # Server certificate (auto-generated)
└── ssl_key.pem                      # Server key (auto-generated)
```

## Installer Options

```bash
# Install with custom CLI name
bash <(curl -Ls https://...install-cli.sh) --name mnm

# Update existing installation
bash <(curl -Ls https://...install-cli.sh) --update

# Uninstall
bash <(curl -Ls https://...install-cli.sh) --uninstall
```

## Requirements

- **OS**: Linux (Ubuntu, Debian, CentOS, Fedora, Arch, openSUSE)
- **Root access**: Required for installation and management
- **Dependencies** (auto-installed):
  - SQLite3
  - curl
  - jq
  - Docker (for docker method)
  - git, Python3 (for normal method)

## Compatibility

- Fully compatible with official [Marzban-node](https://github.com/Gozargah/Marzban-node)
- Uses same configuration format and environment variables
- Managed nodes work identically to manually installed nodes

## Troubleshooting

### Port Already in Use

```
Error: SERVICE_PORT 62050 is already in use on the system
```

Solution: Use a different port with `-s` and `-x` options

### Docker Not Running

```
Error: Docker is not running
```

Solution: Start Docker with `systemctl start docker`

### Permission Denied

```
Error: This command must be run as root
```

Solution: Run with `sudo` or as root user

### Node Not Found

```
Error: Node 'mynode' not found
```

Solution: Check node name with `marzban-node-manager list`

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Links

- [Marzban Panel](https://github.com/Gozargah/Marzban)
- [Marzban Node](https://github.com/Gozargah/Marzban-node)
- [Marzban Scripts](https://github.com/Gozargah/Marzban-scripts)

