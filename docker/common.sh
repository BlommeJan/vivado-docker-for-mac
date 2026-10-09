# Shared by the host scripts (install.sh, start.sh, stop.sh, shell.sh, doctor.sh).
# Works with bash 3.2 (macOS) and newer (Linux, WSL2).
cd "$(dirname "$0")" || exit 1
export PATH="$PATH:/usr/local/bin:/Applications/Docker.app/Contents/Resources/bin"

if [ -t 1 ]; then C_B='\033[1;34m' C_Y='\033[1;33m' C_R='\033[1;31m' C_G='\033[1;32m' C_0='\033[0m'
else C_B= C_Y= C_R= C_G= C_0=; fi
say()  { printf "${C_B}==> %s${C_0}\n" "$*"; }
warn() { printf "${C_Y}WARNING: %s${C_0}\n" "$*" >&2; }
die()  { printf "${C_R}ERROR: %s${C_0}\n" "$*" >&2; exit 1; }
# Check-list lines for doctor.sh / install.sh
ok()   { printf "  ${C_G}[ OK ]${C_0} %s\n" "$*"; }
tip()  { printf "  ${C_Y}[TIP ]${C_0} %s\n" "$*"; }
bad()  { printf "  ${C_R}[FAIL]${C_0} %s\n" "$*"; }
more() { printf "         %s\n" "$@"; }

# Load .env like Docker Compose does: KEY=VALUE lines, optional quotes, nothing is executed,
# and variables already set in the environment win.
load_env() {
    [ -f .env ] || return 1
    local line key val
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in ''|'#'*) continue ;; esac
        key=${line%%=*}
        val=${line#*=}
        key=$(printf '%s' "$key" | tr -d '[:space:]')
        case "$key" in *[!A-Za-z0-9_]*|'') continue ;; esac
        val=${val%$'\r'}
        case "$val" in \"*\") val=${val#\"}; val=${val%\"} ;; \'*\') val=${val#\'}; val=${val%\'} ;; esac
        [ -n "${!key+x}" ] || export "$key=$val"
    done < .env
}

# Set KEY=VALUE in .env (adds the key if missing). VALUE may contain any characters.
set_env() {
    local key=$1 val=$2 tmp
    tmp=$(mktemp)
    awk -v k="$key" -v v="$val" '
        BEGIN { done = 0 }
        index($0, k "=") == 1 { print k "=" v; done = 1; next }
        { print }
        END { if (!done) print k "=" v }' .env > "$tmp"
    cat "$tmp" > .env && rm -f "$tmp"
    export "$key=$val"
}

