# Vivado runtime + XFCE desktop served over noVNC.
# Vivado itself is NOT in this image; it is installed at runtime into XILINX_DIR (mounted at /tools/Xilinx).
#
# Ubuntu 22.04: officially supported by Vivado 2026.1 (UG973) and still ships libtinfo5,
# which Vivado needs on Ubuntu (AR# 76616). 24.04 dropped libtinfo5 from its archive.
FROM --platform=linux/amd64 ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive
ARG NOVNC_VERSION=1.6.0
# Match the host user on Linux so bind-mounted files get the right owner (install.sh sets these)
ARG USER_UID=1000
ARG USER_GID=1000

# Vivado runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl wget sudo locales tzdata procps file less nano unzip xz-utils \
        libtinfo5 libncurses5 libncursesw5 \
        libx11-6 libxext6 libxrender1 libxtst6 libxi6 libxrandr2 libxft2 libxss1 libxcursor1 \
        libfreetype6 fontconfig fonts-dejavu-core \
        libgtk2.0-0 libgtk-3-0 libglib2.0-0 libnss3 libasound2 libsm6 libice6 libgbm1 \
        libudev1 libselinux1 zlib1g \
        build-essential gcc-multilib g++ make python3 git net-tools \
    && rm -rf /var/lib/apt/lists/*

# Desktop: XFCE + TigerVNC + websockify (noVNC comes from its upstream release, apt's is from 2018)
RUN apt-get update && apt-get install -y --no-install-recommends \
        xfce4 xfce4-terminal xfce4-taskmanager dbus-x11 x11-xserver-utils x11-utils xdg-utils \
        mousepad ristretto thunar adwaita-icon-theme elementary-xfce-icon-theme \
        tigervnc-standalone-server tigervnc-tools python3-websockify \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL "https://github.com/novnc/noVNC/archive/refs/tags/v${NOVNC_VERSION}.tar.gz" \
        | tar -xz -C /opt \
    && mv "/opt/noVNC-${NOVNC_VERSION}" /opt/novnc \
    && ln -s vnc.html /opt/novnc/index.html

# Vivado crashes without a UTF-8 locale
RUN sed -i '/en_US.UTF-8/s/^# //' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8 NO_AT_BRIDGE=1

# Unprivileged desktop user (passwordless sudo; the container is only reachable from this machine)
RUN (getent group "$USER_GID" >/dev/null || groupadd --gid "$USER_GID" user) \
    && useradd --create-home --shell /bin/bash --uid "$USER_UID" --gid "$USER_GID" user \
    && echo 'user ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/user \
    && mkdir -p /tools/Xilinx && chown "$USER_UID:$USER_GID" /tools/Xilinx \
    && mkdir -p -m 1777 /tmp/.X11-unix /tmp/.ICE-unix

COPY docker/vivado-env.sh /etc/profile.d/vivado-env.sh
COPY docker/entrypoint.sh docker/install-vivado.sh docker/start-vivado /usr/local/bin/
RUN chmod 755 /usr/local/bin/entrypoint.sh /usr/local/bin/install-vivado.sh /usr/local/bin/start-vivado \
    && echo '. /etc/profile.d/vivado-env.sh' >> /etc/bash.bashrc

USER user
WORKDIR /home/user
EXPOSE 6080
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
