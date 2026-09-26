#!/bin/bash
# Set up this repo on this machine and install Vivado. Safe to re-run: finished steps are skipped.
#   1. checks Docker (and Rosetta on Apple Silicon), memory, CPUs, swap and disk
#   2. creates/updates .env (VNC password, fixed MAC for the license, UID/GID on Linux)
#   3. builds the image
#   4. installs Vivado from the .bin in the installer folder (asks for your AMD login)
#
#   ./install.sh            full setup
#   ./install.sh --reconfig regenerate installer/install_config.txt (e.g. after changing VIVADO_DEVICES)
. "$(dirname "$0")/docker/common.sh"

case "${1:-}" in
    ''|--reconfig) ;;
    -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "Unknown option: $1 (see ./install.sh --help)" ;;
esac

say "Host: $PLATFORM"

# --- 1. Docker ----------------------------------------------------------------
ensure_docker

# --- 2. .env ------------------------------------------------------------------
# Rebuild .env from .env.example, keeping existing values (new settings get their defaults).
if [ -f .env ]; then
    tmp=$(mktemp)
    awk '
        NR == FNR { if ($0 !~ /^#/ && index($0, "=")) { k = substr($0, 1, index($0, "=") - 1); old[k] = $0; order[++n] = k }; next }
        !/^#/ && index($0, "=") { k = substr($0, 1, index($0, "=") - 1); if (k in old) { print old[k]; used[k] = 1; next } }
        { print }
        END { for (i = 1; i <= n; i++) if (!(order[i] in used)) { if (!hdr++) print "\n# Other settings"; print old[order[i]] } }
    ' .env .env.example > "$tmp"
    cat "$tmp" > .env && rm -f "$tmp"
else
    cp .env.example .env
    say "Created .env from .env.example"
fi
chmod 600 .env
load_env

if [ -z "${CONTAINER_MAC:-}" ]; then
    # Locally administered unicast MAC, unique per machine
    mac=$(od -An -N5 -tx1 /dev/urandom | tr -s ' ' ':' | sed 's/^:/02:/; s/:$//')
    set_env CONTAINER_MAC "$mac"
    say "Generated container MAC $mac (your license host ID)"
fi

case "$PLATFORM" in
    linux-*|wsl)
        [ "${HOST_UID:-}" = "$(id -u)" ] || set_env HOST_UID "$(id -u)"
        [ "${HOST_GID:-}" = "$(id -g)" ] || set_env HOST_GID "$(id -g)"
        ;;
esac

if [ -z "${VNC_PASSWORD:-}" ] || [ "$VNC_PASSWORD" = "CHANGE_ME" ]; then
    [ -t 0 ] || die "Run ./install.sh in an interactive terminal to set the VNC password."
    while :; do
        read -r -s -p "Choose a VNC password for the browser desktop (6-8 characters): " pw1; echo
        read -r -s -p "Repeat it: " pw2; echo
        if [ "$pw1" != "$pw2" ]; then echo "Passwords don't match."
        elif [ ${#pw1} -lt 6 ] || [ ${#pw1} -gt 8 ]; then echo "Use 6-8 characters."
        else case "$pw1" in *"'"*) echo "Don't use the ' character." ;; *) break ;; esac
        fi
    done
    # Single quotes: Docker Compose takes the value literally (no $ interpolation)
    set_env VNC_PASSWORD "'$pw1'"
    export VNC_PASSWORD="$pw1"
    unset pw1 pw2
    say "Saved VNC password in .env"
fi

mkdir -p "${XILINX_DIR:-./xilinx}" "${INSTALLER_DIR:-./installer}" "${LICENSE_DIR:-./license}" "${WORK_DIR:-.}"
# Keep Spotlight from indexing the tens of GB of Vivado files
[ "$(uname -s)" = Darwin ] && touch "${XILINX_DIR:-./xilinx}/.metadata_never_index"

# SELinux (Fedora, RHEL, ...) blocks bind mounts unless they are relabeled
if [ "$PLATFORM" = linux-x86 ] && [ "$(getenforce 2>/dev/null)" = Enforcing ] && [ -z "${SELINUX_RELABEL:-}" ]; then
    set_env SELINUX_RELABEL 1
    say "SELinux is enforcing: mounted folders will be relabeled (SELINUX_RELABEL=1)"
fi

# --- 3. Host checks -----------------------------------------------------------
say "Checking this computer (run ./doctor.sh any time to see this again)"
resource_report || die "Fix the problem above and run ./install.sh again."

# --- 4. Image -----------------------------------------------------------------
say "Building the image vivado-desktop:${VIVADO_VERSION}"
docker compose build || die "Image build failed."

# --- 5. Vivado ----------------------------------------------------------------
if vivado_installed && [ "${1:-}" != --reconfig ]; then
    say "Vivado ${VIVADO_VERSION} is already installed in ${XILINX_DIR}"
else
    shopt -s nullglob
    bins=("${INSTALLER_DIR:-./installer}"/*"${VIVADO_VERSION}"*Lin64.bin)
    shopt -u nullglob
    if [ ${#bins[@]} -eq 0 ]; then
        cat <<EOF

Next: download the Vivado installer, then run ./install.sh again
  1. Open https://www.xilinx.com/support/download.html and pick version ${VIVADO_VERSION}.
  2. Download "AMD Unified Installer for FPGAs & Adaptive SoCs ${VIVADO_VERSION}:
     Linux Self Extracting Web Installer" (~300 MB, FPGAs_AdaptiveSoCs_Unified_SDI_${VIVADO_VERSION}_*_Lin64.bin).
     Take the LINUX one, also on macOS or Windows: it runs inside the container.
     AMD asks you to sign in (create a free AMD account if needed) and to fill in a
     name/address form once (US export rules). Students: your university as company is fine.
  3. Put the .bin file in: ${INSTALLER_DIR}/
EOF
        exit 0
    fi
    [ -t 0 ] || die "Run ./install.sh in an interactive terminal: the Vivado install asks for your AMD login."
    cat <<EOF

About to install Vivado ${VIVADO_VERSION}. What will happen:
  - You'll see the install plan (only ${VIVADO_DEVICES}) and confirm it.
  - The installer asks for your AMD account: "User ID" = your AMD e-mail, then your password.
    The password isn't shown while typing. It goes only to AMD's installer and is not saved.
  - You accept AMD's license agreements (EULA).
  - It downloads and installs ~60 GB into ${XILINX_DIR}. This takes 30-90+ minutes,
    depending on your internet and computer. Keep the terminal open.
EOF
    running || docker compose up -d --wait >/dev/null || die "Container failed to start (see: docker compose logs)."
    if [ "${1:-}" = --reconfig ]; then
        docker compose exec -it vivado install-vivado.sh config || exit 1
        exit 0
    fi
    docker compose exec -it vivado install-vivado.sh install || die "Vivado install did not complete."
fi

# --- 6. License ---------------------------------------------------------------
host_id=$(printf '%s' "$CONTAINER_MAC" | tr -d ':')
if has_license && license_matches_mac; then
    say "License found in ${LICENSE_DIR} (host ID ${host_id} matches)"
elif has_license; then
    warn "There is a license in ${LICENSE_DIR}, but it is not for host ID ${host_id} (CONTAINER_MAC in .env)."
    echo "  Vivado won't accept it. Generate a new one for ${host_id} (see README.md > License), or"
    echo "  if the license is for another MAC you own, put that MAC in CONTAINER_MAC in .env."
else
    cat <<EOF

Next: get your free Vivado license. From 2026.1, Vivado won't start without one.
  1. Go to https://www.xilinx.com/getlicense and sign in with your AMD account.
  2. Select the free "Vivado Basic" license and choose "Generate Node-Locked License".
  3. Add a host:  Operating system: Linux 64-bit
                  Host ID type:     Ethernet MAC
                  Host ID value:    ${host_id}
     (this is the container's fixed MAC from .env, not your computer's)
  4. Download the license file (Xilinx.lic; it's also e-mailed to you) and put it in:
     ${LICENSE_DIR}/
  More detail: README.md > License.
EOF
fi

echo
say "Setup done. Start with ./start.sh"
