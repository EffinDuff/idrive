FROM ubuntu:22.04

# Prevent interactive prompts during package install
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=America/New_York

# Install dependencies
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    perl \
    screen \
    cron \
    net-tools \
    iproute2 \
    nano \
    vim \
    tzdata \
    ca-certificates \
    expect \
    python3 \
    && rm -rf /var/lib/apt/lists/*

# Download and install latest iDrive for Linux (auto-accept license)
RUN wget -q https://www.idrivedownloads.com/downloads/linux/download-for-linux/linux-bin/idriveforlinux.bin -O /tmp/idriveforlinux.bin \
    && chmod +x /tmp/idriveforlinux.bin \
    && printf 'a\ny\n' | /tmp/idriveforlinux.bin --install \
    && rm /tmp/idriveforlinux.bin

# Set working directory
WORKDIR /opt/IDriveForLinux/bin

# Declare persistent volume for config/settings
#VOLUME /opt/IDriveForLinux/idriveIt

#attempting to use without entrypoint script

# Copy entrypoint script
#COPY entrypoint.sh /entrypoint.sh
#RUN chmod +x /entrypoint.sh

#ENTRYPOINT ["/entrypoint.sh"]
