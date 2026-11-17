# IDrive for Linux in a container, built for Unraid.
# Rebuilding the image always pulls the newest IDrive package (the download URL is "latest").
ARG UBUNTU_VERSION=26.04
FROM ubuntu:${UBUNTU_VERSION}

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=America/New_York \
    IDRIVE_HOME=/opt/IDriveForLinux

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl wget perl python3 expect \
        procps tini tzdata cron screen \
        net-tools iproute2 nano vim-tiny less \
    && rm -rf /var/lib/apt/lists/*

# Install the current IDrive for Linux package (auto-accepts the license prompts).
# A pristine copy of idriveIt is kept so an empty appdata volume can be seeded.
# BUILD_DATE busts the layer cache so scheduled CI builds always re-download.
ARG BUILD_DATE=unset
RUN echo "build ${BUILD_DATE}" \
    && wget -q https://www.idrivedownloads.com/downloads/linux/download-for-linux/linux-bin/idriveforlinux.bin -O /tmp/idriveforlinux.bin \
    && chmod +x /tmp/idriveforlinux.bin \
    && printf 'a\ny\n' | /tmp/idriveforlinux.bin --install \
    && rm -f /tmp/idriveforlinux.bin \
    && test -x ${IDRIVE_HOME}/bin/idrive \
    && cp -a ${IDRIVE_HOME}/idriveIt /opt/idriveIt.defaults

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR ${IDRIVE_HOME}/bin

# Everything IDrive needs to remember lives here — map it to appdata in Unraid.
VOLUME ["/opt/IDriveForLinux/idriveIt"]

HEALTHCHECK --interval=5m --timeout=10s --start-period=2m \
    CMD pgrep -f 'idrivecron --cron' >/dev/null || [ ! -d /opt/IDriveForLinux/idriveIt/user_profile ]

ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
