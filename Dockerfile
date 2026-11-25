# syntax=docker/dockerfile:1
# check=error=true

# Latest version of node: https://hub.docker.com/_/node/tags
FROM node:26.13.1-trixie-slim AS node

ARG TARGETARCH
ARG DEBIAN_FRONTEND=noninteractive

ENV LANG=C.UTF-8

ARG XDG_CACHE_HOME=/cache
ENV XDG_CACHE_HOME="$XDG_CACHE_HOME"

# Latest version of pnpm: https://www.npmjs.com/package/pnpm
ARG PNPM_VERSION=12.23.0

# Latest version of fixuid: https://github.com/boxboat/fixuid/releases/latest
ARG FIXUID_VERSION=0.6.0

ARG USER=code
ARG GROUP=code
ARG USER_UID=1000
ARG USER_GID=1000

ENV npm_config_cache="$XDG_CACHE_HOME/npm"
ENV npm_config_update_notifier=false
ENV PNPM_CONFIG_STORE_DIR="$XDG_CACHE_HOME/pnpm/store"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

WORKDIR /app

RUN apt-get update \
    && apt-get install --assume-yes --no-install-recommends \
        ca-certificates \
        curl \
        git \
        openssh-client \
        unzip \
    # Node.js 25+ no longer bundles corepack, so pnpm is installed with npm. Its cache goes to /tmp so no root-owned
    # files end up in npm_config_cache.
    && npm install --global --cache /tmp/npm-cache --no-audit --no-fund "pnpm@$PNPM_VERSION" \
    # Install fixuid
    && curl -fsSLo /tmp/fixuid.tar.gz "https://github.com/boxboat/fixuid/releases/download/v$FIXUID_VERSION/fixuid-${FIXUID_VERSION}-linux-${TARGETARCH}.tar.gz" \
    && tar -xf /tmp/fixuid.tar.gz -C /usr/local/bin fixuid \
    && chown root:root /usr/local/bin/fixuid \
    && chmod 4755 /usr/local/bin/fixuid \
    # The node image ships a "node" user with UID 1000, replace it with our own user
    && userdel --remove node \
    && groupadd --gid "$USER_GID" "$GROUP" \
    && useradd --uid "$USER_UID" --gid "$USER_GID" --create-home "$USER" --shell /bin/bash \
    && mkdir -p \
        /etc/fixuid \
        "$npm_config_cache" \
        "$PNPM_CONFIG_STORE_DIR" \
    && chown -R "$USER_UID":"$USER_GID" \
        /app \
        "$XDG_CACHE_HOME" \
    # Cleanup
    && apt-get autoremove --assume-yes \
    && apt-get clean --assume-yes \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /tmp/* \
    && cat <<EOF > /etc/fixuid/config.yml
user: $USER
group: $GROUP
paths:
  - /app
  - "/home/$USER"
  - "$XDG_CACHE_HOME"
EOF

VOLUME ["/cache"]

USER $USER:$GROUP

ENTRYPOINT ["fixuid", "-q"]
CMD ["bash"]
