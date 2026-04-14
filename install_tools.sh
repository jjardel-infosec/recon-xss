#!/usr/bin/env bash

set -u
set -o pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/install_tools.log"
CHECK_ONLY=0
APT_UPDATED=0

INSTALLED_TOOLS=()
MISSING_TOOLS=()

COLOR_RESET=""
COLOR_BOLD=""
COLOR_DIM=""
COLOR_BLUE=""
COLOR_GREEN=""
COLOR_YELLOW=""
COLOR_RED=""
COLOR_MAGENTA=""
COLOR_CYAN=""

ICON_INFO="[*]"
ICON_SUCCESS="[+]"
ICON_WARN="[!]"
ICON_ERROR="[-]"
ICON_STAGE="[>]"

join_by() {
    local delimiter="$1"
    shift
    local item=""
    local output=""

    for item in "$@"; do
        if [ -z "$output" ]; then
            output="$item"
        else
            output="$output$delimiter$item"
        fi
    done

    printf '%s' "$output"
}

initialize_ui() {
    if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-}" != "dumb" ]; then
        COLOR_RESET=$'\033[0m'
        COLOR_BOLD=$'\033[1m'
        COLOR_DIM=$'\033[2m'
        COLOR_BLUE=$'\033[34m'
        COLOR_GREEN=$'\033[32m'
        COLOR_YELLOW=$'\033[33m'
        COLOR_RED=$'\033[31m'
        COLOR_MAGENTA=$'\033[35m'
        COLOR_CYAN=$'\033[36m'
    fi
}

format_console_line() {
    local level="$1"
    shift
    local message="$*"
    local color="${COLOR_CYAN}${COLOR_BOLD}"
    local icon="$ICON_INFO"

    case "$level" in
        INFO)
            color="${COLOR_BLUE}${COLOR_BOLD}"
            icon="$ICON_INFO"
            ;;
        WARN)
            color="${COLOR_YELLOW}${COLOR_BOLD}"
            icon="$ICON_WARN"
            ;;
        ERROR)
            color="${COLOR_RED}${COLOR_BOLD}"
            icon="$ICON_ERROR"
            ;;
        SUCCESS)
            color="${COLOR_GREEN}${COLOR_BOLD}"
            icon="$ICON_SUCCESS"
            ;;
    esac

    printf '%b[%s]%b %b%s%b %s' "$COLOR_DIM" "$(timestamp)" "$COLOR_RESET" "$color" "$icon" "$COLOR_RESET" "$message"
}

print_banner() {
    local line="============================================================"

    printf '\n%b%s%b\n' "${COLOR_CYAN}${COLOR_BOLD}" "$line" "$COLOR_RESET"
    printf '%b Dependency Installer%b\n' "${COLOR_CYAN}${COLOR_BOLD}" "$COLOR_RESET"
    printf '%b Verify and bootstrap URL discovery tooling%b\n' "$COLOR_DIM" "$COLOR_RESET"
    printf '%b%s%b\n\n' "${COLOR_CYAN}${COLOR_BOLD}" "$line" "$COLOR_RESET"
}

print_stage() {
    local title="$1"
    local line="------------------------------------------------------------"

    printf '\n%b%s%b\n' "${COLOR_MAGENTA}${COLOR_BOLD}" "$line" "$COLOR_RESET"
    printf '%b%s%b %b%s%b\n' "${COLOR_MAGENTA}${COLOR_BOLD}" "$ICON_STAGE" "$COLOR_RESET" "${COLOR_MAGENTA}${COLOR_BOLD}" "$title" "$COLOR_RESET"
    printf '%b%s%b\n' "${COLOR_MAGENTA}${COLOR_BOLD}" "$line" "$COLOR_RESET"

    if [ -n "$LOG_FILE" ]; then
        printf '[%s] [STAGE] %s\n' "$(timestamp)" "$title" >> "$LOG_FILE"
    fi
}

usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [--check-only]

Checks whether the required URL discovery tools are installed.
If a tool is missing, the script attempts to install it.

Options:
  --check-only    Only report missing tools without installing them
  -h, --help      Show this help text
EOF
}

timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

