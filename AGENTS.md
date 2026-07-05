# AGENTS.md — Repository conventions for AI coding agents

This document encodes constraints, conventions, and decisions for any AI agent
working on this repository. **Read this first** before making changes.

## 1. Project context

This repo packages **TIDAL Connect** for Snapcast multi-room audio on ARM
Linux. It contains:

- `tidal-connect/` — Dockerfile + entrypoint that runs a closed-source iFi
  Audio binary (`tidal_connect_application`) on Raspbian/Debian 9.
- `forwarder-arecord/` — minimal `arecord`+`socat` audio forwarder that reads
  from the ALSA loopback device, registers a stream with Snapserver via
  JSON-RPC, and forwards raw PCM over TCP. Sole forwarder since the old
  ffmpeg-based one was removed.
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
- **Library pins are intentional.** Verified by `ldd` against
  `tidal_connect_application` in CI (originally run 28186328355, both
  `linux/arm/v7` and `linux/arm64` jobs). As of 2026-07-01 the
  `linux/arm/v7` matrix entry is dropped — the vendor binary is
  armhf-only and `raspbian/stretch` is an armhf-only image on Docker
  Hub, so the arm/v7 build produced identical content to the arm64
  build (both are the armhf image, tagged differently by buildx). The
  arm64 job exercises the deployment target directly: modern Raspberry
  Pi hardware (Pi 3B and later, all 64-bit-capable — Pi 3/3B+/3A+/CM3/
  Zero 2 W/4B/CM4/400/5/500) running 64-bit Raspberry Pi OS + kernel
  binfmt_misc + qemu-user-static, which is exactly what CI's arm64-host
  QEMU shim reproduces. Older armv7-only Pi hardware (Pi 2, Pi 1, Pi
  Zero v1) is not a realistic TIDAL Connect target (insufficient CPU).
  The binary loads these SONAMEs from Debian 9 packages — any
  base-image change must keep them satisfied:
  - **OpenSSL 1.0:** `libssl.so.1.0.0`, `libcrypto.so.1.0.0`
    (Debian 8/9 only; Debian 10+ ships 1.1, Debian 12 ships 3.0 — neither
    is binary-compatible; symbol versions `OPENSSL_1.0.0` / `OPENSSL_1.0.1`
    are absent from 1.1/3.0)
  - **curl:** `libcurl.so.4` SONAME is stable across Debian 8–12, but
    the binary needs the symbol version `CURL_OPENSSL_3` — emitted only
    by libcurl builds linked against OpenSSL 1.0 (Debian 8/9). Debian
    10+ libcurl emits `CURL_OPENSSL_4`; not interchangeable. See
    [docs/troubleshooting.md](docs/troubleshooting.md#base-1-debian-12--soname-symlinks-does-not-satisfy-the-vendor-binary-refuted).
  - **FFmpeg 3.x:** `libavformat.so.57`, `libavcodec.so.57`,
    `libavutil.so.55`, `libswresample.so.2` (Debian 9 only; Debian 10
    ships FFmpeg 4 → `.58` SONAMEs, **not in Debian 10+ repos at all**;
    symbol versions `LIBAV*_5{5,7}` / `LIBSWRESAMPLE_2` are not
    backported)
  - **FLAC:** `libFLAC.so.8`, `libFLAC++.so.6` (Debian 9 only; Debian 11+
    ships `.12`)
  - **Audio/mDNS:** `libportaudio.so.2`, `libasound.so.2`,
    `libavahi-client.so.3`, `libavahi-common.so.3` (compatible across
    Debian 8–12)
  Practical implication: moving past Debian 9 requires shipping
  Debian-9 `.deb` files for OpenSSL 1.0, libcurl3, FFmpeg 3 and FLAC 8
  inside a newer base (BASE-2 approach (a)). SONAME aliasing alone is
  insufficient — refuted empirically by BASE-1 (CI run
  [28461155940](https://github.com/moskakos/tidal-connect-docker/actions/runs/28461155940),
  documented in [docs/troubleshooting.md](docs/troubleshooting.md#base-1-debian-12--soname-symlinks-does-not-satisfy-the-vendor-binary-refuted)).
  A working Debian-11 candidate exists at
  [`tidal-connect/Dockerfile.debian11-vendored`](tidal-connect/Dockerfile.debian11-vendored)
  on branch `feat/base-2-debian11-vendored` (CI validation run
  [28534452841](https://github.com/moskakos/tidal-connect-docker/actions/runs/28534452841),
  documented in [docs/troubleshooting.md](docs/troubleshooting.md#base-2-debian-11--vendored-debian-9-libs-validated)).
  Production cutover is a separate human decision that requires a real
  Raspberry Pi + TIDAL-phone-app smoke test outside CI's reach.
- **`network_mode: host` is required** in `docker-compose.yml` for mDNS /
  Avahi discovery by the TIDAL app. The binary links against
  `libavahi-client.so.3` (verified by `ldd`); removing host networking
  breaks discoverability.
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
  [README.md](README.md) in place.

### Files and structure
- New helper code goes under a dedicated subdirectory at repo root (e.g.
  `forwarder-arecord/`), not mixed into existing service directories.
- `.dockerignore` should be respected and kept tight — vendor license trees
  should not bloat container images.

### Backlog tracking
- [TODO.md](TODO.md) is the consolidated status dashboard for project +
  agent work. Status legend: 🔴 not started · 🟡 in progress · ✅ done.
- **Agents do not edit [TODO.md](TODO.md).** They update only their own
  `.github/agents/<name>.agent.md` "Concrete next tasks" section when
  proposing or refining work. The assistant ("Jalmari") reconciles those
  changes into [TODO.md](TODO.md) on user request or after a completed
  task. This avoids merge conflicts and keeps the dashboard curated.
- Task rows in [TODO.md](TODO.md) keep their line position once added;
  only the status emoji, priority marker, and trailing commit SHA change.
  New tasks are appended to the bottom of their agent section. IDs are
  not reused.
- At most **one 🟡** row in [TODO.md](TODO.md) at a time across all
  agents — that's the focus discipline.

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
| Synthetic E2E | GitHub Actions | Mock Snapserver TCP listener, validate JSON-RPC `AddStream`/`RemoveStream` + entrypoint EXIT trap. Full byte-flow (`arecord → socat`) requires `snd-aloop` and is currently deferred to a self-hosted runner (MISC-1). |
| Performance | Self-hosted runner in Proxmox VM (`tidal-dev`) | Idle CPU under ARM emulation; only this environment reproduces the user's hardware |
| Manual smoke | User's phone | Real TIDAL app discovers device and plays audio; release-gate only |

Performance baselines live in `docs/performance-baseline.md`. Always
measure before/after on the same host when proposing CPU optimizations.

The self-hosted runner service (`actions.runner.moskakos-tidal-connect-docker.tidal-dev.service`)
is **disabled at boot** and controlled on demand — agents SSH'ing to
`tidal-dev` as `moska` have a scoped `sudoers.d` rule allowing
`systemctl start|stop|restart|status|is-active|show` without a password.
See [/memories/repo/tidal-dev-runner.md](/memories/repo/tidal-dev-runner.md)
for the full workflow, security posture, and the required fork-PR guard
that every self-hosted job MUST carry.

## 6. Agent / model selection policy

Use the cheapest model that can do the job. Reserve top-tier models for work
that genuinely requires deep reasoning, cross-file refactors, or
debugging-by-inspection. Tiering guidance:

| Tier | Use for | Examples (subject to availability) |
|------|---------|------------------------------------|
| **High** (premium reasoning) | Base-image modernization, ALSA / forwarder / Snapcast pipeline redesign, library compatibility debugging, complex multi-step refactors | Claude Sonnet 4.5, GPT-5, top-tier reasoning models |
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
| `audio-pipeline-optimizer` | High | Maintain and tune the `arecord`+`socat` forwarder (idle CPU, ALSA quirks, Snapserver JSON-RPC lifecycle). Must not touch the TIDAL binary container. |
| `ci-and-quality` | Low | GitHub Actions, `.dockerignore`, healthchecks, multi-arch buildx, README consolidation. |

Spawn at most one of these at a time; they share Dockerfile / Compose
surface and conflict easily.

## 8. Known issues to keep in mind

- Idle CPU under x86-host + ARM-emulated Proxmox VM: ~1.4 % (median) with
  the `arecord`+`socat` forwarder. Historical `ffmpeg` forwarder measured
  ~21.6 % on the same host — the ~15× gap was the reason for the switch
  and, ultimately, the removal of the ffmpeg forwarder. See
  [docs/performance-baseline.md](docs/performance-baseline.md).
- `tidal_connect_application` accepts at most TIDAL *High* quality
  (16-bit/44.1 kHz), not *Max*.
- `TC_DISABLE_APP_SEC=false` is documented as not working; do not assume it
  does.
- Snapserver `Stream.AddStream` `bind: Address already in use` after
  forwarder restart: reproduced on Snapserver v0.29.0, **fixed in
  v0.35.0** (verified 2026-06-27 with active snapclient). Workarounds
  (change `STREAM_PORT`, restart Snapserver LXC) and the hypothesis are
  kept in [docs/troubleshooting.md](docs/troubleshooting.md) as
  historical reference for older Snapserver builds.

## 9. When in doubt

Open a discussion with the user before:
- Touching any vendor file under `tidal-connect/src/`.
- Removing `network_mode: host`.
- Changing the base image away from Debian-family.
- Adding new top-level documents.
- Pushing to remote branches other than the one currently in use.

## 10. Available MCP servers and tool preferences

**Tool selection priority** (always try in this order; only fall back
when the higher option truly cannot do the job):

1. **Built-in workspace tools** — `read_file`, `grep_search`,
   `file_search`, `semantic_search`, `replace_string_in_file`,
   `multi_replace_string_in_file`, `manage_todo_list`, memory
   operations, etc. These have zero approval friction, return typed
   results, and are optimised for the VS Code chat/agent surfaces.
2. **MCP-server tools** (see table below) — `mcp_mcp-jq_*`,
   `mcp_github_mcp_s2_*`, `mcp_github_mcp_se_*`. Also zero approval
   friction; use them for anything that fits their scope.
3. **Terminal commands** (`run_in_terminal`) — **last resort.** Every
   invocation prompts the user for approval. Reserve for actions the
   above tools cannot express (git operations, shell pipelines,
   invoking `docker`/`yamllint`/`hadolint`/`ssh`, one-off diagnostics).
   When multiple shell steps are unavoidable, batch them into a single
   pipeline so one approval covers the whole flow.

Common substitutions to keep in mind:

| Instead of terminal…    | Prefer the built-in                                          |
|-------------------------|--------------------------------------------------------------|
| `grep -rn 'pattern'`      | `grep_search` (regex, workspace-scoped, no approval)         |
| `cat` / `sed -n Np`       | `read_file` with `startLine` / `endLine`                     |
| `wc -l file`              | `read_file` — you usually want the content, not just a count |
| `find . -name '*.md'`     | `file_search` with a glob                                    |
| `ls dir/`                 | `list_dir`                                                   |
| Running `jq` in a pipe    | `mcp_mcp-jq_jq_query_file` (workspace-scope MCP)             |
| Polling GitHub REST APIs  | `mcp_github_mcp_s2_*` / `mcp_github_mcp_se_*`                |

### 10.1 MCP servers configured in this workspace

The following MCP servers back the "prefer MCP" rule above. MCP calls
return typed results directly.

| MCP server | Scope        | Configured in                          | Prefer over                                                         |
|------------|--------------|-----------------------------------------|---------------------------------------------------------------------|
| `jq`             | workspace | [.vscode/mcp.json](.vscode/mcp.json)                                       | shell `jq` piped through the terminal (each `jq` call needs approval) |
| `github`         | user      | `~/Library/Application Support/Code/User/mcp.json`                         | `gh` CLI (not installed) or `curl` to `api.githubcopilot.com`         |
| `github-actions` | user      | `~/Library/Application Support/Code/User/mcp.json`                         | `curl` to Actions API, `gh run …`                                     |

Terminal fallback is fine when the MCP tool is unavailable (e.g. inside
a subagent that lacks the server in its `tools:` allowlist — see §10.2)
or when a one-off shell pipeline is genuinely simpler than three MCP
round-trips.

### 10.2 Subagent MCP inheritance

Subagents do **NOT** inherit workspace- or user-scope MCP servers by
default. Verified empirically 2026-06-30: an `Explore` subagent reported
both `mcp_mcp-jq_*` and `mcp_github_mcp_s2_*` as *"currently disabled"*
even though the main thread has them.

To grant a subagent access, add the relevant MCP server glob(s) to the
agent's frontmatter `tools:` list. Per-agent guidance in this repo:

| Agent                       | `tools:` includes                                                    |
|-----------------------------|----------------------------------------------------------------------|
| `base-image-modernizer`     | `read, edit, search, execute, jq/*, github/*, github-actions/*`      |
| `ci-and-quality`            | `read, edit, search, execute, jq/*, github/*, github-actions/*`      |
| `audio-pipeline-optimizer`  | `read, edit, search, execute, jq/*, github-actions/*`                |
| `security-hardener`         | `read, edit, search, execute, jq/*, github-actions/*`                |

If a subagent still needs to parse JSON without MCP-jq (e.g. because
an MCP call failed), fall back to terminal `jq` — it works, it just
requires user approval per call. Alternative: write the JSON slice to
disk and let the main thread parse it back on the next turn.

Workspace toolset [`.github/prompts/tidal-connect-docker.toolsets.jsonc`](.github/prompts/tidal-connect-docker.toolsets.jsonc)
aggregates these globs for main-thread convenience; toolsets do not
propagate to subagents.


