#!/bin/bash
set -e

# Defaultit
TC_DEVICE="${TC_DEVICE:-plughw:0,0}"
SNAPCLIENT_DEVICE="${SNAPCLIENT_DEVICE:-plughw:0,1}"
SNAPSERVER_HOST="${SNAPSERVER_HOST:-127.0.0.1}"

echo "===> Käynnistetään Speaker Controller (tmux taustalla)"
tmux new-session -d -s speaker_controller_application '/app/ifi-tidal-release/bin/speaker_controller_application'

echo "===> Käynnistetään Tidal Connect ($TC_DEVICE)"
/app/ifi-tidal-release/bin/tidal_connect_application \
   --tc-certificate-path "/app/ifi-tidal-release/id_certificate/IfiAudio_ZenStream.dat" \
   --playback-device "${TC_DEVICE}" \
   -f "Tidal Connect (Docker)" \
   --codec-mpegh true \
   --codec-mqa false \
   --model-name "Tidal Docker" \
   --disable-app-security false \
   --disable-web-security false \
   --enable-mqa-passthrough false \
   --log-level 3 \
   --enable-websocket-log "0" &

PID_TIDAL=$!

echo "===> Käynnistetään Snapclient (laite: ${SNAPCLIENT_DEVICE}, isäntä: ${SNAPSERVER_HOST})"
snapclient -h "${SNAPSERVER_HOST}" --player alsa --device "${SNAPCLIENT_DEVICE}" --hostID tidal-connect-docker &

PID_SNAP=$!

# Odotetaan molempien prosessien valmistumista
wait $PID_TIDAL $PID_SNAP

echo "===> TIDAL Connect Container sammui."