log() {
    local level="$1"
    shift
    local message="$*"
    local plain_line="[$(timestamp)] [$level] $message"
    local console_line=""

    if [ -n "$LOG_FILE" ]; then
        printf '%s\n' "$plain_line" >> "$LOG_FILE"
    fi

    console_line="$(format_console_line "$level" "$message")"

    if [ "$level" = "ERROR" ]; then
        printf '%b\n' "$console_line" >&2
    else
        printf '%b\n' "$console_line"
    fi
}

log_info() {
    log "INFO" "$@"
}

log_warn() {
    log "WARN" "$@"
}

log_error() {
    log "ERROR" "$@"
}

log_success() {
    log "SUCCESS" "$@"
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --check-only)
                CHECK_ONLY=1
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                printf 'Unknown argument: %s\n\n' "$1" >&2
                usage >&2
                exit 1
                ;;
        esac
        shift
    done
}

ensure_linux() {
    if [ "$(uname -s)" != "Linux" ]; then
        log_error "This installer targets Kali/Debian-style Linux systems."
        exit 1
    fi
}

ensure_user_paths() {
    mkdir -p "$HOME/go/bin" "$HOME/.local/bin"
    export PATH="$HOME/go/bin:$HOME/.local/bin:$PATH"
}

run_as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
        return $?
    fi

    if command_exists sudo; then
        sudo "$@"
        return $?
    fi

    log_error "Root privileges are required for apt operations, and sudo is not available."
    return 1
}

apt_update_once() {
    if [ "$APT_UPDATED" -eq 1 ]; then
        return 0
    fi

    if ! command_exists apt-get; then
        log_warn "apt-get not found. Automatic apt installs are unavailable."
        return 1
    fi

    log_info "Running apt-get update"
    if run_as_root apt-get update >> "$LOG_FILE" 2>&1; then
        APT_UPDATED=1
        return 0
    fi

    log_warn "apt-get update failed."
    return 1
}

install_apt_packages() {
    local packages=("$@")

    if [ "${#packages[@]}" -eq 0 ]; then
        return 0
    fi

    if ! command_exists apt-get; then
        log_warn "apt-get not found. Cannot install: ${packages[*]}"
        return 1
    fi

    if ! apt_update_once; then
        return 1
    fi

    log_info "Installing apt packages: ${packages[*]}"
    if run_as_root apt-get install -y "${packages[@]}" >> "$LOG_FILE" 2>&1; then
        return 0
    fi

    log_warn "Failed to install apt packages: ${packages[*]}"
    return 1
}

ensure_core_dependencies() {
    local packages=()

    command_exists curl || packages+=("curl")
    command_exists git || packages+=("git")
    command_exists python3 || packages+=("python3")
    command_exists go || packages+=("golang-go")
    command_exists pipx || packages+=("pipx")

    if ! command_exists python3 || ! python3 -m pip --version >/dev/null 2>&1; then
        packages+=("python3-pip")
    fi

    if ! command_exists python3 || ! python3 -m venv --help >/dev/null 2>&1; then
        packages+=("python3-venv")
    fi

    if [ "${#packages[@]}" -eq 0 ]; then
        log_info "Core dependencies already available."
        return 0
    fi

    install_apt_packages "${packages[@]}" || log_warn "Some core dependencies could not be installed automatically."
}

record_installed() {
    INSTALLED_TOOLS+=("$1")
}

record_missing() {
    MISSING_TOOLS+=("$1")
}

check_or_install_apt_tool() {
    local tool_name="$1"
    local package_name="$2"

    if command_exists "$tool_name"; then
        log_info "$tool_name is already installed."
        record_installed "$tool_name"
        return 0
    fi

    if [ "$CHECK_ONLY" -eq 1 ]; then
        log_warn "$tool_name is missing."
        record_missing "$tool_name"
        return 1
    fi

    if install_apt_packages "$package_name" && command_exists "$tool_name"; then
        log_success "$tool_name installed successfully via apt."
        record_installed "$tool_name"
        return 0
    fi

    log_warn "$tool_name is still missing after apt installation attempt."
    record_missing "$tool_name"
    return 1
}

