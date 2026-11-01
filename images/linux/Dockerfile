# syntax=docker/dockerfile:1
ARG BASE_IMAGE=debian:trixie-slim@sha256:f6b08b09a05725f9431502d3b5714f5c4576e82c1a84fa1debe0c24a7e0c3ec4
FROM --platform=$BUILDPLATFORM ${BASE_IMAGE} AS unpack
ARG SHA256
COPY payload /tmp/package.deb
RUN test "${#SHA256}" = 64 \
    && printf '%s  %s\n' "$SHA256" /tmp/package.deb | sha256sum --check --strict - \
    && mkdir /package \
    && dpkg-deb --extract /tmp/package.deb /package

FROM ${BASE_IMAGE} AS archive
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates zlib1g libglib2.0-0t64 shared-mime-info build-essential git pkg-config \
    && rm -rf /var/lib/apt/lists/*
COPY --from=unpack /package/ /
COPY --chmod=755 bin/buoy /usr/local/bin/buoy
COPY --chmod=755 bin/inspect-toolchain /usr/local/libexec/inspect-toolchain
COPY --chmod=755 bin/configure-compatibility /usr/local/libexec/configure-compatibility
COPY compatibility.json /usr/local/share/buoy-ci/compatibility.json
COPY manifest.json /usr/local/share/buoy-ci/release.json
ARG COMPAT_BUILD_ROOT
ARG TARGETARCH
RUN /usr/local/libexec/configure-compatibility "$COMPAT_BUILD_ROOT" "$TARGETARCH"
ARG RELEASE
ARG VERSION
ARG ASSET
ARG SHA256
LABEL org.opencontainers.image.title="Buoy compiler" \
      org.opencontainers.image.version="$RELEASE" \
      org.opencontainers.image.source="https://github.com/stretched-out-software/buoy-releases" \
      io.buoy.profile="linux-compiler" \
      io.buoy.asset="$ASSET" \
      io.buoy.asset.sha256="$SHA256"
RUN test -x /usr/bin/buoy \
    && if [ -f /usr/local/share/buoy-ci/auto-startup-object ]; then \
         printf 'linux-sdk-auto-crt\n' > /usr/local/share/buoy-ci/link-mode; \
       else printf 'linux-sdk-overrides\n' > /usr/local/share/buoy-ci/link-mode; fi
LABEL io.buoy.verification="not-verified"
ENV LANG=C.UTF-8
WORKDIR /workspace
# No entrypoint: suitable for Actions containers and ordinary shell commands.
CMD ["buoy", "--version"]

FROM archive AS verified
ARG VERSION
RUN /usr/local/libexec/inspect-toolchain "$VERSION"
LABEL io.buoy.verification="native-compile-and-run-passed"
