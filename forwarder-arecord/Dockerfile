# Alpine 3.20 manifest list digest (pulled 2026-04-17). Pinning the
# digest makes the build reproducible across hosts and CI re-runs.
# To pick up a newer 3.20.x security patch, refresh with:
#   docker buildx imagetools inspect alpine:3.20
# and update the @sha256:... below.
FROM alpine:3.20@sha256:d9e853e87e55526f6b2917df91a2115c36dd7c696a35be12163d44e6e2a4b6bc

# Install required packages
RUN apk add --no-cache \
    alsa-utils \
    socat \
    curl \
    bash \
    && rm -rf /var/cache/apk/*

# Run as a dedicated non-root user. The audio-host group is created
# with GID 29 to match the host's audio group (Debian standard), so
# the bind-mounted /dev/snd device nodes (group=29) remain readable.
# Alpine's own 'audio' group at GID 18 is left untouched.
RUN addgroup -g 29 -S audio-host \
 && adduser -D -H -u 1001 -G audio-host forwarder

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Healthcheck: the forwarder is healthy as long as the capture
# pipeline is running. arecord is the longest-lived process and the
# one that fails first when /dev/snd, the Loopback PCM, or ALSA
# permissions break, so its presence is a reliable liveness signal.
# Uses busybox pgrep (no extra package needed). The probe avoids
# anything that depends on Snapserver reachability so a momentary
# Snapserver hiccup does not flap the container.
#
# start-period covers the AddStream retry loop in entrypoint.sh
# (up to ~6 attempts with exponential backoff capped at 30 s, but
# the warm-cache case lands in ~1-2 s, so 30 s is a comfortable
# upper bound for normal startup without masking real failures).
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD pgrep -x arecord >/dev/null || exit 1

USER forwarder

ENTRYPOINT ["/entrypoint.sh"]
