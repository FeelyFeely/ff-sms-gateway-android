# Phone hub (Raspberry Pi)

One Raspberry Pi keeps the gateway phones (FeelyFeely SMS + WhatsApp Business
on Evolution) reachable over ADB and their apps running. Every phone stays on
USB permanently, so ADB never drops; charging is stopped by each phone's own
charge limit, not by cutting power (cutting USB power also cuts ADB).

## Hardware

| Item | Notes |
|---|---|
| Raspberry Pi 5 (4 GB is plenty) | with its official 27 W USB-C supply |
| Powered USB hub, 7 ports | its own power supply, ≥ 2.4 A per port (e.g. Anker / Sabrent); the Pi's ports cannot charge 5 phones |
| 5 short USB data cables | data cables, not charge-only |
| Phones | Pixel 6a+ (Android 15+) or Samsung Galaxy A (One UI 6.1+): both have a hard 80–85 % charge limit. Avoid Xiaomi/Infinix here: their "smart charging" only delays reaching 100 %. |

Keep the phones ventilated and out of the sun; heat wears batteries faster than charge level does.

## Set up the Pi

1. Flash Raspberry Pi OS Lite (64-bit), enable SSH, connect it to the internet.
2. Copy this folder over and run: `sudo ./setup.sh ff-phonehub-1`, then open the Tailscale login URL it prints.
3. Optional, saves a tap on every phone: copy the Mac's ADB key so phones already
   authorised for the Mac trust the Pi too:
   `scp ~/.android/adbkey ~/.android/adbkey.pub root@ff-phonehub-1:/root/.android/`
4. List the phones in `/etc/phonehub/phones.conf` (`adb devices` shows the serials).
5. Optional alerts: set `ALERT_URL` in `/etc/phonehub/env` (e.g. a private ntfy.sh topic).

## Each phone (before it goes on the hub)

- Developer options → USB debugging on. On first connection to the Pi, tick **Always allow from this computer** (not needed if you did step 3).
- Battery → Charging optimisation / Protect battery → **limit to 80 %** (Pixel) or **85 %** (Samsung).
- Battery: FeelyFeely SMS and WhatsApp Business set to **Unrestricted**.
- Developer options → **Stay awake while charging: off**.
- No screen lock (an unattended reboot must not wait for a PIN).
- FeelyFeely SMS: Cloud server on, Start on boot on, webhook signing key entered.

## Day to day

```
ssh root@ff-phonehub-1      # over Tailscale, from anywhere
phonehub status             # last report: online, battery %, °C, charging, restarts
adb devices                 # every phone, over USB
adb -s <serial> shell ...   # anything else
journalctl -u phonehub -n 50
```

The watchdog (`phonehub.timer`, every 2 min) alerts when a phone goes offline, runs hotter than 45 °C or drops below 25 %, restarts the SMS and WhatsApp apps if they stopped, and turns network ADB (`:5555`) back on after a phone reboots.
