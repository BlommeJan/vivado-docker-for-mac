# Sourced by every login shell and every interactive bash (see /etc/bash.bashrc).

# Rosetta workaround (github.com/ichi4096/vivado-on-silicon-mac): without these preloads Vivado
# crashes during synthesis under Rosetta. Only applied to Vivado itself (its synth/impl child
# processes inherit it): preloading GTK2's gdk globally breaks GTK3 apps like XFCE.
case "${VIVADO_ROSETTA_WORKAROUND:-auto}" in
    1) _preload=1 ;;
    0) _preload= ;;
    *) grep -q VirtualApple /proc/cpuinfo 2>/dev/null && _preload=1 || _preload= ;;
esac
if [ -n "$_preload" ]; then
    export VIVADO_LD_PRELOAD="/lib/x86_64-linux-gnu/libudev.so.1 /lib/x86_64-linux-gnu/libselinux.so.1 /lib/x86_64-linux-gnu/libz.so.1 /lib/x86_64-linux-gnu/libgdk-x11-2.0.so.0"
else
    export VIVADO_LD_PRELOAD=
fi
unset _preload
vivado() { LD_PRELOAD="$VIVADO_LD_PRELOAD" command vivado "$@"; }
export -f vivado

# From 2026.1 Vivado refuses to start without a license file, even for the free Basic tier.
export XILINXD_LICENSE_FILE="${XILINXD_LICENSE_FILE:-/opt/license}"

# Put Vivado on PATH: prefer VIVADO_VERSION, else any install found.
# (2025.1+ layout is <root>/<ver>/Vivado, older is <root>/Vivado/<ver>)
if [ -z "${VIVADO_ENV_LOADED:-}" ]; then
    for _s in "/tools/Xilinx/${VIVADO_VERSION:-none}/Vivado/settings64.sh" \
              "/tools/Xilinx/Vivado/${VIVADO_VERSION:-none}/settings64.sh" \
              /tools/Xilinx/*/Vivado/settings64.sh /tools/Xilinx/Vivado/*/settings64.sh; do
        if [ -f "$_s" ]; then
            . "$_s"
            export VIVADO_ENV_LOADED=1
            break
        fi
    done
    unset _s
fi
