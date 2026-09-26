#!/bin/bash
# Check this computer and the setup, and say what to change: Docker memory/CPUs/swap, Rosetta,
# disk, .env, Vivado install, license. Changes nothing.
. "$(dirname "$0")/docker/common.sh"

echo "Vivado-in-Docker check  (host: $PLATFORM)"
echo

echo "Docker"
ensure_docker
ok "Docker $(docker version --format '{{.Server.Version}}' 2>/dev/null) ($(docker_flavor)), Compose $(docker compose version --short 2>/dev/null)"
load_env || true
resource_report
echo

echo "Setup"
if [ ! -f .env ]; then
    bad "No .env yet: run ./install.sh"
else
    if [ -n "${VNC_PASSWORD:-}" ] && [ "$VNC_PASSWORD" != CHANGE_ME ]; then ok "VNC password set"
    else bad "No VNC password: run ./install.sh"; fi
    if [ -n "${CONTAINER_MAC:-}" ]; then ok "Container MAC / license host ID: $(printf '%s' "$CONTAINER_MAC" | tr -d ':')"
    else bad "No CONTAINER_MAC: run ./install.sh"; fi
fi
if docker image inspect "vivado-desktop:${VIVADO_VERSION:-2026.1}" >/dev/null 2>&1; then ok "Image vivado-desktop:${VIVADO_VERSION:-2026.1} built"
else bad "Image not built: run ./install.sh"; fi
if vivado_installed; then ok "Vivado ${VIVADO_VERSION:-2026.1} installed in ${XILINX_DIR:-./xilinx}"
elif ls "${INSTALLER_DIR:-./installer}"/*Lin64.bin >/dev/null 2>&1; then bad "Vivado not installed yet (installer found): run ./install.sh"
else bad "Vivado not installed: download the Linux installer into ${INSTALLER_DIR:-./installer}/ and run ./install.sh"; fi
if ! has_license; then
    bad "No license in ${LICENSE_DIR:-./license}/ (see README.md > License)"
elif license_matches_mac; then
    ok "License matches host ID $(printf '%s' "${CONTAINER_MAC:-}" | tr -d ':')"
else
    bad "The license in ${LICENSE_DIR:-./license}/ is not for host ID $(printf '%s' "${CONTAINER_MAC:-}" | tr -d ':') (CONTAINER_MAC in .env)"
fi
if running; then
    ok "Container running: $(novnc_url)"
elif port_in_use "${NOVNC_PORT:-6080}"; then
    bad "Port ${NOVNC_PORT:-6080} is used by another program: set NOVNC_PORT in .env to e.g. 6081"
else
    ok "Container stopped (start with ./start.sh)"
fi
