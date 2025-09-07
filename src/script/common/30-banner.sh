#==============================================================================
# Print banner
#==============================================================================

print_banner() {
    local service_name="${SERVICE_TYPE:-apache}"
    local build="${BUILD_TYPE:-dev}"
    local php="${PHP_VERSION:-unknown}"
    echo -e "${GREEN:-}═══════════════════════════════════════════════════════════════${NC:-}" >&2
    echo -e "${GREEN:-}║${NC:-}  ${CYAN:-}Yii2 Docker Container (${service_name^^})${NC:-}" >&2
    echo -e "${GREEN:-}║${NC:-}  ${YELLOW:-}Build:${NC:-} ${build^^} | ${YELLOW:-}PHP:${NC:-} ${php} | ${YELLOW:-}User:${NC:-} $(id -un)" >&2
    echo -e "${GREEN:-}║${NC:-}  ${YELLOW:-}Environment:${NC:-} ${YII_ENV:-production} | ${YELLOW:-}Debug:${NC:-} ${YII_DEBUG:-false}" >&2
    echo -e "${GREEN:-}═══════════════════════════════════════════════════════════════${NC:-}" >&2
}
