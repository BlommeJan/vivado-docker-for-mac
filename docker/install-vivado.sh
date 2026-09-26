#!/bin/bash
# Batch-mode Vivado install into /tools/Xilinx (= XILINX_DIR on the host). Called by ./install.sh.
#   install-vivado.sh status   exit 0 if VIVADO_VERSION is installed
#   install-vivado.sh config   (re)generate /opt/installer/install_config.txt
#   install-vivado.sh install  AMD login + download/install (generates the config if missing)
set -euo pipefail

VERSION="${VIVADO_VERSION:?}"
DEVICES="${VIVADO_DEVICES:?}"
INSTALLER_DIR=/opt/installer
CONFIG="$INSTALLER_DIR/install_config.txt"
EXTRACT_DIR=/tools/Xilinx/.installer

say() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }
confirm() { local a; read -r -p "$1 [y/N] " a; [[ "$a" =~ ^[Yy]$ ]]; }

installed() {
    [ -f "/tools/Xilinx/$VERSION/Vivado/settings64.sh" ] || [ -f "/tools/Xilinx/Vivado/$VERSION/settings64.sh" ]
}

find_bin() {
    shopt -s nullglob
    local bins=("$INSTALLER_DIR"/*"$VERSION"*Lin64.bin)
    [ ${#bins[@]} -ge 1 ] || die "No Linux installer for $VERSION in the installer folder (expected *${VERSION}*Lin64.bin)."
    [ ${#bins[@]} -eq 1 ] || die "Several installers for $VERSION found; keep only one: ${bins[*]##*/}"
    echo "${bins[0]}"
}

extract() {
    local bin; bin=$(find_bin)
    if [ -x "$EXTRACT_DIR/xsetup" ] && [ "$(cat "$EXTRACT_DIR/.source" 2>/dev/null)" = "${bin##*/}" ]; then
        return
    fi
    say "Extracting ${bin##*/}"
    rm -rf "$EXTRACT_DIR"
    sh "$bin" --target "$EXTRACT_DIR" --noexec
    echo "${bin##*/}" > "$EXTRACT_DIR/.source"
}

# Keep only the device families in VIVADO_DEVICES and drop Vitis add-ons.
trim_modules() {
    awk -v devices="$DEVICES" '
    BEGIN {
        n = split(tolower(devices), want, ",")
        for (i = 1; i <= n; i++) { gsub(/^ +| +$/, "", want[i]); hit[i] = 0 }
    }
    /^Modules=/ {
        m = split(substr($0, 9), mods, ",")
        out = ""
        for (j = 1; j <= m; j++) {
            name = mods[j]; sub(/:[01]$/, "", name); val = substr(mods[j], length(name) + 2)
            lname = tolower(name)
            if (lname ~ /artix|spartan|kintex|virtex|zynq|versal|alveo|kria|ultrascale|rfsoc/) {
                val = 0
                for (i = 1; i <= n; i++) if (index(lname, want[i])) { val = 1; hit[i] = 1 }
            } else if (lname ~ /vitis|model composer|power design manager/) {
                val = 0
            }
            out = out (j > 1 ? "," : "") name ":" val
        }
        print "Modules=" out
        next
    }
    /^Destination=/                  { print "Destination=/tools/Xilinx"; next }
    /^CreateProgramGroupShortcuts=/  { print "CreateProgramGroupShortcuts=0"; next }
    /^CreateDesktopShortcuts=/       { print "CreateDesktopShortcuts=0"; next }
    /^CreateFileAssociation=/        { print "CreateFileAssociation=0"; next }
    /^EnableDiskUsageOptimization=/  { print "EnableDiskUsageOptimization=1"; next }
    { print }
    END {
        for (i = 1; i <= n; i++) if (!hit[i]) { print "NOMATCH " want[i] > "/dev/stderr"; bad = 1 }
        exit bad
    }'
}

gen_config() {
    extract
    say "Generating the install config: pick the Vivado product (and edition, if asked)"
    rm -f ~/.Xilinx/install_config.txt
    "$EXTRACT_DIR/xsetup" -b ConfigGen
    local raw=~/.Xilinx/install_config.txt
    [ -f "$raw" ] || raw=$(ls -t ~/.Xilinx/*config*.txt 2>/dev/null | head -1)
    [ -f "$raw" ] || die "ConfigGen did not produce a config file."
    if ! trim_modules < "$raw" > "$CONFIG.tmp" 2> "$CONFIG.err"; then
        cat "$CONFIG.err" >&2
        echo "Available modules:" >&2
        sed -n 's/^Modules=//p' "$raw" | tr ',' '\n' | sed 's/^/    /' >&2
        rm -f "$CONFIG.tmp" "$CONFIG.err"
        die "Some VIVADO_DEVICES don't match any module (see above); fix VIVADO_DEVICES in .env."
    fi
    rm -f "$CONFIG.err"
    mv "$CONFIG.tmp" "$CONFIG"
    say "Wrote install_config.txt"
}

show_plan() {
    grep -E '^(Edition|Product|Destination)=' "$CONFIG" | sed 's/^/    /'
    echo "    Selected modules:"
    sed -n 's/^Modules=//p' "$CONFIG" | tr ',' '\n' | grep ':1$' | sed 's/:1$//; s/^/      - /'
}

case "${1:-install}" in
    status)
        installed
        ;;
    config)
        gen_config
        show_plan
        ;;
    install)
        if installed; then
            say "Vivado $VERSION is already installed in /tools/Xilinx."
            exit 0
        fi
        [ -f "$CONFIG" ] || gen_config
        extract
        say "Install plan"
        show_plan
        echo "    (edit the installer folder's install_config.txt, or delete it to regenerate)"
        confirm "Continue?" || die "Aborted; nothing installed."

        say "Log in with your AMD account (typed here only; your password is never stored)"
        until "$EXTRACT_DIR/xsetup" -b AuthTokenGen; do
            confirm "Login failed. Try again?" || die "Aborted; nothing installed."
        done

        say "Installing requires accepting the AMD EULA and the third-party EULA."
        confirm "Accept XilinxEULA and 3rdPartyEULA and start downloading/installing?" \
            || die "Aborted; nothing installed."
        "$EXTRACT_DIR/xsetup" -b Install -c "$CONFIG" -a XilinxEULA,3rdPartyEULA

        rm -f ~/.Xilinx/wi_authentication_key    # only needed for the download
        installed || die "The installer finished but no settings64.sh for $VERSION was found."
        say "Vivado $VERSION installed."
        ;;
    *)
        die "Unknown command: $1 (use status, config or install)"
        ;;
esac
