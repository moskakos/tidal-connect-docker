# Troubleshooting

Runtime issues encountered during development of this repo, with the
diagnostic steps that were taken and the workarounds that worked.
Intended audience: future maintainers and AI agents resuming this work.

## Snapserver `bind: Address already in use` after forwarder restart

> **Status (2026-06-27): resolved by upgrading Snapserver.** Reproduced
> on Snapserver **v0.29.0** (rev `208066e5`); does **not** reproduce on
> **v0.35.0** (rev `f1237347`). Forcing `docker compose up -d
> --force-recreate tidal-forwarder-arecord` while a snapclient was
> actively consuming the `Tidal` stream completed `Stream.AddStream` on
> the first attempt with no retries needed. The retry/backoff in
> `forwarder-arecord/entrypoint.sh` (commit `720a7a3`) is kept as a
> defensive measure for older Snapserver builds and for kernel
> `TIME_WAIT`, but is no longer expected to trigger in normal operation.
>
> The rest of this section is retained as historical reference for the
> v0.29.0 behaviour.

### Symptom

After tearing down and recreating the forwarder container (`docker
compose down && docker compose up -d`, or `docker restart
tidal-forwarder-arecord`), the forwarder's `Stream.AddStream` call to
Snapserver fails with:

```json
{
  "error": {
    "code": -32603,
    "data": "bind: Address already in use [system:98 at ./boost_1_85_0/boost/asio/detail/reactive_socket_service.hpp:161 in function 'bind']",
    "message": "Internal error"
  },
  "id": 1,
  "jsonrpc": "2.0"
}
```

Snapserver's `Server.GetStatus` shows **no** stream registered for our
`STREAM_PORT`, yet AddStream still rejects the bind. The forwarder
container then enters a restart loop (with the retry/backoff logic from
commit `720a7a3`) until Docker gives up.

### Conditions observed (2026-06-26)

- Snapserver runs in an **LXC container** on the same Proxmox host as
  everything else (not Docker).
- Snapclients were **actively connected** to Snapserver throughout the
  forwarder teardown.
- `ss -tlnp | grep 5000` **inside the snapcast LXC** shows nothing —
  no kernel-level listener exists.
- Manual `curl` of `Stream.AddStream` reproduces the error → it is not
  a forwarder bug; it is Snapserver's internal state.

### Working hypothesis

Snapserver's Boost.Asio `tcp::acceptor` for the stream's listening port
is kept alive by an active `shared_ptr` chain that includes connected
snapclient sessions. `Stream.RemoveStream` removes the user-visible
stream entry, but the acceptor lingers until the last referencing
session is also torn down. Until then, the next `AddStream` requesting
the same `tcp://0.0.0.0:PORT` URI fails the `bind()` check inside
Boost.Asio.

This matches the behaviour described above: kernel sees no listener,
but Snapserver's *own* internal state refuses the rebind.

### Workarounds (in order of preference)

1. **Use a different `STREAM_PORT`.** Trivial to set: edit the
   `STREAM_PORT=...` line in
   [docker-compose.yml](../docker-compose.yml) under
   `tidal-forwarder-arecord` (or `tidal-forwarder`), then
   `docker compose up -d`. Ports `5001`, `5002`, etc. are typically free.
2. **Restart Snapserver** (`pct restart <ctid>` from Proxmox host, or
   `systemctl restart snapserver` / equivalent inside the LXC). Frees
   all internal state. After this, `STREAM_PORT=5000` works again.
3. **Disconnect all snapclients before tearing down the forwarder.**
   If the acceptor is held by client sessions, removing the clients
   first lets the cleanup chain complete on the server side. Untested
   but consistent with the hypothesis.

### Diagnostic commands

From the **snapcast LXC** (e.g. `ssh root@snapcast`):

```bash
# Is anything actually listening on the port?
ss -tlnp | grep :5000

# What streams does Snapserver believe it has?
curl -s -X POST http://localhost:1780/jsonrpc \
  -H 'Content-Type: application/json' \
  -d '{"id":1,"jsonrpc":"2.0","method":"Server.GetStatus"}' \
  | jq '.result.server.streams[] | {id, uri: .uri.raw, status}'

# Reproduce the bind failure manually
curl -s -X POST http://localhost:1780/jsonrpc \
  -H 'Content-Type: application/json' \
  -d '{"id":1,"jsonrpc":"2.0","method":"Stream.AddStream","params":{"streamUri":"tcp://0.0.0.0:5000?name=Test&codec=pcm&sampleformat=44100:16:2"}}'
```

From the **forwarder side** (`ssh tidal-dev`):

```bash
# Forwarder log: look for "AddStream JSON-RPC error" lines
docker logs tidal-forwarder-arecord 2>&1 | grep -E 'AddStream|Stream registered|Stream removed'

# Sockets associated with the stream port — should be empty if the
# forwarder is down
ss -tan | grep :5000
```

