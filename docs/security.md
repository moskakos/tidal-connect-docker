# Security posture

Reference for operators and reviewers of the security-relevant decisions
in this repository. Last refresh: 2026-06-30.

This document is descriptive — it records what the code already does. For
the underlying constraints that justify several of these decisions (vendor
binary, library pins, ARM-only, Debian-9 lock) see [AGENTS.md](../AGENTS.md)
section 2.

## 1. Scope and threat model

This stack streams audio from a closed-source [TIDAL Connect][tc] vendor
binary (iFi Audio's `tidal_connect_application`) to a Snapcast server on a
home LAN. The intended deployment is:

- A trusted home/office LAN.
- ARM hardware (Raspberry Pi class, armv7 or arm64) or an ARM-emulated VM.
- The operator controls the host firewall and does not expose any
  forwarder/Snapcast ports to the public internet.

Out of scope:

- Hardening the closed-source vendor binary itself (we cannot inspect or
  rebuild it).
- Production / multi-tenant deployments.
- Internet-exposed installations.

The most sensitive asset is `tidal-connect/src/id_certificate/`, an
opaque vendor-issued identity that authenticates the device to the TIDAL
backend. Leakage would let a third party impersonate this device. The
audio data itself is non-sensitive and is already on the operator's LAN.

[tc]: https://tidal.com/

## 2. Per-service hardening

All three services declare `security_opt: ["no-new-privileges:true"]` in
[docker-compose.yml](../docker-compose.yml). Service-specific notes:

### 2.1 `tidal-connect` (vendor binary)

- **Runs as root.** The vendor binary requires it; no
  workaround without breaking the binary. See AGENTS.md section 2.
- **Debian 9 (stretch) base.** Forced by the binary's library pins
  (OpenSSL 1.0.0, FFmpeg 3.x, FLAC 8, etc., verified by `ldd` in CI).
- **`network_mode: host`.** Required for the binary's mDNS / Avahi
  discovery so the TIDAL app can find the device. See section 3 below.
- **Capabilities not dropped.** The vendor entrypoint exec's Avahi, which
  expects the default Linux capability set. Dropping capabilities here
  has been observed to break discovery; not changed.

### 2.2 `tidal-forwarder-arecord` (Alpine 3.20, sole forwarder)

The most-hardened service and the only forwarder shipped since the
ffmpeg-based `tidal-forwarder` was removed:

- **Non-root user** (`uid=1001`, `gid=29`). The `audio-host` group at
  GID 29 matches the Debian host's `audio` group so the bind-mounted
  `/dev/snd` device nodes (group=29) stay readable. See
  [`forwarder-arecord/Dockerfile`](../forwarder-arecord/Dockerfile)
  lines 16-21.
- **`cap_drop: [ALL]`** — runs with no Linux capabilities.
- **`no-new-privileges:true`** — set-uid binaries cannot elevate.
- **`read_only: true`** — root filesystem is mounted read-only.
- **`tmpfs: /tmp` with `nosuid,nodev,noexec,size=16m`** — only writable
  area, with execution disabled.
- **`HEALTHCHECK CMD pgrep -x arecord`** — Docker restarts the container
  if the capture pipeline dies. Probe uses busybox `pgrep` so no extra
  package is needed.

## 3. Network exposure

`network_mode: host` is intentional on all three services and **cannot**
be replaced with a bridge network without breaking TIDAL Connect
discovery (the vendor binary links against `libavahi-client.so.3`, see
AGENTS.md section 2). Consequences:

- Containers share the host's network namespace; container-level
  port-mapping rules do not apply.
- Operators **must** rely on the host firewall to keep these ports off
  the public internet:
  - Snapserver control: TCP 1780 (HTTP), TCP 1705 (Snapcast control).
  - Forwarder stream feed to Snapserver: TCP 5000 (default
    `STREAM_PORT`).
  - mDNS / Avahi: UDP 5353.
- Trust boundary = LAN edge. Anything reachable on the LAN can talk to
  these ports.

## 4. Supply chain

| Control | Where | What it catches |
|--|--|--|
| Multi-arch buildx (`linux/arm/v7` + `linux/arm64`) | [`.github/workflows/ci.yml`](../.github/workflows/ci.yml) `build-and-ldd` matrix | Build regressions on either ARM variant. |
| Base image digest pinning (`@sha256:...`) | [`forwarder-arecord/Dockerfile`](../forwarder-arecord/Dockerfile) | Image-tag squatting, base-image tampering. |
| `ldd` verification on every CI build | `build-and-ldd` job | Silent base-image drift that would break the vendor binary's library closure. |
| Trivy `image` scan (HIGH,CRITICAL) | `build-and-ldd` and `smoke-arecord` jobs | Known-CVE packages in either image. |
| Trivy hard-gate (`exit-code: 1`) | Same | A new fixable HIGH/CRITICAL not already justified blocks the build. |
| `.trivyignore` with per-block justification | [`.trivyignore`](../.trivyignore) | Allowlist drift; each block names root cause + revisit conditions. |
| Smoke test against mock Snapserver | `smoke-arecord` job | Forwarder JSON-RPC + lifecycle regressions. |

### 4.1 `.trivyignore` baseline

The allowlist currently contains 31 HIGH/CRITICAL CVEs spanning
`libcurl3`, `libldap-2.4-2`, and `libssl1.0.0` in the `tidal-connect`
image. They are **not fixable in our context**: the vendor binary
requires the exact Debian-8 backport symbol versions and Trivy's
"Fixed Version" column points at OpenSSL 1.1.x packages whose SONAMEs
the binary cannot load. See the [`.trivyignore`](../.trivyignore)
header for the full per-block rationale (root cause, why Trivy's
fix suggestion does not apply, compensating controls, revisit
conditions, originating CI run).

The `tidal-forwarder-arecord` image (Alpine 3.20) currently reports
**zero** HIGH/CRITICAL findings and has no allowlist entries.

## 5. Vendor-binary residual risk

The `tidal_connect_application` binary is the irreducible risk source:

- **Closed-source ARM binary** — cannot be inspected, rebuilt, or
  re-linked. We accept whatever it does at runtime.
- **Requires Debian 9 SONAMEs** — `libssl.so.1.0.0`, `libcrypto.so.1.0.0`,
  `libcurl.so.4`, `libavformat.so.57`, `libFLAC.so.8`, etc. See AGENTS.md
  section 2 for the full inventory verified by `ldd` in CI. Moving past
  Debian 9 requires shipping Debian-9 `.deb`s inside a newer base
  (open work: `base-image-modernizer` agent).
- **Holds vendor identity certificate** (`tidal-connect/src/id_certificate/`).
- **Runs as root** in its container. The container is single-purpose
  and not bridged into the host (apart from `/dev/snd` and `/dev/shm`),
  but a vendor-binary RCE could still compromise the host network
  namespace (because of `network_mode: host`).

**Compensating controls in this stack:**

- LAN-only deployment (section 1 + section 3).
- Container has no writable bind mounts that escape its lifetime; the
  certificate directory is read-only inside the image.
- Egress is implicit: the binary talks HTTPS to `api.tidal.com`,
  controlled by the binary itself. Operators who want defense in depth
  can run an outbound firewall on the host limiting destinations.
- ldd verification at every CI build ensures the runtime library set
  has not silently drifted.

## 6. Known unmitigated items

Recorded here so they are not forgotten. None of these are scheduled
P1 right now; promote in [TODO.md](../TODO.md) if priorities change.

- **31 allowlisted HIGH/CRITICAL CVEs** in the `tidal-connect` image
  (section 4.1). Mitigatable only by moving the binary off Debian-9
  symbol pins, which requires a successful run of the
  `base-image-modernizer` agent (TODO rows `BASE-1`, `BASE-2`).
- **`tidal-connect` runs as root.** Imposed by the vendor binary. Same
  fix path as above.
- **No image signing / provenance attestations** yet (Cosign / SLSA
  in-toto). Worth adding once the base-image modernization stabilises.
- **No SBOM emission.** Trivy can produce CycloneDX or SPDX SBOMs; not
  enabled today.
- **No outbound egress restriction at the container level.** Relies on
  operator's host firewall.

## 7. Operator checklist

Before exposing this stack on a network:

- [ ] Host firewall blocks inbound from outside the LAN to ports
      `1705/tcp`, `1780/tcp`, `5000/tcp`, `5353/udp`.
- [ ] No port forwards from the home router to the host running these
      containers.
- [ ] Snapserver is **v0.35.0 or newer** (see AGENTS.md section 8 known
      issues — older versions reproduced `Address already in use` on
      forwarder restart).
- [ ] Confirm the host `audio` group is GID 29 (Debian default). If
      not, the bind-mounted `/dev/snd` nodes will not be readable by
      `uid 1001 / gid 29` inside the arecord forwarder.

## 8. Re-verification

- **Continuous:** every push to `dev` re-runs the full CI matrix
  ([`.github/workflows/ci.yml`](../.github/workflows/ci.yml)) — lint,
  multi-arch build + ldd, Trivy hard-gate, smoke test.
- **Periodic (operator):**
  - Bump Alpine base digest: `docker buildx imagetools inspect alpine:3.20`,
    update the `@sha256:...` line in
    [`forwarder-arecord/Dockerfile`](../forwarder-arecord/Dockerfile),
    let CI verify.
  - When Trivy reports a new HIGH/CRITICAL on a future scan, CI fails
    closed. Either fix it (preferred — bump base) or add a justified
    entry to [`.trivyignore`](../.trivyignore) with a comment block
    matching the existing per-package format.

## 9. References

- [AGENTS.md](../AGENTS.md) section 2 — vendor binary constraints and
  the verified library pin inventory.
- [AGENTS.md](../AGENTS.md) section 5 — testing tiers (static, build,
  synthetic E2E, performance, manual smoke).
- [AGENTS.md](../AGENTS.md) section 8 — known issues, including the
  Snapserver `Address already in use` regression.
- [`.trivyignore`](../.trivyignore) — per-block CVE allowlist with
  root cause, fix-version analysis, compensating controls, and
  revisit conditions.
- [docs/troubleshooting.md](troubleshooting.md) — operational
  diagnostics.
- [docs/performance-baseline.md](performance-baseline.md) — idle-CPU
  measurements (informs `AUDIO-5` re-measurement after this hardening).
