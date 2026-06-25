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
<!-- Example: -->
<!-- | 2026-06-25 | Proxmox 8.x VM, ARM64 emulated on x86, 2 vCPU | ffmpeg | 30 / 33 / 36 | Baseline, PCM codec | -->
<!-- | 2026-06-25 | Proxmox 8.x VM, ARM64 emulated on x86, 2 vCPU | arecord | 5 / 8 / 12 | First arecord prototype, PCM codec | -->

*No baselines recorded yet. See "How to record a new baseline" below.*

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
