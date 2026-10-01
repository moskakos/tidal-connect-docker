# Proposal: single-container x86-base deployment (spin-off)

> **Status:** 🔴 Idea captured for future spin-off project — **not** a
> change to this repository.
> **Scope decision (2026-10-01):** when/if this idea is pursued, it will
> be developed in a **separate repository**, not merged into
> `tidal-connect-docker`. This repo stays platform-agnostic (supports
> both x86 Docker host via ARM emulation and native ARM hardware).
> **Author:** chat discussion 2026-10-01.
> **Related:** [AGENTS.md](../AGENTS.md) §2 (hard constraints — library
> matrix carries over verbatim), BASE-2
> ([tidal-connect/Dockerfile.debian11-vendored](../tidal-connect/Dockerfile.debian11-vendored))
> as the vendoring template.

## Why this proposal exists

A single combined container with an **amd64 base** and **vendored armhf
libraries** for the vendor binary is technically possible and would be
significantly lighter when deployed on an x86 Docker host — the common
dev/test environment today (`tidal-dev` Proxmox VM, GitHub Actions
amd64 runners under QEMU shim).

The project `tidal-connect-docker` itself remains **platform-agnostic**:
multi-arch build matrix (`linux/arm/v7`, `linux/arm64`), two-container
Compose, runs on both x86 Docker hosts via ARM emulation and native ARM
hardware. No changes to this project are proposed by this document.

What this document captures is the **design of a potential sibling
project** whose single purpose is "run TIDAL Connect + Snapcast forwarder
on an x86 Docker host, as cheaply as possible, with zero intent of
targeting native ARM hardware".

### Key insight behind the idea

The vendor binary's armhf nature is a **per-process constraint**, not a
whole-container one. User-mode QEMU (`qemu-arm-static` + binfmt_misc)
translates ARM userspace instructions to x86 per-process, with syscalls
thunked directly to the host x86 kernel. There is no full-system
emulation and no VM. Everything that is not the vendor binary can
therefore run as native x86.

This means a combined container with an amd64 base and vendored armhf
libs can emulate only `tidal_connect_application` /
`speaker_controller_application`, while the forwarder (`arecord`,
`socat`), Avahi, and process supervision run natively.

## Architecture outline

```
Container (single, platform=linux/amd64)
├── x86-native userland (apt-installed on amd64 Debian 12 slim)
│   ├── arecord, socat, avahi-utils      ← forwarder, native x86
│   ├── supervisor (or s6-overlay)        ← process supervisor
│   └── qemu-arm-static                   ← ARM-ELF interpreter (x86 ELF)
└── /opt/tidal/
    ├── bin/
    │   ├── tidal_connect_application     ← armhf, vendor
    │   └── speaker_controller_application ← armhf, vendor
    ├── sysroot/                          ← armhf vendor libs (Debian 9)
    │   ├── lib/ld-linux-armhf.so.3
    │   ├── lib/libssl.so.1.0.0, libcrypto.so.1.0.0
    │   ├── lib/libcurl.so.4 (OpenSSL 1.0-linked)
    │   ├── lib/libavformat.so.57, libavcodec.so.57, libavutil.so.55,
    │   │        libswresample.so.2
    │   ├── lib/libFLAC.so.8, libFLAC++.so.6
    │   ├── lib/libportaudio.so.2
    │   ├── lib/libasound.so.2
    │   └── lib/libavahi-client.so.3, libavahi-common.so.3
    └── id_certificate/
```

**Emulation footprint:** only `tidal_connect_application` and
`speaker_controller_application` run under `qemu-arm-static`. Everything
else is native x86 — the shell, ALSA tools, socat, Avahi, supervisor,
and the kernel path for `read()`/`write()`/`clock_gettime()`/`ioctl()`.

