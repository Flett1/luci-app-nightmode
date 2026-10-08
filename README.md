# luci-app-nightmode

LuCI application for OpenWrt to automatically toggle router LEDs based on schedule or manual user preference.

## Features

* **Night Mode Schedule:** Automatically turn off LEDs during specified hours.
* **State Preservation:** Saves original LED status in RAM (`/tmp/led_orig_brightness`) to correctly restore active LEDs when exiting Night Mode.
* **UCI Integration:** Configuration stored in `/etc/config/general`.
* **Lightweight:** Shell-based daemon with minimal system footprint.

## Status:
* **Confirmed working** as of September 2026

## Tested Hardware

* **CMCC RAX3000M** (MediaTek MT7981) — Verified working on OpenWrt 25.12.5.

## Installation

### Easy Installation

1. Download and install **WinSCP**.
2. Connect to your router using its IP address, the `root` username, and the router password.
3. Copy both `.apk` files to the `/tmp` directory on the router.
4. Connect to the router via SSH.
5. Run the following command:

```sh
apk add --allow-untrusted /tmp/luci-app-nightmode-*.apk /tmp/luci-i18n-nightmode-ru-*.apk
```

After installation, the application will appear in the **LuCI** interface.

### Building from Source in OpenWrt SDK

1. Navigate to your OpenWrt SDK or build tree directory.
2. Clone the package repository:

```bash
git clone https://github.com/Flett1/luci-app-nightmode.git package/luci-app-nightmode
```

3. The package can then be built using the OpenWrt SDK.

---

**Language:** [🇬🇧 English](README.md) · [🇷🇺 Русский](README.ru.md)
