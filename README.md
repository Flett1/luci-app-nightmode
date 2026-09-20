# luci-app-nightmode

LuCI application for OpenWrt to automatically toggle router LEDs based on schedule or manual user preference.

## Features

* **Night Mode Schedule:** Automatically turn off LEDs during specified hours.
* **State Preservation:** Saves original LED status in RAM (`/tmp/led_orig_brightness`) to correctly restore active LEDs when exiting Night Mode.
* **UCI Integration:** Configuration stored in `/etc/config/general`.
* **Lightweight:** Shell-based daemon with minimal system footprint.

## Tested Hardware

* **CMCC RAX3000M** (MediaTek MT7981) — Verified working on OpenWrt 25.12.5.

## Installation

### Building from source in OpenWrt SDK

1. Add package source to your OpenWrt build tree or SDK:
   ```bash
   git clone https://github.com/Flett1/luci-app-nightmode.git package/luci-app-nightmode
