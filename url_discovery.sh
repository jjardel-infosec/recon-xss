#!/usr/bin/env bash

set -u
set -o pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

OUTPUT_DIR=""
INPUT_FILE=""
ROOT_DOMAIN=""
MODE=""

SUBDOMAINS_FILE=""
LIVE_HOSTS_FILE=""
URLS_RAW_FILE=""
URLS_UNIQUE_FILE=""
URLS_PARAMS_FILE=""
PIPELINE_LOG=""

TMP_DIR=""
STDIN_BUFFER=""
ENUMERATION_BUFFER=""
ARCHIVE_BUFFER=""
CRAWL_BUFFER=""

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
ICON_INPUT="[?]"

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

chaos_api_key() {
    if [ -n "${CHAOS_KEY:-}" ]; then
        printf '%s' "$CHAOS_KEY"
        return 0
    fi

    if [ -n "${CHAOS_API_KEY:-}" ]; then
        printf '%s' "$CHAOS_API_KEY"
        return 0
    fi

    return 1
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
    printf '%b URL Discovery Pipeline%b\n' "${COLOR_CYAN}${COLOR_BOLD}" "$COLOR_RESET"
    printf '%b Subdomains -> Live Hosts -> URLs%b\n' "$COLOR_DIM" "$COLOR_RESET"
    printf '%b%s%b\n\n' "${COLOR_CYAN}${COLOR_BOLD}" "$line" "$COLOR_RESET"
}

print_stage() {
    local title="$1"
    local line="------------------------------------------------------------"

    printf '\n%b%s%b\n' "${COLOR_MAGENTA}${COLOR_BOLD}" "$line" "$COLOR_RESET"
    printf '%b%s%b %b%s%b\n' "${COLOR_MAGENTA}${COLOR_BOLD}" "$ICON_STAGE" "$COLOR_RESET" "${COLOR_MAGENTA}${COLOR_BOLD}" "$title" "$COLOR_RESET"
    printf '%b%s%b\n' "${COLOR_MAGENTA}${COLOR_BOLD}" "$line" "$COLOR_RESET"

    if [ -n "$PIPELINE_LOG" ]; then
        printf '[%s] [STAGE] %s\n' "$(timestamp)" "$title" >> "$PIPELINE_LOG"
    fi
}

usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [-f subdomains.txt] [-o output_dir] [-d root-domain]

Modes:
  Interactive root-domain mode: run without stdin or -f
  Existing subdomain file mode: $SCRIPT_NAME -f subdomains.txt
  STDIN mode: cat subdomains.txt | $SCRIPT_NAME

Options:
  -f, --file      Existing file with subdomains/hosts/URLs
    -o, --output    Output directory (default: $HOME/03-Links-Params)
  -d, --domain    Root domain to use without prompting
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

    if [ -n "$PIPELINE_LOG" ]; then
        printf '%s\n' "$plain_line" >> "$PIPELINE_LOG"
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

line_count() {
    local file_path="$1"
    if [ -f "$file_path" ]; then
        wc -l < "$file_path" | tr -d ' '
    else
        printf '0\n'
    fi
}

cleanup() {
    if [ -n "${TMP_DIR:-}" ] && [ -d "$TMP_DIR" ]; then
        rm -rf "$TMP_DIR"
    fi
}

trap cleanup EXIT INT TERM

setup_workspace() {
    if [ -z "$OUTPUT_DIR" ]; then
        OUTPUT_DIR="$HOME/03-Links-Params"
    fi

    mkdir -p "$OUTPUT_DIR"

    PIPELINE_LOG="$OUTPUT_DIR/pipeline.log"
    SUBDOMAINS_FILE="$OUTPUT_DIR/subdomains_unique.txt"
    LIVE_HOSTS_FILE="$OUTPUT_DIR/live_hosts.txt"
    URLS_RAW_FILE="$OUTPUT_DIR/urls_raw.txt"
    URLS_UNIQUE_FILE="$OUTPUT_DIR/urls_unique.txt"
    URLS_PARAMS_FILE="$OUTPUT_DIR/urls_with_params.txt"

    : > "$PIPELINE_LOG"
    : > "$SUBDOMAINS_FILE"
    : > "$LIVE_HOSTS_FILE"
    : > "$URLS_RAW_FILE"
    : > "$URLS_UNIQUE_FILE"
    : > "$URLS_PARAMS_FILE"

    if command_exists mktemp; then
        TMP_DIR="$(mktemp -d -t url-discovery.XXXXXX 2>/dev/null || true)"
    fi

    if [ -z "$TMP_DIR" ]; then
        TMP_DIR="$OUTPUT_DIR/.tmp_${TIMESTAMP}_$$"
        mkdir -p "$TMP_DIR"
    fi

    STDIN_BUFFER="$TMP_DIR/stdin.txt"
    ENUMERATION_BUFFER="$TMP_DIR/subdomains_raw.txt"
    ARCHIVE_BUFFER="$TMP_DIR/archive_urls.txt"
    CRAWL_BUFFER="$TMP_DIR/crawl_urls.txt"

    : > "$STDIN_BUFFER"
    : > "$ENUMERATION_BUFFER"
    : > "$ARCHIVE_BUFFER"
    : > "$CRAWL_BUFFER"
}

