# PdaNet Linux CLI

A standalone Linux client for PdaNet+ Wi-Fi proxy and USB tethering modes.
It does not use Android's built-in tethering APIs.
**NOTE:** Currently only tested on my own machine (Fedora Linux 43)

## Install

Run:

```bash
./install.sh
```

The installer:

- installs the required packages with DNF, APT, or Pacman;
- installs `pdanet` to `~/.local/bin`;
- installs the USB tunnel helper to `~/.local/libexec`;
- installs nftables, redsocks, dnscrypt-proxy, and systemd configuration
  under `/etc`;
- uses PolicyKit (`pkexec`) for privileged operations;
- validates the CLI and USB protocol codec.

The systemd services are installed but are not enabled at boot. The CLI
starts and stops them as needed.

For development-only installation without package or system changes:

```bash
./install.sh --skip-packages --skip-system
```

## USB tethering

On the phone, enable USB debugging and PdaNet's **USB Tether** option, then
connect it by USB.

```bash
pdanet usb test
pdanet usb
pdanet usb status
pdanet usb off
```

`pdanet usb test` is isolated and does not change routes. `pdanet usb`
changes the host's Internet routes and DNS, so it can interrupt existing
network sessions.

Set `PDANET_ADB_SERIAL` when more than one authorized ADB device is
connected.

## Wi-Fi Direct proxy

Connect the computer to the phone's PdaNet Wi-Fi Direct network, then run:

```bash
pdanet on
pdanet status
pdanet test
pdanet off
```

The Wi-Fi mode transparently carries TCP and DNS through PdaNet's HTTP
proxy. It does not carry ICMP or arbitrary UDP, so use `pdanet test`
instead of `ping`.

## Files

- `bin/pdanet`: lifecycle CLI for Wi-Fi and USB modes
- `libexec/pdanet-usb-helper`: Linux TUN to PdaNet protocol bridge
- `system/etc`: nftables, redsocks, dnscrypt-proxy, and systemd files
- `install.sh`: dependency and file installer
