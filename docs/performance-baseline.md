# Performance baseline

This document tracks idle CPU usage measurements of different audio forwarder
implementations across different host environments. All measurements use the
`scripts/measure-idle-cpu.sh` script.

## What is measured

**Idle CPU** — CPU usage when the TIDAL app is connected but no audio is
actively playing. This is the primary metric for comparing forwarder
implementations, since the user's target environment (ARM-emulated Proxmox VM)
shows high idle CPU with the ffmpeg-based forwarder (~33 % of 2 vCPU).

**Peak CPU** — Optional measurement during active playback. Less critical than
idle, but useful for validating that alternative implementations don't trade
idle efficiency for playback overhead.

## How to measure

1. Start the containers with the forwarder you want to test:
   ```bash
   # For ffmpeg (default):
   docker compose up -d
   
   # For arecord:
   docker compose --profile arecord up -d
   ```

2. Connect the TIDAL app to the device but **do not play anything**.

3. Run the measurement script (default: 60 seconds, sampling every 5 seconds):
   ```bash
   ./scripts/measure-idle-cpu.sh 60 tidal-forwarder
   # or for arecord:
   ./scripts/measure-idle-cpu.sh 60 tidal-forwarder-arecord
   ```

4. Record the min/mean/max CPU% values below.

5. Optionally, repeat the measurement during active playback to capture peak CPU.

## Baseline measurements

| Date (UTC) | Host description | Forwarder | Idle CPU min/mean/max % | Notes |
|------------|------------------|-----------|-------------------------|-------|
| 2026-06-26 | `tidal-dev` Proxmox VM, Debian 13 trixie, kernel 6.12.94, **aarch64 emulated on x86 host** (QEMU full-system, no KVM), 2 vCPU, Docker 29.6.1, Compose v5.2.0 | `ffmpeg` (linuxserver/ffmpeg:latest, PCM `pcm_s16le` 44.1 kHz stereo) | **18.58 / 21.57 / 24.53** | TIDAL app not connected; pipeline running on empty ALSA loopback. 60 s sample, 5 s interval. |
| 2026-06-26 | same as above | `arecord` prototype (alpine:3.20 + alsa-utils + socat, PCM) | **1.22 / 1.43 / 1.81** | Same conditions. Forwarder registered stream with Snapserver (JSON-RPC OK) and started forwarding. |

**Observation:** On the same x86-hosted, ARM-emulated Proxmox VM that
previously showed ~33 % idle CPU with `ffmpeg`, the `arecord` forwarder
consumes **~15× less idle CPU** (mean 1.43 % vs. 21.57 %). The lower
ffmpeg number compared to the historical ~33 % reference is likely due to
Debian 13 / kernel 6.12 / Docker 29 updates on the host stack; the
**ratio** between the two forwarders is the meaningful signal.

**Caveats:**

- "Idle" here means: containers started, TIDAL app **not connected**. With an
  active TIDAL session sitting idle (connected, paused), CPU may be different.
  This measurement is the lower bound.
- Active playback CPU is not yet measured; that requires real TIDAL traffic.
- `tidal-connect` container CPU was not measured separately; it is identical
  across both forwarder variants and not the optimization target.

## How to record a new baseline

1. Ensure the environment is stable (no other heavy processes, TIDAL app
   connected but idle).
2. Run the measurement script as described above.
3. Add a row to the table with:
   - Current UTC date
   - Brief host description (OS, CPU count, architecture, virtualization if any)
   - Forwarder variant (`ffmpeg`, `arecord`, etc.)
   - Min / mean / max CPU% from the script output
   - Any relevant notes (codec, special configuration, etc.)
4. Commit the change:
   ```bash
   git add docs/performance-baseline.md
   git commit -m "docs: record baseline for <forwarder> on <host>"
   ```
5. Repeat for each forwarder variant you want to compare.
