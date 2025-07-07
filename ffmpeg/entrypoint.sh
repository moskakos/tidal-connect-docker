#!/bin/bash
# ffmpeg/ffmpeg-entrypoint.sh

# Function to remove stream from Snapserver
remove_stream() {
  # Check if Snapserver parameters are set
  if [ -z "${SNAPSERVER_HOST}" ] || [ -z "${SNAPSERVER_API_PORT}" ]; then
    warning "Snapserver parameters not defined, skipping stream removal"
    return
  fi
  
  info "Removing stream from Snapserver"
  curl -s -X POST http://${SNAPSERVER_HOST}:${SNAPSERVER_API_PORT}/jsonrpc \
    -H 'Content-Type: application/json' \
    -d "{\"id\":1, \"jsonrpc\":\"2.0\", \"method\":\"Stream.RemoveStream\", \"params\":{\"id\":\"${STREAM_NAME}\"}}"
  
  if [ $? -ne 0 ]; then
    warning "Failed to remove stream from Snapserver."
  else
    info "Stream removed successfully"
  fi
}

# Logging functions
info() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $1"
}

warning() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') [WARNING] $1"
}

error() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $1"
  # Try to clean up the stream
  remove_stream
  # Wait 2 seconds to make sure logs are visible
  sleep 2
  exit 1
}

# Signal handler function
cleanup() {
  info "Container stopping, cleaning up..."
  # Kill ffmpeg if it's running
  if [ ! -z "$FFMPEG_PID" ] && kill -0 $FFMPEG_PID 2>/dev/null; then
    info "Stopping ffmpeg process"
    kill $FFMPEG_PID
    wait $FFMPEG_PID 2>/dev/null
  fi
  
  # Remove stream from snapserver
  remove_stream
  exit 0
}

# Set up signal trap
trap cleanup SIGTERM SIGINT

# Loput skriptistä kuten aiemmin...

# Set defaults if not provided in environment
SNAPSERVER_HOST=${SNAPSERVER_HOST:-snapcast}
SNAPSERVER_API_PORT=${SNAPSERVER_API_PORT:-1780}
STREAM_PORT=${STREAM_PORT:-5000}
STREAM_NAME=${STREAM_NAME:-Tidal}
FFMPEG_AUDIO_FORMAT=${FFMPEG_AUDIO_FORMAT:-flac}
FFMPEG_AUDIO_CODEC=${FFMPEG_AUDIO_CODEC:-flac}
SC_AUDIO_CODEC=${SC_AUDIO_CODEC:-flac}
AUDIO_DEVICE=${AUDIO_DEVICE:-plughw:Loopback,0}
SAMPLE_RATE=${SAMPLE_RATE:-44100}
CHANNELS=${CHANNELS:-2}
BUFFER_SIZE=${BUFFER_SIZE:-1024}
AUDIO_BUFFER=${AUDIO_BUFFER:-2048}
AUDIO_QUALITY=${AUDIO_QUALITY:-5}

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
  -d "{\"id\":1, \"jsonrpc\":\"2.0\", \"method\":\"Stream.AddStream\", \"params\":{\"streamUri\":\"tcp://0.0.0.0:${STREAM_PORT}?name=${STREAM_NAME}&codec=${SC_AUDIO_CODEC}&sampleformat=${SAMPLE_RATE}:16:${CHANNELS}\"}}"

if [ $? -ne 0 ]; then
  warning "Failed to register stream with Snapserver. Continuing anyway..."
  warning "Check that Snapserver is running on ${SNAPSERVER_HOST}:${SNAPSERVER_API_PORT}"
fi

# Start audio forwarding (as background process)
info "Starting audio forwarding with enhanced quality"
ffmpeg -hide_banner -loglevel info \
  -f alsa \
  -thread_queue_size 4096 \
  -ac ${CHANNELS} \
  -ar ${SAMPLE_RATE} \
  -i ${AUDIO_DEVICE} \
  -buffer_size ${BUFFER_SIZE} \
  -af "aresample=async=1000:min_hard_comp=0.01:first_pts=0" \
  -c:a ${FFMPEG_AUDIO_CODEC} \
  -compression_level ${AUDIO_QUALITY} \
  -frame_size ${AUDIO_BUFFER} \
  -application audio \
  -fflags nobuffer \
  -flags low_delay \
  -max_delay 500000 \
  -f ${FFMPEG_AUDIO_FORMAT} \
  tcp://${SNAPSERVER_HOST}:${STREAM_PORT} &

# Save ffmpeg PID so we can terminate it properly
FFMPEG_PID=$!

# Wait for ffmpeg to exit
wait $FFMPEG_PID

# If ffmpeg exits on its own, also clean up
cleanup