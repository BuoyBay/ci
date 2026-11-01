# syntax=docker/dockerfile:1
ARG BASE_IMAGE=debian:trixie-slim@sha256:f6b08b09a05725f9431502d3b5714f5c4576e82c1a84fa1debe0c24a7e0c3ec4
FROM --platform=$BUILDPLATFORM ${BASE_IMAGE} AS verify
ARG SHA256
COPY payload /sdk/payload
COPY manifest.json /sdk/release.json
RUN test "${#SHA256}" = 64 \
    && printf '%s  %s\n' "$SHA256" /sdk/payload | sha256sum --check --strict -

FROM scratch
ARG RELEASE
ARG ASSET
ARG SHA256
ARG SDK_OS
ARG SDK_ARCH
LABEL org.opencontainers.image.title="Buoy SDK artifact carrier" \
      org.opencontainers.image.version="$RELEASE" \
      org.opencontainers.image.source="https://github.com/stretched-out-software/buoy-releases" \
      io.buoy.profile="sdk-artifact" \
      io.buoy.asset="$ASSET" \
      io.buoy.asset.sha256="$SHA256" \
      io.buoy.sdk.os="$SDK_OS" \
      io.buoy.sdk.arch="$SDK_ARCH" \
      io.buoy.runnable-compiler="false"
COPY --from=verify /sdk/ /sdk/
# This transports a checksum-verified upstream installer/archive. It is not a
# Linux compiler, VM, macOS container, or Windows container; it has no command.
