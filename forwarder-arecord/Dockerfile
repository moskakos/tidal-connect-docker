FROM alpine:3.20

# Install required packages
RUN apk add --no-cache \
    alsa-utils \
    socat \
    curl \
    bash \
    && rm -rf /var/cache/apk/*

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
