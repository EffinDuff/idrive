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
# The download is retried; installer output is printed if it fails.
# The build fails if the installed IDrive is older than MIN_IDRIVE_VERSION.
ARG IDRIVE_URL=https://www.idrivedownloads.com/downloads/linux/linux-bin/idriveforlinux.bin
ARG MIN_IDRIVE_VERSION=3.16
ARG BUILD_DATE=unset
RUN set -e; \
    echo "build ${BUILD_DATE}"; \
    wget -q --tries=5 --waitretry=15 --retry-connrefused --timeout=60 \
        "${IDRIVE_URL}" -O /tmp/idriveforlinux.bin; \
    ls -l /tmp/idriveforlinux.bin; \
    chmod +x /tmp/idriveforlinux.bin; \
    if ! printf 'a\ny\n' | /tmp/idriveforlinux.bin --install > /tmp/idrive-install.log 2>&1; then \
        echo "IDrive installer failed. Last 50 lines of its output:"; \
        tail -n 50 /tmp/idrive-install.log; \
        exit 1; \
    fi; \
    rm -f /tmp/idriveforlinux.bin /tmp/idrive-install.log; \
    test -x ${IDRIVE_HOME}/bin/idrive; \
    v=$(grep -o 'Build [0-9][0-9.]*' ${IDRIVE_HOME}/bin/readme.txt | tail -1 | cut -d' ' -f2); \
    echo "Installed IDrive ${v:-unknown} (minimum ${MIN_IDRIVE_VERSION})"; \
    if [ -z "$v" ] || [ "$(printf '%s\n%s\n' "${MIN_IDRIVE_VERSION}" "${v}" | sort -V | head -1)" != "${MIN_IDRIVE_VERSION}" ]; then \
        echo "IDrive ${v:-unknown} is older than the required ${MIN_IDRIVE_VERSION}"; \
        exit 1; \
    fi; \
    echo "${v}" > /opt/idrive-version; \
    cp -a ${IDRIVE_HOME}/idriveIt /opt/idriveIt.defaults

LABEL org.opencontainers.image.source="https://github.com/EffinDuff/idrive"

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR ${IDRIVE_HOME}/bin

# Everything IDrive needs to remember lives here — map it to appdata in Unraid.
VOLUME ["/opt/IDriveForLinux/idriveIt"]

# Healthy if the IDrive scheduler is running, or if no account has been set up yet
HEALTHCHECK --interval=5m --timeout=10s --start-period=2m \
    CMD ["bash", "-c", "pgrep -f 'idrivecron --cron' >/dev/null || ! compgen -G '/opt/IDriveForLinux/idriveIt/user_profile/*/*' >/dev/null"]

ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
