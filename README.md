# Tidal Connect Docker with Snapcast integration

This project provides a Docker-based solution for running TIDAL Connect and forwarding audio to Snapcast for multi-room audio playback in arm64 based systems. It consists of two containers: one for the Tidal Connect client and another for an FFmpeg-based audio forwarder. This project assumes you already have a Snapserver and Snapclients configured.

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
FFmpeg container
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
- The FFmpeg container creates a new stream via Snapcast API, reads audio from the loopback device and forwards it over TCP.
- Snapserver receives the stream and distributes synchronized audio to all Snapclients.

## Prerequisites

- **arm64 Docker host:**  
  This project works only in a 64-bit ARM (arm64/aarch64) Linux system, such as Raspberry Pi 3/4 or [arm64 emulated VM](https://rotelok.com/installing-arm64-debian-10-buster-in-a-virtual-machine/) running a 64-bit OS.

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
- The tidal-connect container runs Debian 9 (stretch). I haven't been able to get `/bin/tidal_connect_application` to work in newer OSes.

## Troubleshooting

- Make sure your user has access to `/dev/snd` and the ALSA loopback module is loaded.
- Follow container's logs immediatelly after starting with `docker-compose up -d && docker-compose logs -f`.
- For Snapcast issues, verify the stream registration and Snapserver logs.

## Credits

- Based on [TonyTromp/tidal-connect-docker](https://github.com/TonyTromp/tidal-connect-docker)

-----

[^1]: See `ffmpeg -formats` and https://trac.ffmpeg.org/wiki/audio%20types
[^2]: https://ffmpeg.org/ffmpeg-codecs.html#Audio-Encoders
[^3]: https://github.com/badaix/snapcast/blob/develop/doc/configuration.md