FROM alpine:3.20

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
