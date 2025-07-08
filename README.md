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

## Issues, bugs and limitations

- FLAC compression from FFmpeg to Snapserver seems to cause audio issues. PCM works.
- `tidal-connect/src/bin/tidal_connect_application` accepts TIDAL *High* quality, no *Max*. *High* still should be CD quality (16/44.1 lossless FLAC).

## Troubleshooting

- Make sure your user has access to `/dev/snd` and the ALSA loopback module is loaded.
- Follow container's logs immediatelly after starting with `docker-compose up -d && docker-compose logs -f`.
- For Snapcast issues, verify the stream registration and Snapserver logs.

## Credits

- Based on [TonyTromp/tidal-connect-docker](https://github.com/TonyTromp/tidal-connect-docker)
