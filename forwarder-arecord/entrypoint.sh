#!/bin/bash
# forwarder-arecord/entrypoint.sh
# Minimal arecord + socat forwarder for Snapcast

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

# Function to remove stream from Snapserver
remove_stream() {
  # Check if Snapserver parameters are set
  if [ -z "${SNAPSERVER_HOST}" ] || [ -z "${SNAPSERVER_API_PORT}" ]; then
    warning "Snapserver parameters not defined, skipping stream removal"
    return
  fi
  
  info "Removing stream from Snapserver"
  curl -s -X POST "http://${SNAPSERVER_HOST}:${SNAPSERVER_API_PORT}/jsonrpc" \
    -H 'Content-Type: application/json' \
    -d "{\"id\":1, \"jsonrpc\":\"2.0\", \"method\":\"Stream.RemoveStream\", \"params\":{\"id\":\"${STREAM_NAME}\"}}"
  
  if [ $? -ne 0 ]; then
    warning "Failed to remove stream from Snapserver."
  else
    info "Stream removed successfully"
  fi
}

# Signal handler function
cleanup() {
  info "Container stopping, cleaning up..."
  
  # Kill the pipeline if it's running
  if [ -n "$PIPELINE_PID" ] && kill -0 "$PIPELINE_PID" 2>/dev/null; then
    info "Stopping audio pipeline"
    kill "$PIPELINE_PID"
    wait "$PIPELINE_PID" 2>/dev/null
  fi
  
  # Remove stream from snapserver
  remove_stream
  exit 0
}

# Set up signal trap (including EXIT for proper cleanup on normal exit)
trap cleanup SIGTERM SIGINT EXIT

# Set defaults if not provided in environment
SNAPSERVER_HOST=${SNAPSERVER_HOST:-snapcast}
SNAPSERVER_API_PORT=${SNAPSERVER_API_PORT:-1780}
STREAM_PORT=${STREAM_PORT:-5000}
STREAM_NAME=${STREAM_NAME:-Tidal}
AUDIO_DEVICE=${AUDIO_DEVICE:-plughw:Loopback,0}
SAMPLE_RATE=${SAMPLE_RATE:-44100}
CHANNELS=${CHANNELS:-2}
# ALSA capture buffering, in microseconds. Defaults reproduce what
# snd-aloop picked automatically before these knobs existed (period
# 125 ms, buffer 500 ms = 4 periods), which keeps idle CPU low.
#
# IMPORTANT — keep BUFFER_TIME a small integer multiple of PERIOD_TIME
# (typically 2..8). ALSA will round otherwise, and the actual numbers
# may differ from what you set. The forwarder logs both the requested
# and (via /proc/asound) the effective values; verify after changing.
#
# Trade-offs:
#   smaller PERIOD_TIME -> lower capture-side latency, more wake-ups
#                          per second, slightly higher CPU
#   larger  PERIOD_TIME -> fewer wake-ups, more dropout margin, lower CPU
# Snapcast itself buffers ~1000 ms downstream, so total end-to-end
# latency is dominated by that, not by these values.
PERIOD_TIME=${PERIOD_TIME:-125000}
BUFFER_TIME=${BUFFER_TIME:-500000}

info "Starting arecord audio forwarder for Snapserver"
info "Snapserver API: $SNAPSERVER_HOST:$SNAPSERVER_API_PORT"
info "Stream: $STREAM_NAME on port $STREAM_PORT"
info "Audio device: $AUDIO_DEVICE ($SAMPLE_RATE Hz, $CHANNELS channels)"
info "ALSA buffering: period_time=${PERIOD_TIME} us, buffer_time=${BUFFER_TIME} us"
info "ALSA devices:"
aplay -l || warning "No ALSA devices found or aplay not available"

# Register stream to snapserver
info "Registering stream with Snapserver"
curl -s -X POST "http://${SNAPSERVER_HOST}:${SNAPSERVER_API_PORT}/jsonrpc" \
  -H 'Content-Type: application/json' \
  -d "{\"id\":1, \"jsonrpc\":\"2.0\", \"method\":\"Stream.AddStream\", \"params\":{\"streamUri\":\"tcp://0.0.0.0:${STREAM_PORT}?name=${STREAM_NAME}&codec=pcm&sampleformat=${SAMPLE_RATE}:16:${CHANNELS}\"}}"

if [ $? -ne 0 ]; then
  warning "Failed to register stream with Snapserver. Continuing anyway..."
  warning "Check that Snapserver is running on ${SNAPSERVER_HOST}:${SNAPSERVER_API_PORT}"
fi

# Start audio forwarding (as background process)
info "Starting audio forwarding with arecord + socat"
arecord -D "$AUDIO_DEVICE" -f S16_LE -r "$SAMPLE_RATE" -c "$CHANNELS" \
  --period-time="$PERIOD_TIME" --buffer-time="$BUFFER_TIME" -t raw 2>&1 | \
  socat - "TCP:${SNAPSERVER_HOST}:${STREAM_PORT}" &

# Save pipeline PID so we can terminate it properly
PIPELINE_PID=$!

# Wait for the pipeline to exit
wait "$PIPELINE_PID"

# If the pipeline exits on its own, cleanup will be called via the EXIT trap
