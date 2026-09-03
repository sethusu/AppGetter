# Cloud Agent base image for the AppGetter PowerShell tool.
# AppGetter is a PowerShell (pwsh) CLI/GUI tool, so the base image must provide
# PowerShell Core plus the modules used for linting (PSScriptAnalyzer) and the
# test suite (Pester 5+). Cursor's default image provides none of these, so we
# install them here as stable, image-layer-baked dependencies. .cursor/install.sh
# then runs after checkout as an idempotent safety net.
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

# Install the PowerShell modules AppGetter needs for lint and tests into the
# system-wide (AllUsers) module path so they are baked into the image layer.
# ErrorActionPreference=Stop makes a gallery/install failure abort the build.
RUN pwsh -NoProfile -Command "\$ErrorActionPreference='Stop'; Set-PSRepository -Name PSGallery -InstallationPolicy Trusted; Install-Module -Name PSScriptAnalyzer -MinimumVersion 1.21.0 -Scope AllUsers -Force; Install-Module -Name Pester -MinimumVersion 5.0.0 -Scope AllUsers -Force -SkipPublisherCheck; Get-Module -ListAvailable -Name PSScriptAnalyzer,Pester | Format-Table Name,Version"

# The ubuntu:24.04 image ships a non-root 'ubuntu' user (uid 1000); run as it.
USER ubuntu
