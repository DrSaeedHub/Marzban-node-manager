#!/usr/bin/env bash
# =============================================================================
# Marzban Node Manager - Color Output Utilities
# =============================================================================
# Provides colorized output functions for better readability
# =============================================================================

# Color codes
readonly COLOR_RESET='\033[0m'
readonly COLOR_BOLD='\033[1m'
readonly COLOR_DIM='\033[2m'
readonly COLOR_UNDERLINE='\033[4m'

# Regular colors
readonly COLOR_RED='\033[0;31m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[0;33m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_MAGENTA='\033[0;35m'
readonly COLOR_CYAN='\033[0;36m'
readonly COLOR_WHITE='\033[0;37m'

# Bold colors
readonly COLOR_BOLD_RED='\033[1;31m'
readonly COLOR_BOLD_GREEN='\033[1;32m'
readonly COLOR_BOLD_YELLOW='\033[1;33m'
readonly COLOR_BOLD_BLUE='\033[1;34m'
readonly COLOR_BOLD_MAGENTA='\033[1;35m'
readonly COLOR_BOLD_CYAN='\033[1;36m'
readonly COLOR_BOLD_WHITE='\033[1;37m'

# Background colors
readonly COLOR_BG_RED='\033[41m'
readonly COLOR_BG_GREEN='\033[42m'
readonly COLOR_BG_YELLOW='\033[43m'
readonly COLOR_BG_BLUE='\033[44m'

# Status symbols
readonly SYMBOL_SUCCESS="✓"
readonly SYMBOL_ERROR="✗"
readonly SYMBOL_WARNING="⚠"
readonly SYMBOL_INFO="ℹ"
readonly SYMBOL_ARROW="➜"
readonly SYMBOL_DOT_FILLED="●"
readonly SYMBOL_DOT_EMPTY="○"

# =============================================================================
# Output Functions
# =============================================================================

# Print colored text
# Usage: color_echo <color> <text> [style]
color_echo() {
    local color="$1"
    local text="$2"
    local style="${3:-0}"
    
    case "$color" in
        red)      printf "\033[${style};31m%s\033[0m\n" "$text" ;;
        green)    printf "\033[${style};32m%s\033[0m\n" "$text" ;;
        yellow)   printf "\033[${style};33m%s\033[0m\n" "$text" ;;
        blue)     printf "\033[${style};34m%s\033[0m\n" "$text" ;;
        magenta)  printf "\033[${style};35m%s\033[0m\n" "$text" ;;
        cyan)     printf "\033[${style};36m%s\033[0m\n" "$text" ;;
        white)    printf "\033[${style};37m%s\033[0m\n" "$text" ;;
        *)        echo "$text" ;;
    esac
}

# Print success message
# Usage: print_success <message>
print_success() {
    printf "${COLOR_BOLD_GREEN}${SYMBOL_SUCCESS} %s${COLOR_RESET}\n" "$1"
}

# Print error message
# Usage: print_error <message>
print_error() {
    printf "${COLOR_BOLD_RED}${SYMBOL_ERROR} %s${COLOR_RESET}\n" "$1" >&2
}

# Print warning message
# Usage: print_warning <message>
print_warning() {
    printf "${COLOR_BOLD_YELLOW}${SYMBOL_WARNING} %s${COLOR_RESET}\n" "$1"
}

# Print info message
# Usage: print_info <message>
print_info() {
    printf "${COLOR_BOLD_BLUE}${SYMBOL_INFO} %s${COLOR_RESET}\n" "$1"
}

# Print step message (for installation steps)
# Usage: print_step <step_number> <message>
print_step() {
    local step="$1"
    local message="$2"
    printf "${COLOR_BOLD_CYAN}[%s]${COLOR_RESET} %s\n" "$step" "$message"
}