sanitize_targets_file() {
    local source_file="$1"

    awk '
    function trim(value) {
        sub(/^[[:space:]]+/, "", value)
        sub(/[[:space:]]+$/, "", value)
        return value
    }
    {
        line = trim($0)
        gsub(/\r/, "", line)
        if (line == "") {
            next
        }

        sub(/^https?:\/\//, "", line)
        sub(/^\*\./, "", line)
        sub(/\/.*$/, "", line)
        sub(/:.*$/, "", line)
        line = tolower(line)

        if (line ~ /^[a-z0-9._-]+$/) {
            print line
        }
    }
    ' "$source_file" | LC_ALL=C sort -u
}

normalize_url_file() {
    local source_file="$1"

    awk '
    function trim(value) {
        sub(/^[[:space:]]+/, "", value)
        sub(/[[:space:]]+$/, "", value)
        return value
    }
    {
        raw = trim($0)
        gsub(/\r/, "", raw)
        if (raw == "") {
            next
        }

        if (match(raw, /https?:\/\/[^[:space:]]+/)) {
            line = substr(raw, RSTART, RLENGTH)
        } else {
            next
        }

        sub(/#.*/, "", line)
        if (line == "") {
            next
        }

        if (line ~ /^https:\/\//) {
            scheme = "https://"
            rest = substr(line, 9)
        } else {
            scheme = "http://"
            rest = substr(line, 8)
        }

        slash_index = index(rest, "/")
        if (slash_index == 0) {
            host = rest
            path = ""
        } else {
            host = substr(rest, 1, slash_index - 1)
            path = substr(rest, slash_index)
        }

        host = tolower(host)

        if (scheme == "http://") {
            sub(/:80$/, "", host)
        }
        if (scheme == "https://") {
            sub(/:443$/, "", host)
        }

        if (path == "/") {
            path = ""
        }
        if (path != "" && path ~ /\/$/ && path !~ /\?/) {
            sub(/\/$/, "", path)
        }

        sub(/\?$/, "", path)
        sub(/&$/, "", path)

        print scheme host path
    }
    ' "$source_file"
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -f|--file)
                shift
                if [ "$#" -eq 0 ]; then
                    printf 'Missing value for --file\n' >&2
                    exit 1
                fi
                INPUT_FILE="$1"
                ;;
            -o|--output)
                shift
                if [ "$#" -eq 0 ]; then
                    printf 'Missing value for --output\n' >&2
                    exit 1
                fi
                OUTPUT_DIR="$1"
                ;;
            -d|--domain)
                shift
                if [ "$#" -eq 0 ]; then
                    printf 'Missing value for --domain\n' >&2
                    exit 1
                fi
                ROOT_DOMAIN="$1"
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

detect_mode() {
    if [ -n "$INPUT_FILE" ]; then
        MODE="file"
        return
    fi

    if [ ! -t 0 ]; then
        MODE="stdin"
        return
    fi

    MODE="interactive"
}

