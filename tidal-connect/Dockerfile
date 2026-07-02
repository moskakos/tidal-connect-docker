FROM raspbian/stretch

# Update apt sources and install required dependencies
RUN echo 'deb http://archive.raspberrypi.org/debian/ stretch main' > /etc/apt/sources.list && \
    echo 'deb http://legacy.raspbian.org/raspbian stretch main contrib non-free rpi firmware' >> /etc/apt/sources.list && \
    echo 'deb-src http://legacy.raspbian.org/raspbian stretch main contrib non-free rpi firmware' >> /etc/apt/sources.list && \
    sed -i 's/^deb /deb [trusted=yes] /' /etc/apt/sources.list && \
    sed -i 's/^deb-src /deb-src [trusted=yes] /' /etc/apt/sources.list && \
    apt-get -o Acquire::Check-Valid-Until=false update -y -q && \
    apt-get upgrade -y -q --allow-unauthenticated

# Install required libraries
RUN apt install --fix-missing --fix-broken -y -q \
    libavformat57 \
    libportaudio2 \
    libflac++6v5 \
    libavahi-common3 \
    libavahi-client3 \
    avahi-daemon \
    alsa-utils \
    curl \
    portaudio19-dev \
    tmux \
    libasound2 \
    libvorbis0a \
    libsoxr0

# Force old libssl & libcurl due to dependency requirements
RUN curl -fk -O -L https://snapshot.debian.org/archive/debian-security/20190925T215334Z/pool/updates/main/o/openssl/libssl1.0.0_1.0.1t-1%2Bdeb8u12_armhf.deb && \
    apt install -y ./libssl1.0.0_1.0.1t-1%2Bdeb8u12_armhf.deb && \
    rm ./libssl1.0.0_1.0.1t-1%2Bdeb8u12_armhf.deb

RUN curl -fk -O -L https://snapshot.debian.org/archive/debian-security/20190913T112238Z/pool/updates/main/c/curl/libcurl3_7.38.0-4%2Bdeb8u16_armhf.deb && \
    apt install -y ./libcurl3_7.38.0-4%2Bdeb8u16_armhf.deb --allow-downgrades && \
    rm ./libcurl3_7.38.0-4%2Bdeb8u16_armhf.deb

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
