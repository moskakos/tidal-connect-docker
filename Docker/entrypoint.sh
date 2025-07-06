#!/bin/bash

# Enable better error reporting
set -e

# Set audio output device
TC_DEVICE="${TC_DEVICE:-plughw:0,0}"

echo "===> Checking system configuration"
echo "- Audio device: $TC_DEVICE"
echo "- System info: $(uname -a)"
echo "- ALSA devices:"
aplay -l || echo "  No ALSA devices found or aplay not available"

# Start necessary services
echo "===> Starting dbus service"
service dbus start

echo "===> Starting Avahi daemon"
service avahi-daemon start &
# Give Avahi time to start properly
sleep 2
# Check if Avahi is actually running
if pgrep avahi-daemon > /dev/null; then
  echo "- Avahi daemon started successfully"
  avahi-browse -at || echo "  Cannot browse Avahi services"
else
  echo "- Warning: Avahi daemon failed to start"
fi

# Start speaker controller in background
echo "===> Starting Speaker Controller"
tmux new-session -d -s speaker_controller_application '/app/ifi-tidal-release/bin/speaker_controller_application'
if [ $? -eq 0 ]; then
  echo "- Speaker controller started successfully"
else
  echo "- Warning: Speaker controller failed to start"
fi

# Start Tidal Connect with the configured device
echo "===> Starting Tidal Connect with device ($TC_DEVICE)"
echo "- Tidal Connect version: $(cat /app/ifi-tidal-release/version.txt 2>/dev/null || echo 'unknown')"

# Run Tidal Connect with proper error handling
/app/ifi-tidal-release/bin/tidal_connect_application \
   --tc-certificate-path "/app/ifi-tidal-release/id_certificate/IfiAudio_ZenStream.dat" \
   --playback-device "$TC_DEVICE" \
   -f "Tidal Connect (Docker)" \
   --codec-mpegh true \
   --codec-mqa false \
   --model-name "Tidal Docker" \
   --disable-app-security true \
   --disable-web-security true \
   --enable-mqa-passthrough false \
   --log-level 4 \
   --enable-websocket-log "0"

# Capture the exit code
TIDAL_EXIT_CODE=$?

# Print detailed error information if there was an issue
if [ $TIDAL_EXIT_CODE -ne 0 ]; then
  echo "===> ERROR: Tidal Connect exited with code $TIDAL_EXIT_CODE"
  echo "- Last 20 lines of system log:"
  dmesg | tail -20
  echo "- Process information:"
  ps aux | grep -E "tidal|avahi|dbus" || echo "  No relevant processes found"
  echo "- Library dependencies:"
  ldd /app/ifi-tidal-release/bin/tidal_connect_application || echo "  ldd command not available"
  echo "===> Please check the logs above for troubleshooting information."
else
  echo "===> Tidal Connect exited normally."
fi

echo "===> TIDAL Connect Container has stopped."
exit $TIDAL_EXIT_CODE