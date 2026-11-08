#!/usr/bin/env bash
# Set up a Raspberry Pi (Raspberry Pi OS 64-bit, Bookworm or later) as the
# phone hub: adb, Tailscale, and the phonehub watchdog every 2 minutes.
# Run as root from this folder:  sudo ./setup.sh [tailscale-hostname]
set -euo pipefail
HOST=${1:-ff-phonehub-1}
cd "$(dirname "$0")"

apt-get update -q
apt-get install -y -q adb android-sdk-platform-tools-common jq curl

# Tailscale with SSH, so the hub is reachable from anywhere on the tailnet.
command -v tailscale >/dev/null || curl -fsSL https://tailscale.com/install.sh | sh
tailscale up --ssh --hostname "$HOST"   # prints a login URL the first time

install -m 755 phonehub.sh /usr/local/bin/phonehub
install -d /etc/phonehub /var/lib/phonehub
[ -f /etc/phonehub/phones.conf ] || install -m 644 phones.conf.example /etc/phonehub/phones.conf
[ -f /etc/phonehub/env ] || cat > /etc/phonehub/env <<'EOF'
# ALERT_URL=https://ntfy.sh/<private-topic>   # optional: POSTed on every alert
# TEMP_MAX_C=45
# LEVEL_MIN=25
# NETWORK_ADB=1
EOF

cat > /etc/systemd/system/phonehub.service <<'EOF'
[Unit]
Description=Gateway phone watchdog
After=network-online.target

[Service]
Type=oneshot
Environment=HOME=/root
ExecStart=/usr/local/bin/phonehub run
EOF

cat > /etc/systemd/system/phonehub.timer <<'EOF'
[Unit]
Description=Run the gateway phone watchdog every 2 minutes

[Timer]
OnBootSec=1min
OnUnitActiveSec=2min

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now phonehub.timer
phonehub --self-test
echo "Done. Edit /etc/phonehub/phones.conf, then: phonehub run && phonehub status"