# Host platform: mac-arm, mac-intel, linux-x86, linux-arm, wsl
detect_platform() {
    case "$(uname -s)-$(uname -m)" in
        Darwin-arm64)              PLATFORM=mac-arm ;;
        Darwin-*)                  PLATFORM=mac-intel ;;
        Linux-x86_64)              grep -qi microsoft /proc/version 2>/dev/null && PLATFORM=wsl || PLATFORM=linux-x86 ;;
        Linux-aarch64|Linux-arm64) PLATFORM=linux-arm ;;
        MINGW*|MSYS*|CYGWIN*)
            die "On Windows, run these scripts inside WSL2 (e.g. Ubuntu from the Microsoft Store), not in Git Bash, PowerShell or CMD. See README.md > Windows." ;;
        *)  die "Unsupported host: $(uname -s) $(uname -m)" ;;
    esac
    if [ "$PLATFORM" = wsl ]; then
        case "$(pwd)" in /mnt/*)
            warn "This folder is on the Windows drive ($(pwd)). Vivado will be very slow here. Clone the repo inside WSL instead, e.g. in ~/ (see README.md > Windows)." ;;
        esac
    fi
}
detect_platform

# Which Docker is this: desktop, orbstack, colima, engine (plain Docker Engine on Linux)
docker_flavor() {
    local ctx os
    ctx=$(docker context show 2>/dev/null)
    os=$(docker info --format '{{.OperatingSystem}}' 2>/dev/null)
    case "$ctx $os" in
        *orbstack*|*OrbStack*) echo orbstack ;;
        *colima*)              echo colima ;;
        *"Docker Desktop"*)    echo desktop ;;
        *)                     echo engine ;;
    esac
}

ensure_docker() {
    if ! command -v docker >/dev/null; then
        case "$PLATFORM" in
            mac-*) die "Docker is not installed. Install Docker Desktop: https://docs.docker.com/desktop/setup/install/mac-install/ (or OrbStack/Colima). See README.md." ;;
            wsl)   die "The docker command is missing in WSL. Install Docker Desktop for Windows and enable Settings > Resources > WSL integration for this distro. See README.md > Windows." ;;
            *)     die "Docker is not installed. Install Docker Engine: https://docs.docker.com/engine/install/ . See README.md > Linux." ;;
        esac
    fi
    docker compose version >/dev/null 2>&1 \
        || die "Docker Compose v2 is missing ('docker compose'). Linux: install the docker-compose-plugin package."
    docker info >/dev/null 2>&1 && return
    case "$PLATFORM" in
        mac-*)
            if [ -d /Applications/Docker.app ]; then
                say "Starting Docker Desktop..."
                open -a Docker
                local i
                for i in $(seq 60); do docker info >/dev/null 2>&1 && return; sleep 2; done
            fi
            die "Docker is not running. Start Docker Desktop (or OrbStack/Colima) and retry." ;;
        wsl)
            die "Docker is not reachable. Start Docker Desktop on Windows and enable Settings > Resources > WSL integration for this distro." ;;
        *)
            if docker info 2>&1 | grep -qi 'permission denied'; then
                die "No permission to use Docker. Run: sudo usermod -aG docker \$USER   then log out and back in."
            fi
            die "Docker is not running. Start it: sudo systemctl start docker" ;;
    esac
}

require_env() {
    load_env || die "No .env yet. Run ./install.sh first."
    [ -n "${CONTAINER_MAC:-}" ] || die "CONTAINER_MAC is empty in .env. Run ./install.sh."
    [ -n "${VNC_PASSWORD:-}" ] && [ "$VNC_PASSWORD" != "CHANGE_ME" ] \
        || die "VNC_PASSWORD is not set in .env. Run ./install.sh (or edit .env)."
}

novnc_url() { echo "http://localhost:${NOVNC_PORT:-6080}/vnc.html?autoconnect=1&resize=remote"; }

running() { [ -n "$(docker compose ps --status running -q vivado 2>/dev/null)" ]; }

vivado_installed() {
    local d=${XILINX_DIR:-./xilinx} v=${VIVADO_VERSION:-2026.1}
    [ -f "$d/$v/Vivado/settings64.sh" ] || [ -f "$d/Vivado/$v/settings64.sh" ]
}

has_license() { ls "${LICENSE_DIR:-./license}"/*.lic >/dev/null 2>&1; }

# 0 = a license file names CONTAINER_MAC as its host ID
license_matches_mac() {
    local id
    id=$(printf '%s' "${CONTAINER_MAC:-}" | tr -d ':')
    [ -n "$id" ] && cat "${LICENSE_DIR:-./license}"/*.lic 2>/dev/null | grep -qi "hostid=$id"
}

port_in_use() { (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; }

# ---------------------------------------------------------------------------------------------
# Resources: what the machine has, what Docker got, and what to recommend.

gb() { awk -v b="$1" 'BEGIN { printf "%d", b / 1073741824 + 0.5 }'; }

host_ram_gb() {
    case "$PLATFORM" in
        mac-*) gb "$(sysctl -n hw.memsize)" ;;
        wsl)   powershell.exe -NoProfile -Command \
                   '[math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory/1GB)' 2>/dev/null \
                   | tr -dc '0-9' ;;
        *)     awk '/^MemTotal/ { printf "%d", $2 / 1048576 + 0.5 }' /proc/meminfo ;;
    esac
}

host_cpus() {
    case "$PLATFORM" in
        mac-*) sysctl -n hw.ncpu ;;
        wsl)   cmd.exe /c 'echo %NUMBER_OF_PROCESSORS%' 2>/dev/null | tr -dc '0-9' ;;
        *)     nproc ;;
    esac
}

# Where to change Docker's CPU/memory/swap on this machine
how_to_resize() {
    case "$PLATFORM-$(docker_flavor)" in
        mac-*-orbstack)
            more "OrbStack > Settings > System: raise the memory and CPU limits." ;;
        mac-arm-colima)
            more "colima stop && colima start --vm-type vz --vz-rosetta --cpu ${1:-8} --memory ${2:-16}" ;;
        mac-intel-colima)
            more "colima stop && colima start --cpu ${1:-8} --memory ${2:-16}" ;;
        mac-*)
            more "Docker Desktop > Settings (gear icon) > Resources > Advanced:" \
                 "CPU limit, Memory limit, Swap. Then 'Apply & restart'." ;;
        wsl-*)
            more "Windows: edit C:\\Users\\<you>\\.wslconfig (create it if missing):" \
                 "  [wsl2]" "  memory=${2:-16}GB" "  processors=${1:-8}" "  swap=8GB" \
                 "Then in PowerShell: wsl --shutdown   and restart Docker Desktop." ;;
        *-desktop)
            more "Docker Desktop > Settings > Resources > Advanced: CPU, Memory, Swap. Then 'Apply & restart'." ;;
        *)
            more "Docker Engine uses the whole machine: close other programs or add swap" \
                 "(e.g. a swap file: https://help.ubuntu.com/community/SwapFaq)." ;;
    esac
}

# Full report. Arg 1 = "quick" skips the checks that need a container run.
# Returns 1 only for real blockers (e.g. QEMU instead of Rosetta).
resource_report() {
    local fail=0 host_mem host_cpu dmem dcpu swap rec_mem free need cpuinfo
    host_mem=$(host_ram_gb); host_cpu=$(host_cpus)
    dmem=$(gb "$(docker info --format '{{.MemTotal}}' 2>/dev/null || echo 0)")
    dcpu=$(docker info --format '{{.NCPU}}' 2>/dev/null || echo 0)
    [ -n "$host_mem" ] && [ "$host_mem" -gt 0 ] 2>/dev/null || host_mem=$dmem
    [ -n "$host_cpu" ] && [ "$host_cpu" -gt 0 ] 2>/dev/null || host_cpu=$dcpu

    # Recommended memory for Docker: 16 GB, but leave the host enough to live
    if   [ "$host_mem" -ge 24 ]; then rec_mem=16
    elif [ "$host_mem" -ge 16 ]; then rec_mem=$((host_mem - 6))
    elif [ "$host_mem" -ge 12 ]; then rec_mem=8
    else rec_mem=$((host_mem - 4)); fi

    # --- x86_64 emulation
    if [ "${1:-}" != quick ]; then
        cpuinfo=$(docker run --rm --platform linux/amd64 ubuntu:22.04 \
                  sh -c 'uname -m; grep -m1 "model name" /proc/cpuinfo; grep SwapTotal /proc/meminfo' 2>/dev/null)
        case "$PLATFORM:$cpuinfo" in
            *:) bad "Could not run an x86_64 (linux/amd64) container."; fail=1 ;;
            mac-arm:*VirtualApple*) ok "x86_64 emulation: Rosetta" ;;
            mac-arm:*QEMU*|mac-arm:*qemu*)
                bad "Docker emulates x86_64 with QEMU; Vivado crashes under QEMU. Turn on Rosetta:"
                more "Docker Desktop > Settings > General > 'Use Rosetta for x86_64/amd64 emulation" \
                     "on Apple Silicon' > Apply & restart. (Colima: start with --vm-type vz --vz-rosetta)"
                fail=1 ;;
            mac-arm:*) tip "x86_64 emulation: can't tell if it's Rosetta ($(echo "$cpuinfo" | sed -n 2p | cut -d: -f2)). If Vivado crashes, enable Rosetta." ;;
            linux-arm:*) bad "ARM Linux can only emulate x86_64 with QEMU: very slow, Vivado may crash. Not supported." ;;
            *) ok "x86_64: native" ;;
        esac
        swap=$(echo "$cpuinfo" | awk '/SwapTotal/ { printf "%d", $2 / 1048576 + 0.5 }')
    fi

    # --- memory
    local resize=0 xdir=${XILINX_DIR:-./xilinx}
    if [ "$dmem" -lt 8 ] && [ "$host_mem" -lt 12 ]; then
        bad "Docker has ${dmem} GB of memory; your computer has ${host_mem} GB. Vivado wants ~8 GB inside Docker,"
        more "so this is tight: give Docker what you can spare (leave ~4 GB for your OS) and close other apps."
        more "Small designs may still work."
        resize=1
    elif [ "$dmem" -lt 8 ]; then
        bad "Docker has ${dmem} GB of memory; Vivado needs at least 8 GB. Set it to ${rec_mem} GB (your computer has ${host_mem} GB)."
        resize=1
    elif [ "$dmem" -lt $((rec_mem - 1)) ]; then
        tip "Docker has ${dmem} GB of memory. ${rec_mem} GB is better for bigger designs (your computer has ${host_mem} GB)."
        resize=1
    else
        ok "Docker memory: ${dmem} GB (computer: ${host_mem} GB)"
    fi
    [ -z "${CONTAINER_MEMORY:-}" ] || more "Container limit from .env: CONTAINER_MEMORY=${CONTAINER_MEMORY}"

    # --- CPUs
    if [ "$dcpu" -lt 4 ] && [ "$host_cpu" -gt "$dcpu" ]; then
        bad "Docker has ${dcpu} CPU cores; give it more (your computer has ${host_cpu})."
        resize=1
    elif [ "$dcpu" -lt "$host_cpu" ]; then
        tip "Docker has ${dcpu} of your ${host_cpu} CPU cores; giving it all makes Vivado faster."
        resize=1
    else
        ok "Docker CPU cores: ${dcpu}"
    fi
    [ -z "${CONTAINER_CPUS:-}" ] || more "Container limit from .env: CONTAINER_CPUS=${CONTAINER_CPUS}"

    # --- swap
    if [ -n "${swap:-}" ]; then
        if [ "$swap" -lt 4 ]; then
            tip "Docker has ${swap} GB of swap; 4 GB or more avoids crashes when memory runs out."
            resize=1
        else
            ok "Docker swap: ${swap} GB"
        fi
    fi

    if [ "$resize" = 1 ]; then
        printf "  ${C_Y}[HOW ]${C_0} To change Docker's memory/CPUs/swap on this computer:\n"
        how_to_resize "$host_cpu" "$rec_mem"
    fi

    # --- disk (Vivado lives in XILINX_DIR on the host, not in Docker's disk)
    mkdir -p "$xdir" 2>/dev/null
    free=$(df -Pk "$xdir" 2>/dev/null | awk 'NR == 2 { printf "%d", $4 / 1048576 }')
    if vivado_installed; then need=10; else need=100; fi
    if [ -z "$free" ]; then :
    elif [ "$free" -lt "$need" ]; then
        if vivado_installed; then bad "Only ${free} GB free on the disk with ${xdir}."
        else bad "Only ${free} GB free where Vivado will be installed (${xdir}); it needs ~65 GB (plan 100 GB)."
             more "Free up space, or set XILINX_DIR in .env to a folder on a bigger disk."; fi
    else
        ok "Free disk at ${xdir}: ${free} GB"
    fi
    return $fail
}

# ---------------------------------------------------------------------------------------------
# The `vivado` command: a symlink in ~/.local/bin to this repo's ./vivado, so
# `vivado start|stop|shell|doctor|install` works from any folder and in any shell.

CMD_LINK="$HOME/.local/bin/vivado"

command_installed() { [ -L "$CMD_LINK" ] && [ "$(readlink "$CMD_LINK")" = "$(pwd)/vivado" ]; }

# Returns 0 if the command is installed (now or already), 1 if it was skipped.
install_command() {
    local bindir other rc line
    bindir=$(dirname "$CMD_LINK")
    if command_installed; then
        ok "The 'vivado' command is installed ($CMD_LINK)"
        return 0
    fi
    if [ -e "$CMD_LINK" ] || [ -L "$CMD_LINK" ]; then
        warn "$CMD_LINK already exists and is not from this repo; leaving it alone."
        more "Remove it yourself and run ./install.sh --command if you want to replace it."
        return 1
    fi
    other=$(command -v vivado 2>/dev/null || true)
    if [ -n "$other" ]; then
        warn "Another 'vivado' is already on your PATH ($other); not adding this one."
        more "Use ./start.sh, ./stop.sh, ... or make your own alias to $(pwd)/vivado."
        return 1
    fi
    mkdir -p "$bindir" && ln -s "$(pwd)/vivado" "$CMD_LINK" || { warn "Could not create $CMD_LINK"; return 1; }
    ok "Installed the 'vivado' command: $CMD_LINK -> $(pwd)/vivado"

    # Make sure ~/.local/bin is on PATH for the user's login shell
    case ":$PATH:" in *":$bindir:"*) return 0 ;; esac
    line='export PATH="$HOME/.local/bin:$PATH"  # added by vivado-docker'
    case "$(basename "${SHELL:-}")" in
        fish)
            rc="$HOME/.config/fish/conf.d/vivado-docker.fish"
            mkdir -p "$(dirname "$rc")"
            echo 'fish_add_path -g $HOME/.local/bin  # added by vivado-docker' > "$rc" ;;
        zsh)
            rc="$HOME/.zshrc"
            grep -qs 'added by vivado-docker' "$rc" || echo "$line" >> "$rc" ;;
        bash)
            rc="$HOME/.bashrc"
            [ "$(uname -s)" = Darwin ] && rc="$HOME/.bash_profile"
            grep -qs 'added by vivado-docker' "$rc" || echo "$line" >> "$rc" ;;
        *)
            tip "Add $bindir to your PATH to use the 'vivado' command."
            return 0 ;;
    esac
    more "Added $bindir to your PATH in $rc. Open a new terminal to use 'vivado'."
}
