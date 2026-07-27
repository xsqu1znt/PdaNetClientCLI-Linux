# PdaNet Linux CLI

A standalone Linux client for PdaNet+ Wi-Fi proxy and USB tethering modes.
It does not use Android's built-in tethering APIs.

**NOTE:** Currently only tested on my own machine (Fedora Linux 43).

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

## Dependencies

The installer checks the native package database and installs only missing
packages. The exact package names are:

| Distribution          | Packages                                                                                                                       |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| Fedora / DNF          | `android-tools bash coreutils curl dnscrypt-proxy gawk glibc grep iproute nftables polkit python3 redsocks systemd util-linux` |
| Debian / Ubuntu / APT | `adb bash coreutils curl dnscrypt-proxy gawk grep iproute2 libc-bin nftables policykit-1 python3 redsocks systemd util-linux`  |
| Arch / Pacman         | `android-tools bash coreutils curl dnscrypt-proxy gawk glibc grep iproute2 nftables polkit python redsocks systemd util-linux` |

The main components are ADB for the USB transport, Python for the USB
tunnel helper, iproute and nftables for routing, redsocks and
dnscrypt-proxy for Wi-Fi proxy mode, systemd/resolvectl for service and DNS
management, and PolicyKit for privileged installation. Curl and the
standard shell utilities are used for connection checks and lifecycle
management.

For development-only installation without package or system changes:

```bash
./install.sh --skip-packages --skip-system
```

## How it connects

In Wi-Fi Direct mode, the computer joins the network created by the PdaNet
phone app. The CLI sends TCP traffic to the phone's HTTP proxy at
`192.168.49.1:8000`: nftables redirects local TCP connections into
redsocks, while dnscrypt-proxy supplies DNS. The phone then makes the
outbound Internet connections on the computer's behalf.

In USB mode, ADB forwards a dynamically selected localhost port to the
PdaNet service listening on the phone. The USB helper performs PdaNet's
binary handshake, creates the `pdanet0` TUN interface at `10.1.19.2`, and
encapsulates raw IPv4 packets into PdaNet frames. The CLI installs routes
and DNS for that interface; the phone decapsulates the packets, performs
userspace TCP/UDP/DNS forwarding, and sends response packets back through
the same ADB connection.

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
