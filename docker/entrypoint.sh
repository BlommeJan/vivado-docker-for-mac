#!/bin/bash
# Starts TigerVNC (container-internal only), an XFCE session, and noVNC on :6080.
set -euo pipefail

: "${VNC_PASSWORD:?VNC_PASSWORD is not set; put it in .env}"
GEOMETRY="${VNC_GEOMETRY:-1920x1080}"
export DISPLAY=:1

# VNC password (VncAuth only uses the first 8 characters)
mkdir -p ~/.vnc
printf '%s\n' "$VNC_PASSWORD" | vncpasswd -f > ~/.vnc/passwd
chmod 600 ~/.vnc/passwd

# Pre-seed XFCE: default panel (skips the first-run dialog), no compositor, no screen lock
xml=~/.config/xfce4/xfconf/xfce-perchannel-xml
mkdir -p "$xml" ~/Desktop
[ -f "$xml/xfce4-panel.xml" ] || cp /etc/xdg/xfce4/panel/default.xml "$xml/xfce4-panel.xml"
cat > "$xml/xfwm4.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="use_compositing" type="bool" value="false"/>
  </property>
</channel>
EOF
cat > "$xml/xsettings.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xsettings" version="1.0">
  <property name="Net" type="empty">
    <property name="IconThemeName" type="string" value="elementary-xfce"/>
  </property>
</channel>
EOF
cat > "$xml/xfce4-power-manager.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-power-manager" version="1.0">
  <property name="xfce4-power-manager" type="empty">
    <property name="dpms-enabled" type="bool" value="false"/>
    <property name="lock-screen-suspend-hibernate" type="bool" value="false"/>
  </property>
</channel>
EOF

# Desktop launchers
cat > ~/Desktop/vivado.desktop <<EOF
[Desktop Entry]
Type=Application
Name=Vivado ${VIVADO_VERSION:-}
Comment=AMD Vivado Design Suite
Exec=/usr/local/bin/start-vivado
Icon=applications-engineering
Terminal=false
Categories=Development;Electronics;
EOF
chmod 755 ~/Desktop/vivado.desktop
ln -sfn /home/user/lab ~/Desktop/lab
gio set ~/Desktop/vivado.desktop metadata::trusted true 2>/dev/null || true

# Vivado thread count (VIVADO_MAX_THREADS in .env), read by every Vivado start
mkdir -p ~/.Xilinx/Vivado
if [[ "${VIVADO_MAX_THREADS:-}" =~ ^[0-9]+$ ]]; then
    echo "set_param general.maxThreads $VIVADO_MAX_THREADS" > ~/.Xilinx/Vivado/Vivado_init.tcl
else
    rm -f ~/.Xilinx/Vivado/Vivado_init.tcl
fi

rm -f /tmp/.X1-lock /tmp/.X11-unix/X1

# -localhost: VNC is only reachable inside the container; the browser goes through websockify
Xtigervnc "$DISPLAY" -rfbport 5901 -localhost -geometry "$GEOMETRY" -depth 24 \
    -SecurityTypes VncAuth -PasswordFile ~/.vnc/passwd -AlwaysShared \
    -desktop "Vivado" &
vnc_pid=$!
for _ in $(seq 50); do [ -e /tmp/.X11-unix/X1 ] && break; sleep 0.2; done

# Login shell so /etc/profile.d/vivado-env.sh is sourced for everything started from the desktop
bash -lc 'dbus-launch --exit-with-session xfce4-session' > ~/.xfce-session.log 2>&1 &

websockify --web /opt/novnc 0.0.0.0:6080 localhost:5901 > ~/.websockify.log 2>&1 &
ws_pid=$!

echo "Desktop ready: http://localhost:6080/vnc.html?autoconnect=1&resize=remote"
wait -n "$vnc_pid" "$ws_pid"
echo "VNC server or websockify exited; stopping container." >&2
exit 1
