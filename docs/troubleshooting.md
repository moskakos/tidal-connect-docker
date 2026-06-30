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