# Print header
# Usage: print_header <title>
print_header() {
    local title="$1"
    local width=60
    local padding=$(( (width - ${#title}) / 2 ))
    
    printf "\n${COLOR_BOLD_BLUE}"
    printf '═%.0s' $(seq 1 $width)
    printf "\n"
    printf "%*s%s%*s\n" $padding "" "$title" $padding ""
    printf '═%.0s' $(seq 1 $width)
    printf "${COLOR_RESET}\n\n"
}

# Print sub-header
# Usage: print_subheader <title>
print_subheader() {
    local title="$1"
    printf "\n${COLOR_BOLD_CYAN}── %s ──${COLOR_RESET}\n\n" "$title"
}

# Print key-value pair
# Usage: print_kv <key> <value>
print_kv() {
    local key="$1"
    local value="$2"
    printf "  ${COLOR_CYAN}%-20s${COLOR_RESET} %s\n" "$key:" "$value"
}

# Print separator line
# Usage: print_separator [width]
print_separator() {
    local width="${1:-60}"
    printf "${COLOR_DIM}"
    printf '─%.0s' $(seq 1 $width)
    printf "${COLOR_RESET}\n"
}

# Print box around text
# Usage: print_box <text>
print_box() {
    local text="$1"
    local width=$((${#text} + 4))
    
    printf "${COLOR_CYAN}┌"
    printf '─%.0s' $(seq 1 $((width - 2)))
    printf "┐\n"
    printf "│ %s │\n" "$text"
    printf "└"
    printf '─%.0s' $(seq 1 $((width - 2)))
    printf "┘${COLOR_RESET}\n"
}

# Print status indicator
# Usage: print_status <status> <message>
# status: up, down, error, warning
print_status() {
    local status="$1"
    local message="$2"
    
    case "$status" in
        up|running|active)
            printf "${COLOR_BOLD_GREEN}${SYMBOL_DOT_FILLED}${COLOR_RESET} %s ${COLOR_GREEN}(Running)${COLOR_RESET}\n" "$message"
            ;;
        down|stopped|inactive)
            printf "${COLOR_DIM}${SYMBOL_DOT_EMPTY}${COLOR_RESET} %s ${COLOR_DIM}(Stopped)${COLOR_RESET}\n" "$message"
            ;;
        error|failed)
            printf "${COLOR_BOLD_RED}${SYMBOL_DOT_FILLED}${COLOR_RESET} %s ${COLOR_RED}(Error)${COLOR_RESET}\n" "$message"
            ;;
        warning)
            printf "${COLOR_BOLD_YELLOW}${SYMBOL_DOT_FILLED}${COLOR_RESET} %s ${COLOR_YELLOW}(Warning)${COLOR_RESET}\n" "$message"
            ;;
        *)
            printf "${COLOR_DIM}${SYMBOL_DOT_EMPTY}${COLOR_RESET} %s\n" "$message"
            ;;
    esac
}

# Print progress spinner
# Usage: spin_start "message" & SPIN_PID=$!; <command>; spin_stop $SPIN_PID
spin_start() {
    local message="${1:-Processing}"
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    
    while true; do
        printf "\r${COLOR_CYAN}${spin:$i:1}${COLOR_RESET} %s..." "$message"
        i=$(( (i + 1) % ${#spin} ))
        sleep 0.1
    done
}

spin_stop() {
    local pid="$1"
    kill "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    printf "\r"
}

# Print table row
# Usage: print_table_row <col1> <col2> <col3> ...
print_table_row() {
    local format="│ %-12s │ %-10s │ %-12s │ %-8s │ %-18s │\n"
    printf "$format" "$@"
}

# Print table header
# Usage: print_table_header <col1> <col2> <col3> ...
print_table_header() {
    local top="┌──────────────┬────────────┬──────────────┬──────────┬────────────────────┐"
    local mid="├──────────────┼────────────┼──────────────┼──────────┼────────────────────┤"
    local bot="└──────────────┴────────────┴──────────────┴──────────┴────────────────────┘"
    
    printf "${COLOR_CYAN}%s${COLOR_RESET}\n" "$top"
    printf "${COLOR_BOLD}"
    print_table_row "$@"
    printf "${COLOR_RESET}"
    printf "${COLOR_CYAN}%s${COLOR_RESET}\n" "$mid"
}

# Print table footer
print_table_footer() {
    local bot="└──────────────┴────────────┴──────────────┴──────────┴────────────────────┘"
    printf "${COLOR_CYAN}%s${COLOR_RESET}\n" "$bot"
}

# Prompt for confirmation
# Usage: confirm "message" [default: y/n]
# Returns: 0 for yes, 1 for no
confirm() {
    local message="$1"
    local default="${2:-n}"
    local prompt
    
    if [[ "$default" == "y" ]]; then
        prompt="[Y/n]"
    else
        prompt="[y/N]"
    fi
    
    printf "${COLOR_YELLOW}? %s %s ${COLOR_RESET}" "$message" "$prompt"
    read -r response
    
    case "$response" in
        [yY][eE][sS]|[yY])
            return 0
            ;;
        [nN][oO]|[nN])
            return 1
            ;;
        "")
            [[ "$default" == "y" ]] && return 0 || return 1
            ;;
        *)
            return 1
            ;;
    esac
}

# Prompt for input
# Usage: prompt_input "message" [default]
# Sets: REPLY variable
prompt_input() {
    local message="$1"
    local default="$2"
    
    if [[ -n "$default" ]]; then
        printf "${COLOR_CYAN}? %s [%s]: ${COLOR_RESET}" "$message" "$default"
    else
        printf "${COLOR_CYAN}? %s: ${COLOR_RESET}" "$message"
    fi
    
    read -r REPLY
    
    if [[ -z "$REPLY" && -n "$default" ]]; then
        REPLY="$default"
    fi
}

# Print banner
print_banner() {
    printf "${COLOR_BOLD_CYAN}"
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
    printf "${COLOR_RESET}\n"
}

# Print mini banner (for help screens)
print_mini_banner() {
    printf "${COLOR_BOLD_CYAN}Marzban Node Manager${COLOR_RESET} - "
    printf "${COLOR_DIM}Manage multiple Marzban nodes easily${COLOR_RESET}\n"
}

