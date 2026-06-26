# Troubleshooting

Runtime issues encountered during development of this repo, with the
diagnostic steps that were taken and the workarounds that worked.
Intended audience: future maintainers and AI agents resuming this work.

## Snapserver `bind: Address already in use` after forwarder restart

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