warn_missing_dependencies() {
    local installer_script="$SCRIPT_DIR/install_tools.sh"
    local enum_missing=()
    local probe_missing=()
    local url_missing=()
    local chaos_key=""
    local has_enumerator=0
    local tool=""

    if [ "$MODE" = "interactive" ]; then
        for tool in subfinder assetfinder findomain; do
            if command_exists "$tool"; then
                has_enumerator=1
            else
                enum_missing+=("$tool")
            fi
        done

        chaos_key="$(chaos_api_key 2>/dev/null || true)"
        if [ -n "$chaos_key" ]; then
            if command_exists chaos; then
                has_enumerator=1
            else
                log_warn "CHAOS_KEY/CHAOS_API_KEY detected but chaos is not installed. Chaos will be skipped."
            fi
        fi
    fi

    for tool in httpx; do
        if ! command_exists "$tool"; then
            probe_missing+=("$tool")
        fi
    done

    for tool in waybackurls gau waymore katana hakrawler xnLinkFinder; do
        if ! command_exists "$tool"; then
            url_missing+=("$tool")
        fi
    done

    if [ "${#enum_missing[@]}" -gt 0 ]; then
        log_warn "Interactive mode is missing enumeration tools: $(join_by ', ' "${enum_missing[@]}")"
        if [ "$has_enumerator" -eq 0 ]; then
            log_warn "No enumeration tools are available. Use file/STDIN mode or install the missing tools."
        fi
    fi

    if [ "${#probe_missing[@]}" -gt 0 ]; then
        log_warn "Probing tools missing: $(join_by ', ' "${probe_missing[@]}"). live_hosts.txt may be empty."
    fi

    if [ "${#url_missing[@]}" -gt 0 ]; then
        log_warn "URL collection tools missing: $(join_by ', ' "${url_missing[@]}"). URL coverage may be reduced."
        if [ "${#url_missing[@]}" -eq 6 ]; then
            log_warn "No URL collection tools are available. URL output files will likely remain empty."
        fi
    fi

    if [ "${#enum_missing[@]}" -gt 0 ] || [ "${#probe_missing[@]}" -gt 0 ] || [ "${#url_missing[@]}" -gt 0 ]; then
        if [ -f "$installer_script" ]; then
            log_info "Install missing dependencies with: $installer_script"
        else
            log_info "Install the missing dependencies before the next run for fuller results."
        fi
    fi
}

normalize_root_domain() {
    ROOT_DOMAIN="$(printf '%s' "$ROOT_DOMAIN" | sed -E 's#^https?://##; s#/$##; s#^\*\.##' | tr '[:upper:]' '[:lower:]')"
}

load_targets_from_file() {
    if [ ! -f "$INPUT_FILE" ]; then
        log_error "Input file not found: $INPUT_FILE"
        exit 1
    fi

    sanitize_targets_file "$INPUT_FILE" > "$SUBDOMAINS_FILE"
    log_info "Loaded $(line_count "$SUBDOMAINS_FILE") unique targets from file mode."
}

load_targets_from_stdin() {
    cat > "$STDIN_BUFFER"

    sanitize_targets_file "$STDIN_BUFFER" > "$SUBDOMAINS_FILE"
    log_info "Loaded $(line_count "$SUBDOMAINS_FILE") unique targets from STDIN mode."
}

prompt_for_root_domain() {
    if [ -z "$ROOT_DOMAIN" ]; then
        printf '%b%s%b ' "${COLOR_MAGENTA}${COLOR_BOLD}" "$ICON_INPUT Root domain:" "$COLOR_RESET" >&2
        IFS= read -r ROOT_DOMAIN
    fi

    normalize_root_domain

    if [ -z "$ROOT_DOMAIN" ]; then
        log_error "A root domain is required for interactive mode."
        exit 1
    fi
}

run_subfinder() {
    local domain="$1"

    if command_exists subfinder; then
        log_info "Running subfinder against $domain"
        subfinder -silent -d "$domain" >> "$ENUMERATION_BUFFER" 2>> "$PIPELINE_LOG" || log_warn "subfinder failed."
    else
        log_warn "subfinder not found. Skipping."
    fi
}

run_assetfinder() {
    local domain="$1"

    if command_exists assetfinder; then
        log_info "Running assetfinder against $domain"
        assetfinder --subs-only "$domain" >> "$ENUMERATION_BUFFER" 2>> "$PIPELINE_LOG" || log_warn "assetfinder failed."
    else
        log_warn "assetfinder not found. Skipping."
    fi
}

