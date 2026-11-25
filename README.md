# mobile-build-images

[![Build Images](https://github.com/specsnl/mobile-build-images/actions/workflows/main.yml/badge.svg)](https://github.com/specsnl/mobile-build-images/actions/workflows/main.yml)

Docker images for building JavaScript and mobile (Capacitor, React Native/Expo) projects: Node.js with pnpm, and an
Android build image. Nothing but Docker has to be installed on the host.

## Pulling the images

```
docker pull ghcr.io/specsnl/mobile-build-images/node:latest
docker pull ghcr.io/specsnl/mobile-build-images/android:latest
```

The image name scheme: `ghcr.io/specsnl/mobile-build-images/{TARGET}:{VERSION}`

- **{TARGET}**: `node` or `android`
- **{VERSION}**: `latest`, a release tag (i.e. `1.0.0`), `main` or `pr-<number>`

Pin a release tag in projects; the changes per release are in the [changelog](CHANGELOG.md).

## The images

Both images are built from the targets of the one [`Dockerfile`](Dockerfile).

- **node** (`linux/amd64`, `linux/arm64`)
    - Node.js 26 (active LTS) with npm.
    - pnpm, installed with npm: Node.js 25+ no longer ships corepack. A project that pins another pnpm version in the
      `packageManager` field of its `package.json` gets that version, as pnpm switches to it itself.
    - git, curl and unzip.
- **android** (`linux/amd64` only), built on `node`
    - JDK 21 (Eclipse Temurin), in `JAVA_HOME=/opt/java/openjdk`.
    - The Android SDK in `ANDROID_HOME=/opt/android-sdk`: the command-line tools (`sdkmanager`), platform-tools,
      platform 36 and build-tools 36.0.0 and 35.0.0. 35.0.0 is the default of the Android Gradle plugin 8.13 that
      Capacitor 8 uses. The SDK licenses are accepted at build time.
    - Gradle is not installed: projects run the Gradle wrapper (`./gradlew`), with `GRADLE_USER_HOME=/cache/gradle`.

The SDK is writable for the user, so the Android Gradle plugin can install what a project needs on top of it (another
build-tools version, an NDK). Those packages are gone with the container though, so they're downloaded again on every
run: build a derived image with `sdkmanager --install '<package>'` for packages you need regularly.

### The android image is amd64-only

Google ships the native Android build-tools (`aapt2`, `zipalign`, ...), platform-tools, the NDK and the `sdkmanager` of
the command-line tools 23 only for Linux x86_64. The Android Gradle plugin downloads its own `aapt2` from Google's Maven
repository, but that one has a Linux arm64 build only from plugin version 9.5 on, and Capacitor 8 uses 8.13. So the
`android` image is only published for `linux/amd64`.

On Apple Silicon it runs under emulation: pass `--platform linux/amd64` (Compose: `platform: linux/amd64`), and turn
on "Use Rosetta for x86_64/amd64 emulation on Apple Silicon" in Docker Desktop, which is much faster than QEMU. Builds
are still slower than native ones.

### Files are owned by the host user

The images run as the user `code` (UID/GID 1000) and use [fixuid](https://github.com/boxboat/fixuid) as their
entrypoint. Run them with `--user "$(id -u):$(id -g)"` (Compose: `user: "${UID}:${GID}"`) and fixuid changes the UID
and GID of `code` to yours at startup, so everything written to a mounted project is owned by you on the host.

The project goes in `/app`, the working directory.

### Caches in /cache

`/cache` is a volume holding the caches, so mount a named volume there to keep them between runs:

| Cache         | Location                        |
|---------------|---------------------------------|
| npm           | `/cache/npm`                    |
| pnpm store    | `/cache/pnpm/store`             |
| pnpm metadata | `/cache/pnpm`                   |
| Gradle        | `/cache/gradle` (android only)  |
| Android user  | `/cache/android` (android only) |

`/cache/android` is `ANDROID_USER_HOME`: it holds the debug keystore, and the Android CLI that `sdkmanager` downloads on
first use.

fixuid makes the image's own files in `/cache` yours, but not files that another UID wrote to the volume earlier: use
a cache volume for one host user.

The pnpm store and the project are on different filesystems, so pnpm copies packages into `node_modules` instead of
hard-linking them. That's slower than linking, but still saves the downloads.

## Usage

### docker run

Install the dependencies and build the web app in the `node` image:

```
docker run --rm --interactive --tty \
    --user "$(id -u):$(id -g)" \
    --volume "$PWD:/app" \
    --volume mobile-build-cache:/cache \
    ghcr.io/specsnl/mobile-build-images/node:latest \
    bash -c 'pnpm install --frozen-lockfile && pnpm run build'
```

Build a release bundle of a Capacitor project in the `android` image:

```
docker run --rm --interactive --tty \
    --platform linux/amd64 \
    --user "$(id -u):$(id -g)" \
    --volume "$PWD:/app" \
    --volume mobile-build-cache:/cache \
    ghcr.io/specsnl/mobile-build-images/android:latest \
    bash -c 'pnpm install --frozen-lockfile && pnpm run build && npx cap sync android && cd android && ./gradlew bundleRelease'
```

The bundle ends up in `android/app/build/outputs/bundle/release/`. Signing it is up to the project's Gradle
configuration.

### Docker Compose

```yaml
services:
  node:
    image: ghcr.io/specsnl/mobile-build-images/node:latest
    user: "${UID:-1000}:${GID:-1000}"
    volumes:
      - .:/app
      - cache:/cache

  android:
    image: ghcr.io/specsnl/mobile-build-images/android:latest
    platform: linux/amd64
    user: "${UID:-1000}:${GID:-1000}"
    volumes:
      - .:/app
      - cache:/cache

volumes:
  cache:
```

Compose reads `UID` and `GID` from the environment or the project's `.env`. Shells don't export them, so add them to
`.env` once (`printf 'UID=%s\nGID=%s\n' "$(id -u)" "$(id -g)" >> .env`). Then run, for example:

```
docker compose run --rm node pnpm install
docker compose run --rm android bash -c 'cd android && ./gradlew bundleRelease'
```

### iOS

Compiling and archiving iOS apps is out of scope: they need macOS and Xcode. The web build and `npx cap sync ios` run
in the `node` image (with `@capacitor/cli` as a project dependency): Capacitor 8 uses Swift Package Manager by
default, so there's no CocoaPods install step.

```
docker compose run --rm node bash -c 'pnpm run build && npx cap sync ios'
```

Signing and uploads to Google Play and TestFlight are not part of these images: they're tracked in
[#2](https://github.com/specsnl/mobile-build-images/issues/2).

## Building the images

```
docker build --target node --tag ghcr.io/specsnl/mobile-build-images/node:latest .
docker build --platform linux/amd64 --target android --tag ghcr.io/specsnl/mobile-build-images/android:latest .
```

## Releasing

Add the changes under a new version heading in the [changelog](CHANGELOG.md), merge it and push a tag with the same
version (i.e. `1.0.0`). The tag workflow publishes the images under that tag.

## Task commands

Available [Task](https://taskfile.dev/#/) commands:

```
* build:               Build the node and android images
* lint:                Apply a Dockerfile linter (https://github.com/hadolint/hadolint)
* build:android:       Build the android image (linux/amd64 only)
* build:node:          Build the node image
* shell:android:       Interactive shell in the android image, with the current directory mounted
* shell:node:          Interactive shell in the node image, with the current directory mounted
```
