#!/bin/bash
# ffmpeg/ffmpeg-entrypoint.sh

# Logging functions
info() {
  echo "[INFO] $1"
}

warning() {
  echo "[WARNING] $1"
}

error() {
  echo "[ERROR] $1"
  # Wait 2 seconds to make sure logs are visible
  sleep 2
  exit 1
}

# Set defaults if not provided in environment
SNAPSERVER_HOST=${SNAPSERVER_HOST:-snapcast}
SNAPSERVER_API_PORT=${SNAPSERVER_API_PORT:-1780} # API port for Snapserver
STREAM_PORT=${STREAM_PORT:-5000}
STREAM_NAME=${STREAM_NAME:-Tidal}
AUDIO_FORMAT=${AUDIO_FORMAT:-flac}
AUDIO_DEVICE=${AUDIO_DEVICE:-plughw:Loopback,0}
SAMPLE_RATE=${SAMPLE_RATE:-44100}
CHANNELS=${CHANNELS:-2}
BUFFER_SIZE=${BUFFER_SIZE:-1024}

info "Starting ffmpeg audio forwarder for Snapserver"
info "Snapserver API: $SNAPSERVER_HOST:$SNAPSERVER_API_PORT"
info "Stream: $STREAM_NAME on port $STREAM_PORT"
info "Audio device: $AUDIO_DEVICE ($SAMPLE_RATE Hz, $CHANNELS channels)"
info "ALSA devices:"
aplay -l || warning "No ALSA devices found or aplay not available"

# Register stream to snapserver
info "Registering stream with Snapserver"
curl -s -X POST http://${SNAPSERVER_HOST}:${SNAPSERVER_API_PORT}/jsonrpc \
  -H 'Content-Type: application/json' \
  -d "{\"id\":1, \"jsonrpc\":\"2.0\", \"method\":\"Stream.AddStream\", \"params\":{\"streamUri\":\"tcp://0.0.0.0:${STREAM_PORT}?name=${STREAM_NAME}&codec=${AUDIO_FORMAT}&sampleformat=${SAMPLE_RATE}:16:${CHANNELS}\"}}"

if [ $? -ne 0 ]; then
  warning "Failed to register stream with Snapserver. Continuing anyway..."
  warning "Check that Snapserver is running on ${SNAPSERVER_HOST}:${SNAPSERVER_API_PORT}"
fi

# Start audio forwarding
info "Starting audio forwarding"
exec ffmpeg -hide_banner -loglevel info \
  -f alsa -ac ${CHANNELS} -ar ${SAMPLE_RATE} -i ${AUDIO_DEVICE} \
  -buffer_size ${BUFFER_SIZE} \
  -c:a ${AUDIO_FORMAT} -f ${AUDIO_FORMAT} \
  tcp://${SNAPSERVER_HOST}:${STREAM_PORT}