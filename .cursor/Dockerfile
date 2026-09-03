# Cloud Agent base image for the AppGetter PowerShell tool.
# AppGetter is a PowerShell (pwsh) CLI/GUI tool, so the base image must provide
# PowerShell Core. Cursor's default image does not, so we install it here (a
# stable system toolchain). Repository-tied PowerShell modules are installed by
# .cursor/install.sh after checkout.
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# git and curl are required by Cursor in fully custom images; wget/gnupg/ca-certificates
# are needed to add the Microsoft package repository.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        gnupg \
        wget \
    && rm -rf /var/lib/apt/lists/*

# Install PowerShell Core (pwsh) from the official Microsoft package repository.
RUN wget -q "https://packages.microsoft.com/config/ubuntu/24.04/packages-microsoft-prod.deb" \
        -O /tmp/packages-microsoft-prod.deb \
    && dpkg -i /tmp/packages-microsoft-prod.deb \
    && rm -f /tmp/packages-microsoft-prod.deb \
    && apt-get update \
    && apt-get install -y --no-install-recommends powershell \
    && rm -rf /var/lib/apt/lists/* \
    && pwsh --version

# The ubuntu:24.04 image ships a non-root 'ubuntu' user (uid 1000); run as it.
USER ubuntu
