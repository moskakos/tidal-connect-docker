---
description: "Constraints and conventions for the audio forwarder (ffmpeg / Snapcast bridge). Apply when editing anything under ffmpeg/ or alternative forwarder implementations."
applyTo: "ffmpeg/**,forwarder-*/**"
---

# Audio forwarder — agent instructions

## What this container does

Reads PCM audio from an ALSA loopback capture device, registers a stream
with Snapserver via JSON-RPC, and forwards the audio over TCP to that
stream. Currently implemented with `linuxserver/ffmpeg`; alternative
lower-CPU implementations are an active area of development.

## Hard rules

1. **Snapserver stream lifecycle must be respected.** Always:
   - `Stream.AddStream` on container start (idempotent in practice — log a
     warning if it fails but do not crash).
   - `Stream.RemoveStream` on `SIGTERM` / `SIGINT` / `EXIT`. Stale streams
     pile up in Snapserver and confuse clients.
2. **Sample format, rate, and channel count sent in `Stream.AddStream` must
   exactly match what the forwarder actually transmits.** Mismatches cause
   silent corruption or noise.
3. **Default codec is PCM** (`s16le` / `pcm_s16le` on the ffmpeg side, `pcm`
   on the Snapcast side). FLAC has caused dropouts in this setup; do not
   change the default.
4. **The forwarder must reach Snapserver over the network defined in
   `docker-compose.yml`.** Currently `network_mode: host`. New forwarder
   implementations must work with this networking model.

## Performance constraints (important)

When this container runs in an ARM-emulated VM on an x86 host, ffmpeg's
ALSA capture + resampling loop currently consumes ~33 % of 2 vCPUs **even
at idle** (no audio playing). This is the primary motivation for
considering alternative implementations:

- `arecord | socat TCP:...` — minimal CPU, no resampling, no codec wrapping
- Snapcast `process://` or `pipe://` source — only spawns the reader when a
  client is actively listening
- Snapcast native ALSA source — eliminates this container entirely if
  Snapserver runs on the same host

Any alternative implementation **must** be measured against the current
ffmpeg implementation on the same host before claiming improvement. Record
results in `docs/performance-baseline.md`.

## Entrypoint conventions

When editing `ffmpeg/entrypoint.sh` (or writing a new forwarder
entrypoint):

- Use the existing `info` / `warning` / `error` / `remove_stream` /
  `cleanup` helpers. Copy the pattern verbatim for new implementations.
- `trap cleanup SIGTERM SIGINT` is mandatory.
- Background the audio process (`&`), capture PID, `wait $PID`, then fall
  through to `cleanup`. This pattern lets signal handlers run promptly.
- All env-var defaults live at the top of the script in one block. Do not
  scatter `${VAR:-default}` throughout the body.

## Snapserver JSON-RPC

Endpoint: `http://${SNAPSERVER_HOST}:${SNAPSERVER_API_PORT}/jsonrpc`

Methods used:
- `Stream.AddStream` with `streamUri` like
  `tcp://0.0.0.0:${PORT}?name=${NAME}&codec=${CODEC}&sampleformat=${RATE}:16:${CHANNELS}`
- `Stream.RemoveStream` with `id` equal to the stream `name`

Snapserver replies with JSON; current scripts ignore the body and rely on
`curl` exit code. This is acceptable but improving error handling (parse
the JSON, log the result code) is a welcome enhancement.

## Anti-patterns

- Do **not** add transcoding or quality-altering filters by default. The
  forwarder's job is to move bytes, not to "improve" the audio.
- Do **not** introduce a persistent connection to Snapserver's WebSocket
  API just to register a stream — JSON-RPC over HTTP is sufficient and
  matches existing convention.
- Do **not** assume the Snapserver hostname resolves immediately on
  container start. If you add a readiness check, make it retry with backoff
  rather than fail hard.
- Do **not** introduce Python or Node for orchestration. Shell + small
  utilities (`curl`, `socat`, `arecord`, `jq` if needed) is the convention.
