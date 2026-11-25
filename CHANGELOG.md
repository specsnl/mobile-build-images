# Changelog

All notable changes to the images are documented in this file. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the release tags follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-11-25

### Added

- `node` image: Node.js 26 (active LTS) with pnpm 12, a `fixuid` entrypoint and a `/cache` volume for the pnpm and
  npm caches. Published for `linux/amd64` and `linux/arm64`.
- `android` image: the `node` image plus JDK 21 (Eclipse Temurin), the Android SDK command-line tools, platform 36,
  build-tools 36.0.0 and 35.0.0 and platform-tools, with the SDK licenses accepted. `GRADLE_USER_HOME` is
  `/cache/gradle` and `ANDROID_USER_HOME` is `/cache/android`. Published for `linux/amd64` only.
- `fastlane` image: the `node` image plus Ruby 3.3 with Bundler, fastlane 2.242.0 and zsign 1.1.3, for app signing
  and store uploads, and `install-transporter` to install Apple's Transporter for Linux into `/cache/itms`. Published
  for `linux/amd64` and `linux/arm64`; Transporter only runs on `linux/amd64`.

[Unreleased]: https://github.com/specsnl/mobile-build-images/compare/1.0.0...HEAD
[1.0.0]: https://github.com/specsnl/mobile-build-images/releases/tag/1.0.0
