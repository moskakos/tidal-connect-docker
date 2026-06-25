# AGENTS.md — Repository conventions for AI coding agents

This document encodes constraints, conventions, and decisions for any AI agent
working on this repository. **Read this first** before making changes.

## 1. Project context

This repo packages **TIDAL Connect** for Snapcast multi-room audio on ARM
Linux. It contains:

- `tidal-connect/` — Dockerfile + entrypoint that runs a closed-source iFi
  Audio binary (`tidal_connect_application`) on Raspbian/Debian 9.
- `ffmpeg/` — entrypoint script that runs in `linuxserver/ffmpeg`, reads from
  an ALSA loopback device, registers a stream with Snapserver via JSON-RPC,
  and forwards audio over TCP.
- `docker-compose.yml` — wires the two services together with `network_mode:
  host`.

## 2. Hard constraints (do not violate)

- **Do not modify `tidal-connect/src/bin/`**. These are vendor binaries
  (`tidal_connect_application`, `speaker_controller_application`). They are
  ARM-only (`armhf`) and require an older runtime than current Debian
  provides.
- **Do not modify files under `tidal-connect/src/licenses/`**. Vendor
  licenses; keep verbatim.
- **Do not delete `tidal-connect/src/id_certificate/`** without an explicit
  user request. Required by the binary at runtime.
- **Library pins are intentional**: the binary requires `libssl.so.1.0.0` and
  `libcurl.so.4` from Debian 8/9. Any base-image change must continue to
  satisfy these via snapshot.debian.org packages or equivalent.
- **`network_mode: host` is required** in `docker-compose.yml` for mDNS /
  Avahi discovery by the TIDAL app. Removing it breaks discoverability.
- **The TIDAL Connect protocol has no FOSS replacement.** Do not propose
  rewriting the binary away.

## 3. Soft conventions

### Shell scripting
- All entrypoints use the `info` / `warning` / `error` logging helpers
  defined inline. New scripts must use the same shape (timestamped log
  lines, `error` exits with code 1 after `sleep 2`).
- Always trap `SIGTERM SIGINT` for cleanup. Prefer adding `EXIT` to the trap
  as well so cleanup runs on normal exit too.
- `set -e` is intentional in `tidal-connect/entrypoint.sh`; keep it.

### Docker / Compose
- Pin third-party images by digest where feasible (`@sha256:...`), not just
  tag.
- Multi-arch builds use `docker buildx`. Target platforms: `linux/arm/v7`
  and `linux/arm64`.
- New environment variables must have defaults inside the entrypoint and be
  documented in [README.md](README.md)'s configuration table.
- Do not introduce a new top-level `README*.md` file. Edit
  [README.md](README.md) in place. The existing `README-new.md` /
  `README-old.md` will be cleaned up separately.

### Files and structure
- New helper code goes under a dedicated subdirectory at repo root (e.g.
  `forwarder-arecord/`), not mixed into existing service directories.
- `.dockerignore` should be respected and kept tight — vendor license trees
  should not bloat container images.

## 4. Git workflow

- **Base branch for development: `dev`** (not `master`).
- Feature branches: `feat/<short-name>`, branched from `dev`, merged back
  into `dev` via PR (or fast-forward if trivial).
- The user merges `dev` → `master` manually when they choose.
- Do not push to `master` directly. Do not force-push to `dev` or `master`.
- Commit messages: imperative mood, scoped prefix when helpful
  (`forwarder:`, `tidal-connect:`, `ci:`, `docs:`).

## 5. Testing tiers

| Tier | Where | What |
|------|-------|------|
| Static | GitHub Actions | hadolint, shellcheck, yamllint, `docker compose config` |
| Build | GitHub Actions | `docker buildx` multi-arch, Trivy scan, smoke test (container starts, binary stays alive 30 s) |
| Synthetic E2E | GitHub Actions | `modprobe snd-aloop`, mock Snapserver TCP listener, validate byte flow + JSON-RPC calls |
| Performance | Self-hosted runner in Proxmox VM | Idle CPU under ARM emulation; only this environment reproduces the user's hardware |
| Manual smoke | User's phone | Real TIDAL app discovers device and plays audio; release-gate only |

Performance baselines live in `docs/performance-baseline.md` (to be created).
Always measure before/after on the same host when proposing CPU
optimizations.

## 6. Agent / model selection policy

Use the cheapest model that can do the job. Reserve top-tier models for work
that genuinely requires deep reasoning, cross-file refactors, or
debugging-by-inspection. Tiering guidance:

| Tier | Use for | Examples (subject to availability) |
|------|---------|------------------------------------|
| **High** (premium reasoning) | Base-image modernization, ALSA / ffmpeg / Snapcast pipeline redesign, library compatibility debugging, complex multi-step refactors | Claude Sonnet 4.5, GPT-5, top-tier reasoning models |
| **Mid** (balanced) | Security hardening (well-known patterns), Dockerfile review, shell-script refactors | GPT-5 mini, Claude Haiku (4.x), Gemini 2.5 Pro |
| **Low** (fast / cheap) | CI YAML scaffolding, lint-rule fixes, doc edits, file-name search, README cleanup | GPT-5 nano, Gemini Flash, similar small models |
| **Explore subagent** | Read-only codebase Q&A, file location, pattern search | Fast/cheap tier; never high tier |

Rules:
- Specify the model in `.agent.md` frontmatter when the choice is not the
  workspace default.
- Never run the highest-tier model on a task that fits the low tier
  (lint/YAML/docs).
- When in doubt, start with the mid tier and escalate only if the model
  visibly struggles.

## 7. Planned agent inventory

Each agent gets its own file under `.github/agents/<name>.agent.md` when
created. Current plan (not yet implemented):

| Agent | Tier | Scope |
|-------|------|-------|
| `base-image-modernizer` | High | Try Debian 11 / 12 / distroless; diagnose binary load failures via `ldd` / `strace`; keep ARM constraints intact. |
| `security-hardener` | Mid | Non-root user, `cap_drop`, `no-new-privileges`, digest pinning, supply-chain hygiene. |
| `audio-pipeline-optimizer` | High | Replace ffmpeg with `arecord`+`socat` or Snapcast native sources; measure idle CPU before/after. Must not touch the TIDAL binary container. |
| `ci-and-quality` | Low | GitHub Actions, `.dockerignore`, healthchecks, multi-arch buildx, README consolidation. |

Spawn at most one of these at a time; they share Dockerfile / Compose
surface and conflict easily.

## 8. Known issues to keep in mind

- Idle CPU under x86-host + ARM-emulated Proxmox VM: ~33 % per 2 vCPU. The
  audio-pipeline-optimizer's primary target.
- FLAC encoding in ffmpeg has caused audio dropouts → PCM is the safe
  default.
- `tidal_connect_application` accepts at most TIDAL *High* quality
  (16-bit/44.1 kHz), not *Max*.
- `TC_DISABLE_APP_SEC=false` is documented as not working; do not assume it
  does.

## 9. When in doubt

Open a discussion with the user before:
- Touching any vendor file under `tidal-connect/src/`.
- Removing `network_mode: host`.
- Changing the base image away from Debian-family.
- Adding new top-level documents.
- Pushing to remote branches other than the one currently in use.
