#!/bin/bash
# ffmpeg/ffmpeg-entrypoint.sh

# Set defaults if not provided in environment
SNAPSERVER_HOST=${SNAPSERVER_HOST:-snapcast}
SNAPSERVER_PORT=${SNAPSERVER_PORT:-1705}
STREAM_PORT=${STREAM_PORT:-5000}
STREAM_NAME=${STREAM_NAME:-Tidal}
AUDIO_FORMAT=${AUDIO_FORMAT:-flac}
AUDIO_DEVICE=${AUDIO_DEVICE:-plughw:Loopback,0}
SAMPLE_RATE=${SAMPLE_RATE:-44100}
CHANNELS=${CHANNELS:-2}
BUFFER_SIZE=${BUFFER_SIZE:-1024}

echo "==> Starting Snapcast audio forwarder"
echo "- Snapserver: $SNAPSERVER_HOST:$SNAPSERVER_PORT"
echo "- Stream: $STREAM_NAME on port $STREAM_PORT"
echo "- Audio device: $AUDIO_DEVICE ($SAMPLE_RATE Hz, $CHANNELS channels)"

# Register stream to snapserver
echo "==> Registering stream with Snapserver"
curl -s -X POST http://${SNAPSERVER_HOST}:${SNAPSERVER_PORT}/json \
  -H 'Content-Type: application/json' \
  -d "{\"action\":\"add\",\"stream\":\"tcp://0.0.0.0:${STREAM_PORT}?name=${STREAM_NAME}&sampleformat=${SAMPLE_RATE}:16:${CHANNELS}\"}"

if [ $? -ne 0 ]; then
  echo "WARNING: Failed to register stream with snapserver. Continuing anyway..."
fi

# Start audio forwarding
echo "==> Starting audio forwarding"
exec ffmpeg -hide_banner -loglevel info \
  -f alsa -ac ${CHANNELS} -ar ${SAMPLE_RATE} -i ${AUDIO_DEVICE} \
  -buffer_size ${BUFFER_SIZE} \
  -c:a ${AUDIO_FORMAT} -f ${AUDIO_FORMAT} \
  tcp://${SNAPSERVER_HOST}:${STREAM_PORT}