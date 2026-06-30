# ============================================================================
# BASE-1 EXPERIMENT — NOT INTENDED TO MERGE INTO `dev`.
#
# Goal: prove (or refute) that Debian 12 (bookworm) + SONAME compatibility
# symlinks can satisfy the vendor TIDAL Connect binary's link-time deps.
# Expected outcome: `ldd` resolves all SONAMEs (because the symlinks point
# to newer SO files), but the binary fails at runtime due to ABI breakage
# (OpenSSL 1.0 → 3.0 symbol renames, FFmpeg 3 → 5 API changes, FLAC 8 → 12).
#
# Findings will be recorded in docs/troubleshooting.md and merged to `dev`
# as a doc-only commit. This Dockerfile stays only on the
# `feat/base-1-debian12-refute` branch as evidence.
# ============================================================================
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# hadolint ignore=DL3008
RUN apt-get update -y -q && \
    apt-get install --no-install-recommends -y -q \
        ca-certificates \
        libssl3 \
        libcurl4 \
        libavformat59 \
        libavcodec59 \
        libavutil57 \
        libswresample4 \
        libflac12 \
        libflac++10 \
        libportaudio2 \
        libasound2 \
        libavahi-client3 \
        libavahi-common3 \
        avahi-daemon \
        alsa-utils \
    && rm -rf /var/lib/apt/lists/*

# SONAME compat layer. The vendor binary was linked against Debian-9-era
# SONAMEs (see AGENTS.md §2). Map them onto Debian-12 SO files; the dynamic
# loader will be able to *open* the libraries, which is what `ldd` tests.
# Runtime correctness is **not** expected — see BASE-1.
RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    case "$arch" in \
        armhf) libdir="/usr/lib/arm-linux-gnueabihf" ;; \
        arm64) libdir="/usr/lib/aarch64-linux-gnu"   ;; \
        *) echo "unsupported arch: $arch" >&2; exit 1 ;; \
    esac; \
    ln -sf libssl.so.3        "${libdir}/libssl.so.1.0.0";    \
    ln -sf libcrypto.so.3     "${libdir}/libcrypto.so.1.0.0"; \
    ln -sf libavformat.so.59  "${libdir}/libavformat.so.57";  \
    ln -sf libavcodec.so.59   "${libdir}/libavcodec.so.57";   \
    ln -sf libavutil.so.57    "${libdir}/libavutil.so.55";    \
    ln -sf libswresample.so.4 "${libdir}/libswresample.so.2"; \
    ln -sf libFLAC.so.12      "${libdir}/libFLAC.so.8";       \
    ln -sf libFLAC++.so.10    "${libdir}/libFLAC++.so.6"

# Copy required binaries and scripts
RUN mkdir -p /app/ifi-tidal-release
WORKDIR /app/ifi-tidal-release

COPY src/bin/ bin
COPY src/pa_devs/ .
COPY src/play .
COPY src/id_certificate id_certificate
COPY src/licenses licenses
RUN chmod a+x bin/*

# Set environment variables
ENV PA_ALSA_PLUGHW=1

# Add entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Define entrypoint and default command
ENTRYPOINT ["/entrypoint.sh"]
CMD []
