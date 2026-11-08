#!/usr/bin/env bash
# phonehub: keep the gateway phones on this Pi reachable and their apps running.
# Run by phonehub.timer every 2 minutes; `phonehub status` prints the last report.
#
# For each phone in phones.conf it:
#   - checks the phone answers over USB ADB (alerts when it does not)
#   - restarts the SMS gateway and WhatsApp Business apps if they are not running
#   - turns network ADB (port 5555) back on after a reboot, if NETWORK_ADB=1
#   - records battery level, temperature and charging state
# Alerts go to the journal, and to ALERT_URL (POST, plain text) when set. An
# alert repeats only when a phone's problems change, not every run.
set -uo pipefail

CONF=${PHONEHUB_CONF:-/etc/phonehub/phones.conf}
STATE=${PHONEHUB_STATE:-/var/lib/phonehub}
[ -f /etc/phonehub/env ] && . /etc/phonehub/env
DEFAULT_PKGS=${DEFAULT_PKGS:-"cloud.feelyfeely.sms com.whatsapp.w4b"}
TEMP_MAX_C=${TEMP_MAX_C:-45}     # alert above this battery temperature
LEVEL_MIN=${LEVEL_MIN:-25}       # alert below this charge (charging has stopped?)
NETWORK_ADB=${NETWORK_ADB:-1}
ALERT_URL=${ALERT_URL:-}

log() { echo "phonehub: $*" >&2; }   # stderr: stdout carries the JSON

alert() {  # alert <serial> <name> <problems>; only when the problems changed
  local serial=$1 name=$2 problems=$3 last="$STATE/last_$1"
  [ "$(cat "$last" 2>/dev/null)" = "$problems" ] && return 0
  echo "$problems" > "$last"
  local msg="phonehub $(hostname): $name ($serial): ${problems:-OK again}"
  log "$msg"
  [ -n "$ALERT_URL" ] && curl -fsS -m 10 -d "$msg" "$ALERT_URL" >/dev/null || true
}

# battery_field <dumpsys battery output> <field>  ->  value
battery_field() { awk -F': ' -v k="  $2" '$1==k {print $2; exit}' <<<"$1"; }

check_phone() {
  local serial=$1 name=$2; shift 2
  local pkgs=${*:-$DEFAULT_PKGS} problems="" a="adb -s $serial"

  if [ "$($a get-state 2>/dev/null)" != "device" ]; then
    alert "$serial" "$name" "offline (not on USB, or USB debugging not allowed)"
    echo "{\"serial\":\"$serial\",\"name\":\"$name\",\"online\":false}"
    return
  fi

  local bat level temp status
  bat=$($a shell dumpsys battery 2>/dev/null)
  level=$(battery_field "$bat" level)
  temp=$(battery_field "$bat" temperature); temp=$(( ${temp:-0} / 10 ))
  status=$(battery_field "$bat" status)   # 2 charging, 3 discharging, 4 not charging, 5 full
  [ "${temp:-0}" -gt "$TEMP_MAX_C" ] && problems+="hot ${temp}C; "
  [ "${level:-100}" -lt "$LEVEL_MIN" ] && problems+="battery ${level}%; "

  local pkg restarted=""
  for pkg in $pkgs; do
    $a shell pm path "$pkg" >/dev/null 2>&1 || continue   # not installed on this phone
    if [ -z "$($a shell pidof "$pkg" 2>/dev/null)" ]; then
      $a shell monkey -p "$pkg" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
      restarted+="$pkg "
    fi
  done
  if [ -n "$restarted" ]; then
    sleep 3; $a shell input keyevent KEYCODE_HOME >/dev/null 2>&1
    log "$name: restarted $restarted"
  fi

  # adbd forgets tcpip mode on reboot. Only switch when it is off: switching
  # restarts adbd, which drops USB for a moment.
  if [ "$NETWORK_ADB" = 1 ] && [ "$($a shell getprop service.adb.tcp.port 2>/dev/null | tr -d '\r')" != 5555 ]; then
    $a tcpip 5555 >/dev/null 2>&1 && log "$name: network ADB on :5555"
  fi

  alert "$serial" "$name" "${problems%; }"
  echo "{\"serial\":\"$serial\",\"name\":\"$name\",\"online\":true,\"level\":${level:-null},\"temp_c\":$temp,\"status\":${status:-null},\"restarted\":\"${restarted% }\"}"
}

main() {
  mkdir -p "$STATE"
  adb start-server >/dev/null 2>&1
  local out="[" sep="" serial name rest
  while read -r serial name rest; do
    case "$serial" in ''|\#*) continue ;; esac
    out+="$sep$(check_phone "$serial" "$name" $rest)"; sep=","
  done < "$CONF"
  echo "$out]" > "$STATE/status.json.tmp" && mv "$STATE/status.json.tmp" "$STATE/status.json"
  # Phones on USB that are not in the list: say so once, so nobody is forgotten.
  local s
  for s in $(adb devices | awk 'NR>1 && $2=="device" && $1 !~ /:/ {print $1}'); do
    grep -q "^$s[[:space:]]" "$CONF" || alert "$s" unlisted "on USB but not in $CONF"
  done
}

self_test() {
  local sample=$'Current Battery Service state:\n  AC powered: false\n  USB powered: true\n  status: 2\n  level: 81\n  temperature: 312\n'
  [ "$(battery_field "$sample" level)" = 81 ] || { echo "level parse failed"; exit 1; }
  [ "$(battery_field "$sample" temperature)" = 312 ] || { echo "temperature parse failed"; exit 1; }
  [ "$(battery_field "$sample" status)" = 2 ] || { echo "status parse failed"; exit 1; }
  echo "self-test ok"
}

case "${1:-run}" in
  run) main ;;
  status) jq . "$STATE/status.json" 2>/dev/null || cat "$STATE/status.json" ;;
  --self-test) self_test ;;
  *) echo "usage: phonehub [run|status|--self-test]"; exit 2 ;;
esac
