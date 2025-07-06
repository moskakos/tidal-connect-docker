#!/bin/bash
# tidal-connect entrypoint.sh

set -e

# Logging functions
info() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $1"
}

warning() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') [WARNING] $1"
}

error() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $1"
  # Wait 2 seconds to make sure logs are visible
  sleep 2
  exit 1
}

# Configuration variables with defaults
# Audio output device
OUTPUT_DEVICE="${OUTPUT_DEVICE:-plughw:0,0}"
# Tidal Connect configuration
TC_NAME="${TC_NAME:-Tidal Connect (Docker)}"
TC_MODEL="${TC_MODEL:-Tidal Docker}"
TC_CODEC_MPEGH="${TC_CODEC_MPEGH:-true}"
TC_CODEC_MQA="${TC_CODEC_MQA:-false}"
TC_MQA_PASSTHROUGH="${TC_MQA_PASSTHROUGH:-false}"
TC_DISABLE_APP_SEC="${TC_DISABLE_APP_SECURITY:-false}"
TC_DISABLE_WEB_SEC="${TC_DISABLE_WEB_SECURITY:-false}"
TC_LOG_LEVEL="${TC_LOG_LEVEL:-3}"
TC_WEBSOCKET_LOG="${TC_WEBSOCKET_LOG:-0}"
# Enable or disable speaker controller
SC_ENABLE="${SC_ENABLE:-true}"

# Check system configuration
info "Checking system configuration"
info "Audio device: $OUTPUT_DEVICE"
info "System info: $(uname -a)"
info "ALSA devices:"
aplay -l || warning "No ALSA devices found or aplay not available"

# Start required services
info "Starting dbus service"
service dbus start

info "Starting Avahi daemon"
service avahi-daemon start &
sleep 2
if pgrep avahi-daemon > /dev/null; then
  info "Avahi daemon started successfully"
  avahi-browse -at || warning "Cannot browse Avahi services"
else
  warning "Avahi daemon failed to start"
fi

# Start speaker controller if enabled
if [ "$SC_ENABLE" = "true" ]; then
  info "Starting Speaker Controller"
  tmux new-session -d -s speaker_controller_application '/app/ifi-tidal-release/bin/speaker_controller_application'
  if [ $? -eq 0 ]; then
    info "Speaker controller started successfully"
  else
    warning "Speaker controller failed to start"
  fi
else
  info "Speaker Controller is disabled, not starting"
fi

# Start Tidal Connect
info "Starting Tidal Connect with device ($OUTPUT_DEVICE)"
info "Tidal Connect version: $(cat /app/ifi-tidal-release/version.txt 2>/dev/null || echo 'unknown')"

# Run Tidal Connect
/app/ifi-tidal-release/bin/tidal_connect_application \
  --tc-certificate-path "/app/ifi-tidal-release/id_certificate/IfiAudio_ZenStream.dat" \
  --playback-device "$OUTPUT_DEVICE" \
  -f "$TC_NAME" \
  --model-name "$TC_MODEL" \
  --codec-mpegh "$TC_CODEC_MPEGH" \
  --codec-mqa "$TC_CODEC_MQA" \
  --enable-mqa-passthrough "$TC_MQA_PASSTHROUGH" \
  --disable-app-security "$TC_DISABLE_APP_SEC" \
  --disable-web-security "$TC_DISABLE_WEB_SEC" \
  --log-level "$TC_LOG_LEVEL" \
  --enable-websocket-log "$TC_WEBSOCKET_LOG"

# Capture exit code
TIDAL_EXIT_CODE=$?

# Error reporting
if [ $TIDAL_EXIT_CODE -ne 0 ]; then
  error "Tidal Connect exited with code $TIDAL_EXIT_CODE"
  info "Last 20 lines of system log:"
  dmesg | tail -20
  info "Process information:"
  ps aux | grep -E "tidal|avahi|dbus" || warning "No relevant processes found"
  info "Library dependencies:"
  ldd /app/ifi-tidal-release/bin/tidal_connect_application || warning "ldd command not available"
  error "Please check the logs above for troubleshooting information."
else
  info "Tidal Connect exited normally."
fi

info "TIDAL Connect Container has stopped."
exit $TIDAL_EXIT_CODE