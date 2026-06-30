# Tidal Connect Docker with Snapcast integration

This project provides a Docker-based solution for running TIDAL Connect and forwarding audio to Snapcast for multi-room audio playback in ARM-based systems (both 32-bit armv7/armhf and 64-bit arm64/aarch64). It consists of two containers: one for the Tidal Connect client and another for an FFmpeg-based audio forwarder. This project assumes you already have a Snapserver and Snapclients configured.

## How does this work?

Something like this:

```
TIDAL app
   │
   │  (Tidal Connect protocol over LAN)
   ▼
Tidal Connect container
   │
   │  (audio output via ALSA loopback device)
   ▼
FFmpeg container (or arecord alternative)
   │
   │  (audio stream via TCP)
   ▼
Snapserver
   │
   │  (synchronized audio via TCP)
   ▼
Snapclient(s)
```

- The TIDAL app connects to the Tidal Connect container on your network.
- Tidal Connect outputs audio to an ALSA loopback device.
- The FFmpeg container creates a new stream via Snapcast API, reads audio from the loopback device and forwards it over TCP. An alternative minimal `arecord`-based forwarder is available for lower CPU usage (see "Choosing a forwarder" below).
- Snapserver receives the stream and distributes synchronized audio to all Snapclients.

## Prerequisites

