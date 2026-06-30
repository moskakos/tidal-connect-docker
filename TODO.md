# TODO

> Project + agent backlog rollup. Glance-view of where the work stands.
>
> **Source of truth for scope & constraints:** the per-agent files under
> [.github/agents/](.github/agents/) (`*.agent.md`, section "Concrete next
> tasks"). This file is the consolidated status dashboard.
>
> **Status legend:** 🔴 not started · 🟡 in progress · ✅ done
>
> **Priority:** `P1` next up · `P2` scheduled · `P3` nice-to-have ·
> empty = unscheduled / exploratory. Priority is shown in its own column,
> independent of row order.
>
> **Update policy**
> - Maintained by the assistant ("Jalmari") after every task completion,
>   on user request, or when CI changes the picture.
> - Agents do **not** edit this file. They update only their own
>   `.github/agents/<name>.agent.md` "Concrete next tasks" section.
>   Jalmari reconciles those changes into this file.
> - Task rows keep their line position once added. Only the **Status**,
>   **Pri**, and **Commit** cells change. New tasks are **appended** to
>   the bottom of their agent's table. IDs are never reused.
> - At most **one 🟡** row in the entire file at a time. If you start work
>   without flipping a row to 🟡, you're freelancing.
> - `Active` block below mirrors the current 🟡 row for fast scanning.
>
> Last refresh: 2026-06-30 (AUDIO-5 done, 551fe27).

## Active

_(no active task — pick a `P1` row below and flip its Status to 🟡)_

## ci-and-quality

| Status | Pri | ID   | Description                                                              | Commit  |
|--------|-----|------|--------------------------------------------------------------------------|---------|
| ✅     |     | CI-1 | README consolidation                                                     | b5ca9e5 |
| ✅     |     | CI-2 | yamllint step in lint job                                                | b911521 |
| ✅     |     | CI-3 | `.dockerignore` review for both build contexts                           | 6e373d1 |
| ✅     |     | CI-4 | Pin third-party images by digest                                         | 4e6b8ed |
| ✅     |     | CI-5 | Healthcheck for `tidal-forwarder-arecord` (`pgrep -x arecord`)           | ee84a35 |
| ✅     |     | CI-6 | Trivy scan job + `.trivyignore`                                          | 7586ff7 |
| ✅     |     | CI-7 | Smoke test job (Tier 2.5; build + JSON-RPC + cleanup)                    | 7ba5871 |
| ✅     |     | CI-8 | Trivy hard-gate (`exit-code: 1`) once `.trivyignore` is justified        | 8295863 |

## security-hardener

| Status | Pri | ID    | Description                                                             | Commit                |
|--------|-----|-------|-------------------------------------------------------------------------|-----------------------|
| ✅     |     | SEC-1 | `no-new-privileges` on all services                                     | 58cdf02               |
| ✅     |     | SEC-2 | Drop all Linux capabilities from forwarder services                     | f87f991               |
| ✅     |     | SEC-3 | `forwarder-arecord` runs as non-root (uid 1001, gid 29)                 | 9ec8caa               |
| ✅     |     | SEC-4 | Pin third-party images by digest                                        | 4e6b8ed (shared CI-4) |
| ✅     |     | SEC-5 | `forwarder-arecord` read-only rootfs + tmpfs `/tmp`                     | b6ffed6               |
| ✅     |     | SEC-6 | Document security posture ([docs/security.md](docs/security.md))        | 127099a               |
| ✅     |     | SEC-7 | `.trivyignore` allowlist review (per-block justification in header)     | 7586ff7               |

## base-image-modernizer

| Status | Pri | ID     | Description                                                                                                                            | Commit |
|--------|-----|--------|----------------------------------------------------------------------------------------------------------------------------------------|--------|
| 🔴     | P3  | BASE-1 | Approach (c) quick refute: Debian 12 + SONAME symlinks; document negative result in [docs/troubleshooting.md](docs/troubleshooting.md) | —      |
| 🔴     | P3  | BASE-2 | Approach (a): Debian 11 + vendored Debian-9 `.deb`s (OpenSSL 1.0, FFmpeg 3, FLAC 8) under `/opt/legacy-libs`; both arches              | —      |

## audio-pipeline-optimizer

| Status | Pri | ID      | Description                                                                                                                    | Commit  |
|--------|-----|---------|--------------------------------------------------------------------------------------------------------------------------------|---------|
| ✅     |     | AUDIO-1 | `forwarder-arecord` prototype gated by Compose profile                                                                         | ec7f4cb |
| ✅     |     | AUDIO-2 | Idle-CPU baseline doc (aarch64 emulated)                                                                                       | 96f8f45 |
| ✅     |     | AUDIO-3 | Expose `PERIOD_TIME` / `BUFFER_TIME` env tunables                                                                              | e9ebf47 |
| ✅     |     | AUDIO-4 | AddStream retry with backoff (Snapserver TIME_WAIT)                                                                            | 720a7a3 |
| ✅     |     | AUDIO-5 | Re-measure idle CPU after SEC-2 / SEC-3 / SEC-5 hardening; update [docs/performance-baseline.md](docs/performance-baseline.md) | 551fe27 |

## Cross-cutting

| Status | Pri | ID     | Description                                                                                                                                                                                                            | Commit |
|--------|-----|--------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|--------|
| 🔴     | P3  | MISC-1 | Full Tier-3 byte-flow smoke (`arecord → socat`) on self-hosted Proxmox runner with generic-kernel `snd-aloop`. Background: [/memories/repo/github-runner-no-snd-aloop.md](/memories/repo/github-runner-no-snd-aloop.md) | —      |