run_findomain() {
    local domain="$1"

    if command_exists findomain; then
        log_info "Running findomain against $domain"
        findomain -t "$domain" -q >> "$ENUMERATION_BUFFER" 2>> "$PIPELINE_LOG" || log_warn "findomain failed."
    else
        log_warn "findomain not found. Skipping."
    fi
}

run_chaos() {
    local domain="$1"
    local chaos_key=""

    chaos_key="$(chaos_api_key 2>/dev/null || true)"
    if [ -z "$chaos_key" ]; then
        log_info "CHAOS_KEY/CHAOS_API_KEY not set. Skipping chaos."
        return 0
    fi

    if command_exists chaos; then
        log_info "Running chaos against $domain"
        chaos -d "$domain" -key "$chaos_key" -silent >> "$ENUMERATION_BUFFER" 2>> "$PIPELINE_LOG" || log_warn "chaos failed."
    else
        log_warn "chaos not found. Skipping."
    fi
}

enumerate_subdomains() {
    local domain="$1"

    print_stage "Subdomain Enumeration"

    : > "$ENUMERATION_BUFFER"

    run_subfinder "$domain"
    run_assetfinder "$domain"
    run_findomain "$domain"
    run_chaos "$domain"

    sanitize_targets_file "$ENUMERATION_BUFFER" > "$SUBDOMAINS_FILE"
    log_info "Saved $(line_count "$SUBDOMAINS_FILE") unique subdomains after enumeration."
}

probe_live_hosts() {
    print_stage "Live Host Probing"

    : > "$LIVE_HOSTS_FILE"

    if [ ! -s "$SUBDOMAINS_FILE" ]; then
        log_warn "No targets available for probing."
        return 0
    fi

    if ! command_exists httpx; then
        log_warn "httpx not found. live_hosts.txt will be empty."
        return 0
    fi

    log_info "Probing live hosts with httpx"
    if httpx -silent -l "$SUBDOMAINS_FILE" 2>> "$PIPELINE_LOG" | awk 'NF' | LC_ALL=C sort -u > "$LIVE_HOSTS_FILE"; then
        log_info "Saved $(line_count "$LIVE_HOSTS_FILE") live hosts."
    else
        log_warn "httpx failed. Continuing with an empty live host list."
        : > "$LIVE_HOSTS_FILE"
    fi
}

collect_waybackurls() {
    if ! command_exists waybackurls; then
        log_warn "waybackurls not found. Skipping."
        return 0
    fi

    if [ ! -s "$SUBDOMAINS_FILE" ]; then
        log_warn "Skipping waybackurls because there are no targets."
        return 0
    fi

    log_info "Collecting URLs with waybackurls"
    waybackurls < "$SUBDOMAINS_FILE" >> "$ARCHIVE_BUFFER" 2>> "$PIPELINE_LOG" || log_warn "waybackurls failed."
}

collect_gau() {
    if ! command_exists gau; then
        log_warn "gau not found. Skipping."
        return 0
    fi

    if [ ! -s "$SUBDOMAINS_FILE" ]; then
        log_warn "Skipping gau because there are no targets."
        return 0
    fi

    log_info "Collecting URLs with gau"
    gau < "$SUBDOMAINS_FILE" >> "$ARCHIVE_BUFFER" 2>> "$PIPELINE_LOG" || log_warn "gau failed."
}

collect_waymore() {
    local target=""
    local waymore_output=""

    if ! command_exists waymore; then
        log_warn "waymore not found. Skipping."
        return 0
    fi

    if [ ! -s "$SUBDOMAINS_FILE" ]; then
        log_warn "Skipping waymore because there are no targets."
        return 0
    fi

    log_info "Collecting URLs with waymore"
    while IFS= read -r target; do
        [ -n "$target" ] || continue
        waymore_output="$(mktemp "$TMP_DIR/waymore.XXXXXX")"
        if waymore -i "$target" -mode U -oU "$waymore_output" >> "$PIPELINE_LOG" 2>&1; then
            cat "$waymore_output" >> "$ARCHIVE_BUFFER"
        else
            log_warn "waymore failed for $target"
        fi
        rm -f "$waymore_output"
    done < "$SUBDOMAINS_FILE"
}

