#!/bin/bash
set -e

# Defaults
# Set audio output device (use environment variable if provided, otherwise default)
TC_DEVICE="${TC_DEVICE:-plughw:0,0}"
#SNAPCLIENT_DEVICE="${SNAPCLIENT_DEVICE:-plughw:0,1}"

# Start speaker controller in background
echo "===> Starting Speaker Controller in tmux session"
tmux new-session -d -s speaker_controller_application '/app/ifi-tidal-release/bin/speaker_controller_application'

# Start Tidal Connect with the configured device
echo "===> Starting Tidal Connect with device ($TC_DEVICE)"
/app/ifi-tidal-release/bin/tidal_connect_application \
   --tc-certificate-path "/app/ifi-tidal-release/id_certificate/IfiAudio_ZenStream.dat" \
   --playback-device "$TC_DEVICE" \
   -f "Tidal Connect (Docker)" \
   --codec-mpegh true \
   --codec-mqa false \
   --model-name "Tidal Docker" \
   --disable-app-security false \
   --disable-web-security false \
   --enable-mqa-passthrough false \
   --log-level 3 \
   --enable-websocket-log "0" &

# Wait for processes to finish
PID_TIDAL=$!
wait $PID_TIDAL

echo "===> TIDAL Connect Container has stopped."