Compare with the current ARM-emulated Proxmox VM where **every**
userspace instruction (including kernel timers' userspace side) goes
through `qemu-system-aarch64`'s TCG.

## Technical approach

### 1. Base image

- **FROM** `debian:bookworm-slim` (amd64 default) — standard, actively
  maintained, no armhf gymnastics.
- Reuse the BASE-2 pattern from
  [tidal-connect/Dockerfile.debian11-vendored](../tidal-connect/Dockerfile.debian11-vendored):
  download Debian 9 armhf `.deb`s from `snapshot.debian.org` during
  build, extract into `/opt/tidal/sysroot/`, point the vendor binary at
  them.
- The one change vs. BASE-2: base is **amd64** instead of **armhf**.
  Everything else about the vendor-lib vendoring is identical.

### 2. ARM dynamic linker and `QEMU_LD_PREFIX`

The vendor ELFs' `.interp` points to `/lib/ld-linux-armhf.so.3`. On an
amd64 base, that path does not exist natively. Two options:

- **Preferred:** set `QEMU_LD_PREFIX=/opt/tidal/sysroot` in the
  entrypoint. `qemu-arm-static` resolves every ARM library lookup
  (including the dynamic linker) against the sysroot prefix.
- Alternative: bind-mount or symlink `/opt/tidal/sysroot/lib/ld-linux-armhf.so.3`
  → `/lib/ld-linux-armhf.so.3`. More fragile; avoid.

### 3. `binfmt_misc` registration

A one-time host-side setup (not image-side):

```bash
docker run --privileged --rm tonistiigi/binfmt --install arm,arm64
```

Registers `qemu-arm-static` / `qemu-aarch64-static` with the kernel
using the `F` (fix-binary) flag, so the interpreter is opened by the
kernel *before* namespace entry and is available inside every
container, including read-only / restricted ones. The image does not
need to carry `qemu-arm-static` at all with this flag.

For single-command host bootstrap, a `scripts/install-binfmt.sh` would
suffice; alternatively a note in [README.md](../README.md).

### 4. Process supervision

Two long-running services, same container, independent lifecycles:

- `/opt/tidal/bin/tidal_connect_application` (armhf, via QEMU)
- `arecord ... | socat ...` (x86, native) — current forwarder shell
  pipeline

Use `supervisord` or `s6-overlay`:

- Each program in its own `[program:*]` block with
  `stdout_logfile=/dev/stdout`, `redirect_stderr=true` → unified
  `docker logs` stream, but each line prefixed with the program name.
- `autorestart=true` per program → vendor-binary crash restarts only
  the vendor-binary program, not the forwarder.
- Supervisord forwards `SIGTERM` to children on shutdown so the
  forwarder can still execute its `Stream.RemoveStream` cleanup
  (`forwarder.instructions.md` requirement).

### 5. Compose shape

Single service, `network_mode: host` preserved (mDNS requirement):

```yaml
services:
  tidal:
    image: tidal-combined:latest
    network_mode: host
    devices:
      - /dev/snd
    environment:
      - SNAPSERVER_HOST=...
      - STREAM_PORT=...
      # ... existing env vars from both current services
    restart: unless-stopped
```

The two Compose profiles currently used in [docker-compose.yml](../docker-compose.yml)
collapse to one.

## Trade-offs

### Wins

| | Current (two containers in ARM-emulated VM) | Proposed (one container on x86 host) |
|---|---|---|
| Full-system CPU emulation | Yes (entire VM) | **No** |
| User-mode emulation scope | Entire userland | **Vendor binary only** |
| ALSA / arecord / socat / Avahi | Emulated | **Native x86** |
| Kernel syscalls | Emulated (`qemu-system-aarch64`) | Native x86 syscall ABI |
| Expected idle CPU vs. baseline | ~1.4 % median (measured) | Likely sub-0.5 % (unmeasured) |
| Build matrix | `linux/arm/v7`, `linux/arm64` | `linux/amd64` only |
| `docker compose up` services | 2 | 1 |
| Compose profile count | 2 | 1 |

### Losses

| Concern | Mitigation |
|---|---|
| Image is x86-only; cannot run on real Pi as-is | If Pi hardware arrives, add a parallel `Dockerfile.pi` (pure armhf, no supervisord, no qemu, no vendored libs — essentially today's `tidal-connect/Dockerfile`). Shared entrypoint/forwarder shell code lives in one place and is `COPY`'d by both. Dual-image maintenance cost is low because the Pi variant is simpler. |
| Vendor-binary crash isolation | Supervisord's per-`[program:*]` `autorestart` provides the same restart semantics as `restart: unless-stopped` on a dedicated container. Lifecycle verified by supervisord's crash log, not Docker's event stream. |
| Logs no longer separable via `docker logs <container>` | Supervisord prefixes each stdout line with the program name (`[tidal-connect] ...`, `[forwarder] ...`). `docker logs tidal` → single multiplexed stream. Grep is sufficient. If deeper separation needed: emit to syslog or a sidecar fluentbit. |
| Entrypoint complexity rises | Replaced with supervisord config (declarative) instead of two separate `entrypoint.sh` files. Net complexity roughly equal; shared config file instead of two scripts. |
| CI build loses multi-arch cross-check | The multi-arch build existed partly to prove the vendor binary loads under both armhf and arm64 QEMU shims. In the proposed model, only amd64 is built; armhf behavior is implicitly tested every time `tidal_connect_application` runs under `qemu-arm-static` in the integration test. Build time halves. |
| Pi deploy drifts | Only matters if/when Pi becomes a real target. See §Future direction below. |

## Hard constraints retained

Per [AGENTS.md](../AGENTS.md) §2:

- ✅ Vendor binaries unmodified (lives in `/opt/tidal/bin/` from
  current `tidal-connect/src/bin/`).
- ✅ Vendor licenses retained (COPY into `/opt/tidal/licenses/`).
- ✅ `id_certificate/` retained.
- ✅ Library pins satisfied: the Debian 9 `.deb` extraction gives
  exact OpenSSL 1.0, FFmpeg 3, FLAC 8, libcurl 3 (OpenSSL 1.0-linked),
  portaudio, alsa-lib, avahi SONAMEs the binary needs. BASE-2 already
  proved this pattern works empirically (CI run
  [28534452841](https://github.com/moskakos/tidal-connect-docker/actions/runs/28534452841),
  real-world playback verified on tidal-dev 2026-07-02).
- ✅ `network_mode: host` retained (single service, same mDNS
  guarantees).
- ✅ No vendor-binary rewrite proposed.

Per [AGENTS.md](../AGENTS.md) §3 (soft):

- ⚠️ Shell logging helpers (`info` / `warning` / `error`) → still used
  for entrypoint pre-flight checks (binfmt detection, sysroot sanity).
  Supervisord replaces the long-running trap/wait loop.
- ⚠️ `SIGTERM`/`SIGINT` trap → delegated to supervisord's shutdown
  sequence, which forwards to children. Forwarder still gets the signal
  needed to run `Stream.RemoveStream`.
- ✅ Non-root user, `cap_drop`, `no-new-privileges`, read-only rootfs:
  all can be preserved in the new container (needs validation; mounting
  tmpfs for supervisord's socket path and for `/opt/tidal/sysroot/tmp`
  if required by the vendor binary).

## Open questions

Flagged for the implementation phase, not blockers for the idea:

1. **Supervisord vs. s6-overlay vs. tini + bash job control** — which
   fits best. Supervisord is the obvious pick but adds a Python
   runtime; s6-overlay is leaner but less familiar; `tini + bash &`
   is possible but fragile around signal propagation.
2. **Read-only rootfs feasibility** — supervisord wants a writable
   socket and PID file; a tmpfs mount for `/var/run/supervisor` likely
   covers it. Needs testing.
3. **Vendor binary writable paths** — does `tidal_connect_application`
   need to write anywhere besides `/opt/tidal/id_certificate/`? Check
   `strace -e trace=file` under current ARM VM run. If more paths
   needed, additional tmpfs mounts.
4. **`QEMU_LD_PREFIX` + sysroot layout** — does the vendor binary
   `dlopen()` any library at runtime by basename-only? If yes, sysroot
   must mirror `/usr/lib/arm-linux-gnueabihf/` exactly, not just
   `/lib/`. Easy to handle; just worth confirming.
5. **Does `tonistiigi/binfmt` persistence survive VM reboots?** On
   Debian hosts it persists via systemd unit. Document in README.
6. **GHCR tag naming for the new image** — if we keep BASE-2's
   `tidal-connect:base2-candidate` convention or introduce a new
   `tidal-combined:x86-emu` tag. Separate from this proposal; decide
   when CI starts pushing.

## Future direction: Pi support, if ever

A hypothetical spin-off repo starts x86-only by design. If an
ARM-native deployment ever becomes relevant to that project, the
cleanest options at that point are:

- Keep the spin-off x86-only and continue using **this** repo
  (`tidal-connect-docker`) for ARM-native hardware. The two projects
  cover different deployment shapes.
- Or, in the spin-off repo, add a parallel `Dockerfile.pi` (armhf
  base, no supervisord, no qemu, no vendored libs — essentially this
  repo's current `tidal-connect/` + `forwarder-arecord/` Dockerfiles
  merged by nothing beyond compose). Shared assets live in a
  `shared/` directory, `COPY`'d into both.

Not a decision for today. Flagged only to show Pi is not permanently
excluded from the eventual spin-off either.

## Status and next steps

- **Current status:** 🔴 idea captured, no spin-off repo exists.
  **This repo (`tidal-connect-docker`) will not implement the idea** —
  it stays platform-agnostic.
- **When pursued:** create a new repo (name TBD, e.g.
  `tidal-connect-x86`), seed it with a copy of this document, and
  start from the BASE-2 Dockerfile template adapted to amd64 base.
- **Prerequisite reads at that point:**
  - This document in full.
  - [AGENTS.md](../AGENTS.md) §2 of **this** repo (library matrix) —
    carries over verbatim to the spin-off.
  - [tidal-connect/Dockerfile.debian11-vendored](../tidal-connect/Dockerfile.debian11-vendored)
    (vendoring template to adapt from armhf base to amd64 base).
  - [forwarder-arecord/entrypoint.sh](../forwarder-arecord/entrypoint.sh)
    (forwarder logic to inline).
  - [docs/performance-baseline.md](performance-baseline.md) (what to
    beat).
- **First concrete milestone in the spin-off repo (when scheduled):**
  proof-of-concept Dockerfile that builds amd64 image, bundles Debian 9
  armhf libs, runs vendor binary via `qemu-arm-static` with `ldd`
  showing no `not found`, 60-second runtime smoke test. Equivalent of
  BASE-2 in CI, but on amd64.
- **Decision gate in the spin-off repo:** real-world smoke test on an
  x86 Docker host — TIDAL phone app discovers device and plays audio
  via Snapcast.

Tracking row: `MISC-4` in [TODO.md](../TODO.md) (lives here as a
"remember this exists" hook — not as a task scheduled against this
repo).