collect_katana() {
    if ! command_exists katana; then
        log_warn "katana not found. Skipping."
        return 0
    fi

    if [ ! -s "$LIVE_HOSTS_FILE" ]; then
        log_warn "Skipping katana because there are no live hosts."
        return 0
    fi

    log_info "Collecting URLs with katana"
    katana -list "$LIVE_HOSTS_FILE" -silent >> "$CRAWL_BUFFER" 2>> "$PIPELINE_LOG" || log_warn "katana failed."
}

collect_hakrawler() {
    if ! command_exists hakrawler; then
        log_warn "hakrawler not found. Skipping."
        return 0
    fi

    if [ ! -s "$LIVE_HOSTS_FILE" ]; then
        log_warn "Skipping hakrawler because there are no live hosts."
        return 0
    fi

    log_info "Collecting URLs with hakrawler"
    hakrawler -plain -depth 2 -subs < "$LIVE_HOSTS_FILE" >> "$CRAWL_BUFFER" 2>> "$PIPELINE_LOG" || log_warn "hakrawler failed."
}

collect_xnlinkfinder() {
    local target=""

    if ! command_exists xnLinkFinder; then
        log_warn "xnLinkFinder not found. Skipping."
        return 0
    fi

    if [ ! -s "$LIVE_HOSTS_FILE" ]; then
        log_warn "Skipping xnLinkFinder because there are no live hosts."
        return 0
    fi

    log_info "Collecting URLs with xnLinkFinder"
    while IFS= read -r target; do
        [ -n "$target" ] || continue
        xnLinkFinder -i "$target" -o cli >> "$CRAWL_BUFFER" 2>> "$PIPELINE_LOG" || log_warn "xnLinkFinder failed for $target"
    done < "$LIVE_HOSTS_FILE"
}

merge_and_finalize_urls() {
    cat "$ARCHIVE_BUFFER" "$CRAWL_BUFFER" | awk 'NF' > "$URLS_RAW_FILE"

    normalize_url_file "$URLS_RAW_FILE" | LC_ALL=C sort -u > "$URLS_UNIQUE_FILE"

    grep -F '?' "$URLS_UNIQUE_FILE" > "$URLS_PARAMS_FILE" || : > "$URLS_PARAMS_FILE"

    log_info "Saved $(line_count "$URLS_RAW_FILE") raw URL rows."
    log_info "Saved $(line_count "$URLS_UNIQUE_FILE") normalized unique URLs."
    log_info "Saved $(line_count "$URLS_PARAMS_FILE") parameterized URLs."
}

collect_urls() {
    print_stage "URL Collection"

    : > "$ARCHIVE_BUFFER"
    : > "$CRAWL_BUFFER"

    collect_waybackurls
    collect_gau
    collect_waymore
    collect_katana
    collect_hakrawler
    collect_xnlinkfinder

    merge_and_finalize_urls
}

print_summary() {
    print_stage "Run Summary"

    log_success "Pipeline complete. Output directory: $OUTPUT_DIR"
    log_info "subdomains_unique.txt: $(line_count "$SUBDOMAINS_FILE") lines"
    log_info "live_hosts.txt: $(line_count "$LIVE_HOSTS_FILE") lines"
    log_info "urls_raw.txt: $(line_count "$URLS_RAW_FILE") lines"
    log_info "urls_unique.txt: $(line_count "$URLS_UNIQUE_FILE") lines"
    log_info "urls_with_params.txt: $(line_count "$URLS_PARAMS_FILE") lines"
    log_info "pipeline.log: $PIPELINE_LOG"
}

main() {
    initialize_ui
    parse_args "$@"
    detect_mode
    setup_workspace

    print_banner

    log_info "Selected mode: $MODE"

    if [ -n "$INPUT_FILE" ] && [ ! -t 0 ]; then
        log_warn "STDIN detected together with --file. Ignoring STDIN and using file mode."
    fi

    print_stage "Dependency Check"
    warn_missing_dependencies

    case "$MODE" in
        file)
            load_targets_from_file
            ;;
        stdin)
            load_targets_from_stdin
            ;;
        interactive)
            prompt_for_root_domain
            enumerate_subdomains "$ROOT_DOMAIN"
            ;;
        *)
            log_error "Unknown mode: $MODE"
            exit 1
            ;;
    esac

    if [ ! -s "$SUBDOMAINS_FILE" ]; then
        log_warn "No targets collected. Output files were created but later stages may be empty."
    fi

    probe_live_hosts
    collect_urls
    print_summary
}

main "$@"