### Upstream

Not yet filed against `badaix/snapcast`. If filing: include the LXC
networking detail, the snapclient-attached state at teardown, and the
manual `curl` reproducer above. The forwarder side of this repo is not
needed in the reproducer.

### Why the existing retry/backoff in the forwarder doesn't fix this

`forwarder-arecord/entrypoint.sh` retries `AddStream` with exponential
backoff up to ~90 s total (commit `720a7a3`). That suffices for kernel
`TIME_WAIT` (60 s typical), but **does not** help when Snapserver
itself is holding the port in its own memory — only restarting
Snapserver, or picking a different port, clears that state.

## BASE-1: Debian 12 + SONAME symlinks does not satisfy the vendor binary (refuted)

> **Status (2026-06-30): refuted.** Empirical evidence from CI run
> [28461155940](https://github.com/moskakos/tidal-connect-docker/actions/runs/28461155940)
> on branch `feat/base-1-debian12-refute` (commit `649fbb3`). The
> experimental Dockerfile was **not** merged to `dev`; this section is
> the durable record of the negative result so the experiment is not
> repeated.

### Hypothesis tested

Rebase the `tidal-connect` image on `debian:bookworm-slim` (Debian 12),
install the current Debian-12 versions of the libraries the vendor
binary needs (`libssl3`, `libavformat59`, `libavcodec59`, `libavutil57`,
`libswresample4`, `libflac12`, `libflac++10`, plus the libs that have
been stable since Debian 8: `libcurl4`, `libportaudio2`, `libasound2`,
`libavahi-client3`, `libavahi-common3`), then create SONAME-only
compatibility symlinks for the Debian-9-era names the binary expects:

| Expected by binary (Debian 9)   | Symlinked to (Debian 12)        |
|---------------------------------|---------------------------------|
| `libssl.so.1.0.0`               | `libssl.so.3`                   |
| `libcrypto.so.1.0.0`            | `libcrypto.so.3`                |
| `libavformat.so.57`             | `libavformat.so.59`             |
| `libavcodec.so.57`              | `libavcodec.so.59`              |
| `libavutil.so.55`               | `libavutil.so.57`               |
| `libswresample.so.2`            | `libswresample.so.4`            |
| `libFLAC.so.8`                  | `libFLAC.so.12`                 |
| `libFLAC++.so.6`                | `libFLAC++.so.10`               |

The expectation was: `ldd` resolves all SONAMEs (because the loader
can open the symlink targets), and *if* `ldd` passes we add a
runtime-execution probe to see what really breaks. The expectation was
wrong about which check fires first.

### Result

`ldd` **fails on both `linux/arm/v7` and `linux/arm64`**. The loader
opens the target SOs without trouble — the problem is one level deeper:
the binary requests **versioned symbols** that the newer libraries do
not provide.

The verbatim failures (CI run `28461155940`, both arches):

```text
.../libssl.so.1.0.0:        version `OPENSSL_1.0.0'   not found
.../libssl.so.1.0.0:        version `OPENSSL_1.0.1'   not found
.../libcrypto.so.1.0.0:     version `OPENSSL_1.0.0'   not found
.../libcurl.so.4:           version `CURL_OPENSSL_3'  not found
.../libavcodec.so.57:       version `LIBAVCODEC_57'   not found
.../libavformat.so.57:      version `LIBAVFORMAT_57'  not found
.../libavutil.so.55:        version `LIBAVUTIL_55'    not found
.../libswresample.so.2:     version `LIBSWRESAMPLE_2' not found
```

(Each line is prefixed with the binary path; trimmed here for clarity.)

`libFLAC.so.8` / `libFLAC++.so.6` did **not** raise version errors,
suggesting FLAC does not export versioned symbols (or the vendor binary
does not depend on any versioned ones). They are still a runtime
correctness gamble, just not blocked at ldd time.

### Why the experiment was guaranteed to fail

The vendor binary was linked against Debian-9 libraries that **do**
emit GNU symbol versions (verified by `objdump -T` on the original
SOs). Linux's dynamic loader (`ld-linux*.so.3` / `ld-linux-aarch64.so.1`)
performs the version check in `_dl_check_map_versions` and refuses to
proceed when a requested `VERDEF` is missing from the resolved SO,
even if the unversioned symbol name does exist. A SONAME symlink only
solves the *file-open* problem; it does nothing about the *version
table* inside the SO.

This applies regardless of how the symlink is created (`ln -s`,
`ldconfig` alias, `LD_LIBRARY_PATH`, `LD_PRELOAD` — all share the same
post-open versioning logic).

Note on `libcurl.so.4`: this SONAME is stable across Debian 8–12, but
the *symbol version* `CURL_OPENSSL_3` is specific to libcurl builds
linked against OpenSSL 1.0 (Debian 8/9). Debian 10+ libcurl rebuilt
against OpenSSL 1.1+/3.0 emits `CURL_OPENSSL_4`. **`AGENTS.md` §2's
note that libcurl is "compatible across Debian 8–12" is true for SONAME
compatibility but wrong for symbol-version compatibility** — the
binary needs a libcurl built against OpenSSL 1.0, which only Debian
8/9 (and historical snapshots) ship.

### Consequences for BASE-2 and beyond

The only path to a newer base image is to **provide the actual
Debian-9 .so files** alongside the newer base. Concretely, BASE-2's
approach (a) — vendor the Debian-9 `.deb`s for `libssl1.0.0`,
`libcurl3`, `libavformat57` (+ `-codec57`, `-util55`, `-swresample2`),
`libflac8`, `libflac++6v5` into `/opt/legacy-libs` on a Debian-11 (or
-12) base and set `LD_LIBRARY_PATH=/opt/legacy-libs` for the vendor
binary's launcher.

This is structurally similar to what the current `raspbian/stretch`
image does, just inverted: instead of pinning the *whole base* to
Debian 9, vendor only the *legacy libraries* into a modern base, while
all surrounding tooling (`apt`, `bash`, `coreutils`, security
patches, `libc`) tracks the newer release.

Open question for BASE-2: glibc compatibility. The vendor binary was
linked against glibc 2.24 (Debian 9). Debian 11 ships glibc 2.31,
Debian 12 ships glibc 2.36. Newer glibc is forward-compatible with
older binaries by design (`GLIBC_2.X` symbols accumulate), so this is
not expected to be a problem — but worth verifying with `ldd` /
`objdump -T` on the binary's `libc.so.6` deps as the first step of
BASE-2.

### Reproducing this

```bash
git fetch origin feat/base-1-debian12-refute
git checkout feat/base-1-debian12-refute
# inspect tidal-connect/Dockerfile to see the experiment
# CI run linked above contains the artifact ldd-armv7.zip /
# ldd-arm64.zip with the full ldd output
```

The branch is preserved on `origin` as evidence; it will not be merged.

## BASE-2: Debian 11 + vendored Debian-9 libs (validated)

> **Status (2026-07-01): validated.** Empirical evidence from CI run
> [28534452841](https://github.com/moskakos/tidal-connect-docker/actions/runs/28534452841)
> on branch `feat/base-2-debian11-vendored` (commit `6540958`). The
> candidate Dockerfile is preserved as
> [`tidal-connect/Dockerfile.debian11-vendored`](../tidal-connect/Dockerfile.debian11-vendored)
> on that branch — **not** merged into `dev` because the production
> Dockerfile cutover is a human decision (needs a real-hardware TIDAL
> phone-app smoke test that CI cannot do).

### Hypothesis validated

Multi-stage Docker build:

- **Stage 1 (`legacy`)** — `FROM --platform=linux/arm/v7 raspbian/stretch`.
  `apt install` FFmpeg 3.x (`libavformat57`, `libavcodec57`, `libavutil55`,
  `libswresample2`), FLAC 8 (`libflac8`, `libflac++6v5`), `libidn11`, and
  `curl` from stretch. Then override with **Debian-8** `libssl1.0.0` and
  `libcurl3` from `snapshot.debian.org` — same URLs the production
  Dockerfile has always used. apt handles the ~30 FFmpeg transitive codec
  deps (`libx264`, `libopus`, `libvorbis`, `libmp3lame`, …) automatically
  with correct SONAME symlinks.
- **Stage 2 (runtime)** — `FROM --platform=linux/arm/v7 debian:11-slim`.
  Native apt install of stable-across-releases libs (`libportaudio2`,
  `libasound2`, `libavahi-*`, `libbsd0`, `avahi-daemon`, `alsa-utils`).
  Then `COPY --from=legacy` for BOTH `/usr/lib/arm-linux-gnueabihf/` and
  `/lib/arm-linux-gnueabihf/` into `/opt/legacy-libs`. Prune Debian-9
  glibc-family files from `/opt/legacy-libs`. `ldconfig -n` to
  (re-)create SONAME symlinks. `ENV LD_LIBRARY_PATH=/opt/legacy-libs`.

### CI result

```text
All libraries resolved on linux/arm64 (debian11-vendored)
Running 30-second smoke probe for tidal_connect_application...
exit_code=1
Smoke probe passed: binary loaded and ran without segfault on linux/arm64
```

The binary loads all its shared libraries (no `not found`, no
`error while loading shared libraries`, no segfault). It exits with
code 1 as expected in CI — no real ALSA devices, no valid TIDAL
certificate, no mDNS on the host network — but that is an
application-level exit, not a linker or ABI failure. Same criterion
CI already applies to the production Dockerfile passes here.

### Key lessons (8-iteration path to green)

| # | Commit    | Lesson                                                                                                                       |
|---|-----------|------------------------------------------------------------------------------------------------------------------------------|
| 1 | `bf40068` | Initial subagent attempt: snapshot.debian.org URLs (path `debian/` was wrong; correct is `debian-security/` for these pkgs). |
| 2 | `da5d302` | Correct URLs resolved via `snapshot.debian.org` `/mr/binary/<pkg>/<ver>/binfiles?fileinfo=1` metadata API. `linux/arm/v7` platform pinning forced (vendor binary armhf-only). |
| 3 | `b6fb856` | Debian `.deb`s ship the real `.so` file; the SONAME→file symlink is created by postinst `ldconfig` — bypass with `ldconfig -n` on the target dir. |
| 4 | `53f19f7` | Snapshot-URL harvest stalls at ~30 FFmpeg transitive codec deps (`libx264`, `libopus`, `libvorbis`, …). Switch to multi-stage build: `FROM raspbian/stretch AS legacy` + `apt install` handles the closure automatically. |
| 5 | `54a333c` | Debian 9's `libssl1.0.2` SONAME is `libssl.so.1.0.2`, not `libssl.so.1.0.0` (verified with `strings`). ldconfig won't create a mismatched alias. Explicit `ln -sf` works for the *filename* but the *symbol version* table still refuses (same class of refute as BASE-1). |
| 6 | `5bf9769` | Fix: use **Debian 8**'s `libssl1.0.0` and `libcurl3` from `snapshot.debian.org` — they emit the `OPENSSL_1.0.0` / `OPENSSL_1.0.1` / `CURL_OPENSSL_3` symbol version tags the vendor binary actually needs. This is the same override the production Dockerfile has always used. |
| 7 | `25afdfc` | Debian 9 is pre-usrmerge: `libidn.so.11` lives in `/lib/arm-linux-gnueabihf/`, not `/usr/lib/…`. Add a second `COPY --from=legacy` for `/lib/…`. |
| 8 | `6540958` | The second COPY brings Debian 9's `libc.so.6` (glibc 2.24) too, and `LD_LIBRARY_PATH=/opt/legacy-libs` then makes every Debian 11 binary (`/bin/sh`, `chmod`, …) load the old libc first and crash with `GLIBC_2.28 not found`. Fix: `rm` glibc-family SO files from `/opt/legacy-libs` after both COPYs. Debian 11's glibc 2.31 is forward-compatible so the Debian-9 SOs still work. |

Everything above is captured in the individual commit messages on
`feat/base-2-debian11-vendored`; they are the primary reference if the
approach ever needs to be re-derived.

### Consequences

- The base-image-modernization scope (BASE-1 refuted approach (c),
  BASE-2 validated approach (a)) is now conclusive: **only vendoring
  Debian-9/8 libraries into a modern base image works.** SONAME
  symlinks alone are refuted; matching-version overrides on the actual
  library files are required.
- Trivy CVE count on the candidate image should be lower than the
  production `raspbian/stretch` image (Debian 11 base + modern
  `libavahi-*`/`libportaudio2`/`libasound2` from Debian 11
  security-patched builds). Not yet measured; a future task can quantify.
- Runtime CPU / memory / startup-time on real hardware are not yet
  measured; a future task can quantify.

### Handoff for production cutover (human decision)

To swap production to the candidate:

1. Rename `tidal-connect/Dockerfile.debian11-vendored` → `Dockerfile`
   (or update `docker-compose.yml` to build from the candidate file).
2. Rebuild + push to real Raspberry Pi hardware.
3. Manually verify with the TIDAL phone app: device is discovered via
   mDNS, playback starts and continues without dropouts, forwarder
   pipeline (either `ffmpeg` or `arecord` profile) works unchanged.
4. Only then decide whether the CI matrix should keep the production
   Dockerfile as a legacy reference or drop it.

A safer alternative to a straight swap is a Compose-profile
side-by-side (like `ffmpeg` vs `arecord` for the forwarder): keep both
Dockerfiles, add `docker-compose.debian11.yml` with `image:` overrides,
run both variants on the deployment host for a few weeks before
retiring the old one.

### Reproducing this

```bash
git fetch origin feat/base-2-debian11-vendored
git checkout feat/base-2-debian11-vendored
# inspect tidal-connect/Dockerfile.debian11-vendored — the working
# multi-stage build.
# CI run linked above contains the ldd-arm64-debian11-vendored artifact
# with the full ldd output and the smoke probe stdout.
```

The branch is preserved on `origin` as evidence; the Dockerfile,
CI matrix entry, and smoke probe stay there until the human decides to
promote the candidate to production.

