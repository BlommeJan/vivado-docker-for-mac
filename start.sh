#!/bin/bash
# Start the Vivado desktop container and print the browser URL.
. "$(dirname "$0")/docker/common.sh"

require_env
ensure_docker
if running; then
    say "Already running"
else
    port_in_use "${NOVNC_PORT:-6080}" \
        && die "Port ${NOVNC_PORT:-6080} is already used by another program. Set NOVNC_PORT in .env (e.g. 6081)."
    docker compose up -d --wait || die "Container failed to start. Details: docker compose logs   Check: ./doctor.sh"
fi

vivado_installed || warn "Vivado ${VIVADO_VERSION} is not installed yet; run ./install.sh."
has_license || warn "No license in ${LICENSE_DIR}; Vivado ${VIVADO_VERSION} won't start without one (see ./install.sh)."
mem=$(gb "$(docker info --format '{{.MemTotal}}' 2>/dev/null || echo 0)")
[ "$mem" -ge 8 ] || warn "Docker has only ${mem} GB of memory; Vivado may crash. Run ./doctor.sh to see how to raise it."

echo
echo "Open: $(novnc_url)"
