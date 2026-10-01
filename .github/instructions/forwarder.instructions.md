---
description: "Constraints and conventions for the audio forwarder (arecord+socat / Snapserver bridge). Apply when editing anything under forwarder-*/."
applyTo: "forwarder-*/**"
---

# Audio forwarder — agent instructions

## What this container does

Reads PCM audio from an ALSA loopback capture device with `arecord`,
registers a stream with Snapserver via JSON-RPC, and forwards the raw
PCM to that stream over TCP with `socat`. This is the sole forwarder
shipped in this repo. A historical `ffmpeg`-based implementation was
removed because its idle CPU on ARM-emulated hosts was ~15× higher
(see [docs/performance-baseline.md](../../docs/performance-baseline.md))
and it offered no functionality the current setup needs.

## Hard rules

1. **Snapserver stream lifecycle must be respected.** Always:
   - `Stream.AddStream` on container start (idempotent in practice — log a
     warning if it fails but do not crash).
   - `Stream.RemoveStream` on `SIGTERM` / `SIGINT` / `EXIT`. Stale streams
     pile up in Snapserver and confuse clients.
2. **Sample format, rate, and channel count sent in `Stream.AddStream` must
   exactly match what the forwarder actually transmits.** Mismatches cause
   silent corruption or noise.
3. **Codec is PCM only** (`s16le` on the ALSA side, `pcm` on the Snapcast
   side). FLAC caused dropouts in the old ffmpeg forwarder; the arecord
   pipeline has no re-encoding step and PCM is the only sensible output.
4. **The forwarder must reach Snapserver over the network defined in
   `docker-compose.yml`.** Currently `network_mode: host`. Any
   architectural change must work with this networking model.

## Performance constraint

Idle CPU on the reference host (x86 + ARM-emulated Proxmox VM, 2 vCPU)
is ~1.4 % median with the current pipeline. Regressions above ~5 %
require investigation before merging. Always compare on the same host;
results live in [docs/performance-baseline.md](../../docs/performance-baseline.md).

## Entrypoint conventions

When editing `forwarder-arecord/entrypoint.sh`:

- Use the existing `info` / `warning` / `error` / `remove_stream` /
  `cleanup` helpers.
- `trap cleanup SIGTERM SIGINT EXIT` is mandatory.
- Background the audio process (`&`), capture PID, `wait $PID`, then fall
  through to `cleanup`. This pattern lets signal handlers run promptly.
- All env-var defaults live at the top of the script in one block. Do not
  scatter `${VAR:-default}` throughout the body.

## ALSA buffering knobs

`PERIOD_TIME` / `BUFFER_TIME` env vars **must be edited in sync**:

- `BUFFER_TIME` must be a small integer multiple of `PERIOD_TIME`
  (typically 2..8). ALSA silently rounds otherwise.
- Smaller period = lower latency, more wake-ups, higher CPU. The default
  policy here is **low CPU first** — keep periods at ALSA's auto-chosen
  values (currently 125 ms / 500 ms for snd-aloop) unless there is a
  measured reason to shrink them.
- Whenever you change defaults in the entrypoint, update the matching
  env-var rows in `docker-compose.yml` with the same numbers and an
  inline comment explaining the trade-off.
- The effective values can be read live from
  `/proc/asound/<card>/pcm*c/sub*/hw_params` while the forwarder is
  running — verify after every change.

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

- Do **not** add transcoding or quality-altering filters. The forwarder's
  job is to move bytes, not to "improve" the audio. If someone proposes
  re-adding ffmpeg, point them at the performance baseline.
- Do **not** introduce a persistent connection to Snapserver's WebSocket
  API just to register a stream — JSON-RPC over HTTP is sufficient and
  matches existing convention.
- Do **not** assume the Snapserver hostname resolves immediately on
  container start. If you add a readiness check, make it retry with backoff
  rather than fail hard.
- Do **not** introduce Python or Node for orchestration. Shell + small
  utilities (`curl`, `socat`, `arecord`, `jq` if needed) is the convention.
