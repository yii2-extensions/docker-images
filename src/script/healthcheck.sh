#!/bin/bash
set -euo pipefail

#==============================================================================
# Container healthcheck (Docker HEALTHCHECK)
#
# Requests the loopback-only internal endpoint, which is served by Apache and
# executed by PHP-FPM. It is independent of the SSL redirect, the application
# rewrite rules and ENABLE_HEALTH_ENDPOINT. Exits non-zero when Apache or
# PHP-FPM cannot answer.
#==============================================================================

response="$(curl --fail --silent --show-error --max-time 3 --user-agent healthcheck http://127.0.0.1/__health)"

if [[ "$response" != *'"status": "healthy"'* ]]; then
    echo "healthcheck: unexpected response: ${response:0:200}" >&2
    exit 1
fi