check_or_install_go_tool() {
    local tool_name="$1"
    local module_ref="$2"

    if command_exists "$tool_name"; then
        log_info "$tool_name is already installed."
        record_installed "$tool_name"
        return 0
    fi

    if [ "$CHECK_ONLY" -eq 1 ]; then
        log_warn "$tool_name is missing."
        record_missing "$tool_name"
        return 1
    fi

    if ! command_exists go; then
        log_warn "Go is not available. Unable to install $tool_name."
        record_missing "$tool_name"
        return 1
    fi

    log_info "Installing $tool_name with go install"
    if GO111MODULE=on go install "$module_ref" >> "$LOG_FILE" 2>&1; then
        hash -r
    else
        log_warn "go install failed for $tool_name"
    fi

    if command_exists "$tool_name" || [ -x "$HOME/go/bin/$tool_name" ]; then
        log_success "$tool_name installed successfully via Go."
        record_installed "$tool_name"
        return 0
    fi

    log_warn "$tool_name is still missing after Go installation attempt."
    record_missing "$tool_name"
    return 1
}

check_or_install_python_tool() {
    local tool_name="$1"
    local package_ref="$2"

    if command_exists "$tool_name"; then
        log_info "$tool_name is already installed."
        record_installed "$tool_name"
        return 0
    fi

    if [ "$CHECK_ONLY" -eq 1 ]; then
        log_warn "$tool_name is missing."
        record_missing "$tool_name"
        return 1
    fi

    if command_exists pipx; then
        log_info "Installing $tool_name with pipx"
        pipx install --force "$package_ref" >> "$LOG_FILE" 2>&1 || log_warn "pipx installation failed for $tool_name"
    elif command_exists python3; then
        log_info "Installing $tool_name with python3 -m pip --user"
        python3 -m pip install --user --upgrade "$package_ref" >> "$LOG_FILE" 2>&1 || log_warn "pip installation failed for $tool_name"
    else
        log_warn "Python tooling is not available. Unable to install $tool_name."
    fi

    hash -r

    if command_exists "$tool_name" || [ -x "$HOME/.local/bin/$tool_name" ]; then
        log_success "$tool_name installed successfully via Python tooling."
        record_installed "$tool_name"
        return 0
    fi

    log_warn "$tool_name is still missing after Python installation attempt."
    record_missing "$tool_name"
    return 1
}

check_required_tools() {
    check_or_install_go_tool "subfinder" "github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest"
    check_or_install_go_tool "assetfinder" "github.com/tomnomnom/assetfinder@latest"
    check_or_install_apt_tool "findomain" "findomain"
    check_or_install_go_tool "chaos" "github.com/projectdiscovery/chaos-client/cmd/chaos@latest"
    check_or_install_go_tool "httpx" "github.com/projectdiscovery/httpx/cmd/httpx@latest"
    check_or_install_go_tool "waybackurls" "github.com/tomnomnom/waybackurls@latest"
    check_or_install_go_tool "gau" "github.com/lc/gau/v2/cmd/gau@latest"
    check_or_install_python_tool "waymore" "git+https://github.com/xnl-h4ck3r/waymore.git"
    check_or_install_go_tool "katana" "github.com/projectdiscovery/katana/cmd/katana@latest"
    check_or_install_go_tool "hakrawler" "github.com/hakluke/hakrawler@latest"
    check_or_install_python_tool "xnLinkFinder" "git+https://github.com/xnl-h4ck3r/xnLinkFinder.git"
}

print_summary() {
    print_stage "Installer Summary"
    log_info "Installation log: $LOG_FILE"

    if [ "${#INSTALLED_TOOLS[@]}" -gt 0 ]; then
        log_info "Available tools: $(join_by ', ' "${INSTALLED_TOOLS[@]}")"
    fi

    if [ "${#MISSING_TOOLS[@]}" -gt 0 ]; then
        log_warn "Missing tools: $(join_by ', ' "${MISSING_TOOLS[@]}")"
        log_info "Add these paths in a new shell if commands are not found:"
        log_info 'export PATH="$HOME/go/bin:$HOME/.local/bin:$PATH"'
        return 1
    fi

    log_success "All required tools are available."
    log_info "If a new shell does not find the commands, export:"
    log_info 'export PATH="$HOME/go/bin:$HOME/.local/bin:$PATH"'

    return 0
}

main() {
    initialize_ui
    parse_args "$@"
    : > "$LOG_FILE"
    print_banner
    ensure_linux
    ensure_user_paths

    log_info "Starting tool verification"
    if [ "$CHECK_ONLY" -eq 1 ]; then
        log_info "Check-only mode enabled. No installation will be performed."
    else
        print_stage "Core Dependencies"
        ensure_core_dependencies
    fi

    print_stage "Required Tools"
    check_required_tools
    print_summary
}

main "$@"