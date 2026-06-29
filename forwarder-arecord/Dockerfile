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

USER forwarder

ENTRYPOINT ["/entrypoint.sh"]