- **ARM Docker host:**  
  This project works on both 32-bit ARM (armv7/armhf) and 64-bit ARM (arm64/aarch64) Linux systems, such as Raspberry Pis or [ARM emulated VM](https://rotelok.com/installing-arm64-debian-10-buster-in-a-virtual-machine/).

- **ALSA Loopback device:**  
  The ALSA loopback kernel module (`snd-aloop`) must be available and loaded on the Docker host.  
  You can load it with:  
  ```sh
  sudo modprobe snd-aloop

  # Add snd-aloop to /etc/modules to ensure the loopback device is available after reboot.
  echo snd-aloop | sudo tee -a /etc/modules
  ```

- **Docker and Docker Compose:**  
  Ensure both Docker and Docker Compose are installed and running on your host.

- **Snapserver and Snapclients:**  
  You need a working Snapcast infrastructure.  
  (This project does not start Snapserver or Snapclients for you.)

- **Network configuration:**  
  The containers must be able to communicate with Snapserver (typically via `network_mode: host`).

- **Access to `/dev/snd`:**  
  The Docker containers must have access to the host's `/dev/snd` for audio playback.

## Quick Start

1. **Clone this repository:**
   ```sh
   git clone https://github.com/moskakos/tidal-connect-docker.git
   cd tidal-connect-docker
   ```

2. **Edit `docker-compose.yml` as needed:**
   - Set the correct ALSA device (e.g. `plughw:Loopback,0`)
   - Adjust environment variables for your setup

3. **Start the containers:**
   ```sh
   docker-compose up -d
   ```
   
   To use the alternative low-CPU `arecord` forwarder instead:
   ```sh
   docker compose --profile arecord up -d
   ```

4. **Check logs:**
   ```sh
   docker-compose logs -f
   ```

## Configuration

- **ALSA Device:**  
  Set the `OUTPUT_DEVICE` and `AUDIO_DEVICE` environment variables to match your system's loopback device.
- **Snapserver:**  
  Ensure Snapserver is running and accessible from the forwarder container.
- **Other Parameters:**  
  Sample rate, channels, buffer sizes, and more can be set in `docker-compose.yml`.

### ALSA buffering (arecord forwarder)

- `PERIOD_TIME` / `BUFFER_TIME`: when using the `arecord` forwarder these
  environment variables control ALSA capture buffering (microseconds). The
  `BUFFER_TIME` value should be a small integer multiple of `PERIOD_TIME`.
  Example (in `docker-compose.yml`):

  - `PERIOD_TIME=125000`   # 125 ms period
  - `BUFFER_TIME=500000`   # 500 ms buffer (4 periods)

  See `forwarder-arecord/entrypoint.sh` for details and sensible defaults.

### Entrypoint override

You can override the `tidal-connect` container entrypoint by mounting a
script at `/0-entrypoint.sh`. If present, the container will execute
`/0-entrypoint.sh` instead of the bundled `entrypoint.sh` (this is useful
for advanced customizations). Use the original
[tidal-connect/entrypoint.sh](tidal-connect/entrypoint.sh) as a base.

### Choosing a forwarder

This project provides two audio forwarder implementations. Selection happens
via Compose profiles. The repo ships a `.env` file at the root that pins
`COMPOSE_PROFILES=ffmpeg` so that the historical command `docker compose
up -d` keeps working unchanged.

#### FFmpeg forwarder (default)
- **Profile:** `ffmpeg` (selected by the shipped `.env`)
- **Container:** `tidal-forwarder`
- **Pros:** More flexible, supports multiple codecs (PCM, FLAC), adjustable buffering and resampling
- **Cons:** Higher CPU usage, especially at idle (~33% on ARM-emulated systems)
- **Start command:**
  ```sh
  docker compose up -d
  # or explicitly:
  docker compose --profile ffmpeg up -d
  ```

#### arecord forwarder (alternative)
- **Profile:** `arecord`
- **Container:** `tidal-forwarder-arecord`
- **Pros:** Minimal CPU usage (significantly lower at idle), simple pipeline
- **Cons:** PCM only (no FLAC), no resampling or buffering options
- **Recommended for:** Low-resource hosts, ARM-emulated VMs, or any environment where idle CPU is a concern
- **Start command:**
  ```sh
  # one-shot:
  COMPOSE_PROFILES=arecord docker compose up -d
  # or persistently: edit .env and set COMPOSE_PROFILES=arecord
  ```

**Note:** Both forwarders use the same `STREAM_NAME` and capture the same
ALSA loopback device, so only run one at a time to avoid conflicts in
Snapserver.

## Configuration options

| Variable                | Container        | Description                                          | Example value                        |
|-------------------------|------------------|------------------------------------------------------|--------------------------------------|
| `OUTPUT_DEVICE`         | tidal-connect    | ALSA device for Tidal Connect audio output           | `Loopback: PCM (plughw:0,1)`         |
| `TC_NAME`               | tidal-connect    | Device name shown in TIDAL app                       | `Snapcast multiroom`                 |
| `TC_MODEL`              | tidal-connect    | Model name 🤷                                        | `Tidal Docker`                       |
| `TC_LOG_LEVEL`          | tidal-connect    | Log verbosity (0=quiet, 4=debug)                     | `1`                                  |
| `TC_DISABLE_APP_SEC`    | tidal-connect    | Disable app security checks                          | `true` or `false`                    |
| `TC_DISABLE_WEB_SEC`    | tidal-connect    | Disable web security checks                          | `true` or `false`                    |
| `SC_ENABLE`             | tidal-connect    | Enable `speaker_controller_application`              | `true` or `false`                    |
| `SNAPSERVER_HOST`       | tidal-forwarder  | Hostname or IP of Snapserver                         | `snapcast.local`                     |
| `SNAPSERVER_API_PORT`   | tidal-forwarder  | Snapserver API port                                  | `1780`                               |
| `STREAM_NAME`           | tidal-forwarder  | Stream name registered in Snapserver                 | `Tidal`                              |
| `STREAM_PORT`           | tidal-forwarder  | TCP port for audio stream to Snapserver              | `5000`                               |
| `FFMPEG_AUDIO_FORMAT`   | tidal-forwarder  | FFmpeg output format[^1]                             | `s16le` (PCM) or `flac`              |
| `FFMPEG_AUDIO_CODEC`    | tidal-forwarder  | FFmpeg audio codec[^2]                               | `pcm_s16le` (PCM) or `flac`          |
| `SC_AUDIO_CODEC`        | tidal-forwarder  | Codec type for Snapcast[^3] stream registration      | `pcm` or `flac`                      |
| `AUDIO_DEVICE`          | tidal-forwarder  | ALSA device FFmpeg reads from (loopback)             | `plughw:Loopback,0`                  |
| `SAMPLE_RATE`           | tidal-forwarder  | Audio sample rate (Hz)                               | `44100`                              |
| `CHANNELS`              | tidal-forwarder  | Number of audio channels                             | `2`                                  |
| `BUFFER_SIZE`           | tidal-forwarder  | FFmpeg buffer size                                   | `1024`                               |
| `AUDIO_BUFFER`          | tidal-forwarder  | Audio frame buffer size                              | `2048`                               |
| `FLAC_COMPRESSION_LEVEL`| tidal-forwarder  | FLAC compression level (1=fastest, 8=highest compression) | `8`                             |

**Note:**  
- All variables can be set in `docker-compose.yml` under the appropriate service.
- PCM (`s16le`/`pcm_s16le`/`pcm`) is recommended for best reliability.

Also please note that I have no idea what all the parameters in `/bin/tidal_connect_application` actually do. I wanted to expose them just in case.

## Issues, bugs and limitations

- FLAC compression from FFmpeg to Snapserver seems to cause audio issues. PCM works.
- `/bin/tidal_connect_application` accepts TIDAL *High* quality at best - no *Max*. *High* still should be CD quality (lossless 16/44.1).
- `TC_DISABLE_APP_SEC` and `TC_DISABLE_WEB_SEC` set to `false` didn't work for me.
- The tidal-connect container runs Debian 9 (stretch). `/bin/tidal_connect_application` requires an old operating system and does not work on newer OS versions. The Docker image is built for ARM (armv7/armhf), but also works on ARM64 devices when Docker uses proper emulation.

## Troubleshooting

- Make sure your user has access to `/dev/snd` and the ALSA loopback module is loaded.
- Follow container's logs immediatelly after starting with `docker-compose up -d && docker-compose logs -f`.
- For Snapcast issues, verify the stream registration and Snapserver logs.

See also: [docs/troubleshooting.md](docs/troubleshooting.md),
[docs/performance-baseline.md](docs/performance-baseline.md), and
[docs/security.md](docs/security.md) for additional diagnostics,
performance tuning, and the security posture of this stack.

## Credits

- Based on [TonyTromp/tidal-connect-docker](https://github.com/TonyTromp/tidal-connect-docker)

-----

[^1]: See `ffmpeg -formats` and https://trac.ffmpeg.org/wiki/audio%20types
[^2]: https://ffmpeg.org/ffmpeg-codecs.html#Audio-Encoders
[^3]: https://github.com/badaix/snapcast/blob/develop/doc/configuration.md