#!/bin/bash
#==============================================================================
# Logging Functionality
#==============================================================================

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    case "$level" in
        ERROR) echo -e "${RED}[${timestamp}]${NC} ${RED}ERROR:${NC} $message" >&2 ;;
        WARNING|WARN) echo -e "${YELLOW}[${timestamp}]${NC} ${YELLOW}WARN:${NC} $message" >&2 ;;
        SUCCESS) echo -e "${GREEN}[${timestamp}]${NC} ${GREEN}OK:${NC} $message" >&2 ;;
        INFO) echo -e "${BLUE}[${timestamp}]${NC} ${CYAN}INFO:${NC} $message" >&2 ;;
        DEBUG)
            if [[ "${DEBUG_ENTRYPOINT:-false}" == "true" ]]; then
                echo -e "${MAGENTA}[${timestamp}]${NC} ${MAGENTA}DEBUG:${NC} $message" >&2
            fi
            ;;
        *)       echo -e "[${timestamp}] $message" >&2 ;;
    esac
}
