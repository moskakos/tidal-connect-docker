---
description: "Constraints and conventions for the tidal-connect container (vendor iFi binary, Debian-9 runtime, ARM-only). Apply when editing anything under tidal-connect/."
applyTo: "tidal-connect/**"
---

# tidal-connect container — agent instructions

## What this container is

A Docker image that runs the closed-source iFi Audio `tidal_connect_application`
binary so the TIDAL mobile app can target it as a TIDAL Connect endpoint. The
binary writes PCM audio to an ALSA device (typically a loopback configured by
the host).

## Hard rules

1. **Never modify, rebuild, recompile, replace, or "improve" the binaries in
   `tidal-connect/src/bin/`.** They are vendor artifacts. Patching them
   breaks TIDAL Connect protocol compatibility and likely violates the
   vendor's license terms.
2. **Never delete or move `tidal-connect/src/id_certificate/`.** The binary
   loads `IfiAudio_ZenStream.dat` from this directory at runtime.
3. **The base image must satisfy these runtime requirements** (verified by
   `ldd` against the binary in CI run 28186328355; full output in
   `artefact-28186328355/`):
   - **OpenSSL 1.0** — `libssl.so.1.0.0`, `libcrypto.so.1.0.0`
     (Debian 8/9 only; OpenSSL 1.1/3.0 are not ABI-compatible)
   - **curl** — `libcurl.so.4` (works on Debian 8–12)
   - **FFmpeg 3.x** — `libavformat.so.57`, `libavcodec.so.57`,
     `libavutil.so.55`, `libswresample.so.2` (Debian 9 only; not
     available in Debian 10+ repos at all)
   - **FLAC** — `libFLAC.so.8`, `libFLAC++.so.6` (Debian 9 only;
     Debian 11+ ships `.12`)
   - **Audio/mDNS** — `libportaudio.so.2`, `libasound.so.2`,
     `libavahi-client.so.3`, `libavahi-common.so.3` (compatible across
     Debian 8–12)
   - **glibc** version compatible with the binary's expectations
     (Debian 9's 2.24 works; newer versions need verification).
4. **Avahi + dbus must be running before the binary starts.** mDNS / Bonjour
   discovery is how the TIDAL app finds the endpoint.
5. **`network_mode: host` cannot be removed** from `docker-compose.yml`
   without a working mDNS-bridge alternative (none currently exists in this
   repo).
6. **`PA_ALSA_PLUGHW=1`** is required for PortAudio to use ALSA correctly.

## Architecture notes

- The container is currently armhf-only (`linux/arm/v7`). It runs on arm64
  via multi-arch emulation, and on x86 via QEMU user-mode emulation (slow).
- The TIDAL binary is a long-running foreground process. The entrypoint runs
  it in the background to support signal-based cleanup, then `wait`s on its
  PID.
- `speaker_controller_application` is optional (`SC_ENABLE` env var). It is
  launched inside a `tmux` session because it expects a TTY.

## Entrypoint conventions

When editing `tidal-connect/entrypoint.sh`:

- Preserve `set -e` at the top.
- Preserve the `trap cleanup SIGTERM SIGINT` line; consider adding `EXIT` to
  it so cleanup also runs on normal exit.
- Use `info` / `warning` / `error` for all log output. Never `echo` directly.
- The `/0-entrypoint.sh` override hook must remain functional — users rely
  on it for custom configurations.
- Every new environment variable must:
  - have a sensible default (`VAR="${VAR:-default}"`),
  - be logged at startup via `info`,
  - be documented in [README.md](../../README.md)'s configuration table.

## Debugging tips

- If the binary segfaults on startup after a base-image change, run
  `ldd /app/ifi-tidal-release/bin/tidal_connect_application` inside the
  container to find unresolved symbols.
- `strace -f` is invaluable for diagnosing missing files or syscalls
  rejected by newer kernels.
- The binary logs verbosely at `TC_LOG_LEVEL=4`.

## Anti-patterns

- Do **not** add Python, Node, or other runtimes for tooling around the
  binary. Shell is the convention here.
- Do **not** install build tools (`gcc`, `make`) into the runtime image.
  The binary is pre-built; the container does not compile anything.
- Do **not** add `HEALTHCHECK` commands that depend on network calls to
  external services (e.g. TIDAL servers) — they create flapping in poor
  network conditions.
