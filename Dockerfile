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

# Latest version of eclipse-temurin: https://hub.docker.com/_/eclipse-temurin/tags
FROM eclipse-temurin:21.0.13_9-jdk-noble AS jdk

FROM node AS android

ARG USER=code
ARG GROUP=code

# Latest version of the command-line tools: https://developer.android.com/studio#command-line-tools-only
ARG ANDROID_CMDLINE_TOOLS_VERSION=16111833
ARG ANDROID_PLATFORM_VERSION=36
# The build-tools of the platform: https://developer.android.com/tools/releases/build-tools
ARG ANDROID_BUILD_TOOLS_VERSION=36.0.0
# The default build-tools of the Android Gradle plugin 8.13, used by Capacitor 8. The plugin installs a missing default
# at build time, which would be lost with the container.
ARG ANDROID_AGP_BUILD_TOOLS_VERSION=35.0.0

ENV JAVA_HOME=/opt/java/openjdk
ENV ANDROID_HOME=/opt/android-sdk
ENV PATH="$JAVA_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"
ENV ANDROID_USER_HOME="$XDG_CACHE_HOME/android"
ENV GRADLE_USER_HOME="$XDG_CACHE_HOME/gradle"

COPY --from=jdk /opt/java/openjdk /opt/java/openjdk

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

USER 0:0

RUN curl -fsSLo /tmp/cmdline-tools.zip "https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_CMDLINE_TOOLS_VERSION}_latest.zip" \
    && mkdir -p "$ANDROID_HOME/cmdline-tools" \
    && unzip -q /tmp/cmdline-tools.zip -d /tmp \
    && mv /tmp/cmdline-tools "$ANDROID_HOME/cmdline-tools/latest" \
    # sdkmanager accepts the licenses of the packages it installs. It downloads the Android CLI it wraps into
    # ANDROID_USER_HOME, which is removed again to keep it out of the image.
    && ANDROID_USER_HOME=/tmp/android sdkmanager --install \
        "platform-tools" \
        "platforms;android-$ANDROID_PLATFORM_VERSION" \
        "build-tools;$ANDROID_BUILD_TOOLS_VERSION" \
        "build-tools;$ANDROID_AGP_BUILD_TOOLS_VERSION" \
        > /dev/null \
    && test -f "$ANDROID_HOME/licenses/android-sdk-license" \
    # The SDK is writable for the user, so Gradle and sdkmanager can add packages
    && chown -R "$USER":"$GROUP" "$ANDROID_HOME" \
    && echo "  - $ANDROID_HOME" >> /etc/fixuid/config.yml \
    # Cleanup
    && rm -rf /tmp/*

USER $USER:$GROUP

# Latest version of debian: https://hub.docker.com/_/debian/tags
FROM debian:trixie-20261123-slim AS zsign

ARG DEBIAN_FRONTEND=noninteractive

# Latest version of zsign: https://github.com/zhlynn/zsign/releases/latest
ARG ZSIGN_VERSION=1.1.3

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update \
    && apt-get install --assume-yes --no-install-recommends \
        ca-certificates \
        git \
        g++ \
        make \
        pkg-config \
        libssl-dev \
    && git clone --quiet --depth 1 --branch "v$ZSIGN_VERSION" https://github.com/zhlynn/zsign.git /tmp/zsign \
    && make --directory /tmp/zsign/build/linux VERSION="$ZSIGN_VERSION" \
    && install -m 755 /tmp/zsign/bin/zsign /usr/local/bin/zsign

FROM node AS fastlane

ARG USER=code
ARG GROUP=code
ARG DEBIAN_FRONTEND=noninteractive

# Latest version of fastlane: https://rubygems.org/gems/fastlane
ARG FASTLANE_VERSION=2.242.0

ENV BUNDLE_PATH="$XDG_CACHE_HOME/bundle"
ENV GEM_SPEC_CACHE="$XDG_CACHE_HOME/gem/specs"
ENV FASTLANE_ITUNES_TRANSPORTER_PATH="$XDG_CACHE_HOME/itms"
ENV FASTLANE_SKIP_UPDATE_CHECK=1
ENV FASTLANE_HIDE_CHANGELOG=1
ENV FASTLANE_OPT_OUT_USAGE=1

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

USER 0:0

RUN apt-get update \
    # The compiler and headers stay, so projects with a Gemfile can bundle gems with native extensions
    && apt-get install --assume-yes --no-install-recommends \
        ruby \
        ruby-dev \
        ruby-bundler \
        build-essential \
    && gem install --no-document "fastlane:$FASTLANE_VERSION" \
    # Transporter keeps its state in ~/.itmstransporter, which install-transporter puts in /cache next to Transporter
    && ln -s "$XDG_CACHE_HOME/itmstransporter" "/home/$USER/.itmstransporter" \
    && chown --no-dereference "$USER":"$GROUP" "/home/$USER/.itmstransporter" \
    # Cleanup
    && apt-get autoremove --assume-yes \
    && apt-get clean --assume-yes \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /tmp/* "$XDG_CACHE_HOME/gem"

COPY --from=zsign /usr/local/bin/zsign /usr/local/bin/zsign
COPY files/fastlane /

USER $USER:$GROUP
