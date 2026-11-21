#!/bin/sh
set -eu

case "${1:-}" in
  short|long) test_type=$1 ;;
  *) echo "Usage: $0 short|long" >&2; exit 2 ;;
esac

devices=$(/usr/sbin/smartctl --scan-open)
status=0
while read -r device option device_type rest; do
  [ -n "$device" ] || continue
  if ! /usr/sbin/smartctl -d "$device_type" -t "$test_type" "$device"; then
    status=1
  fi
done <<EOF
$devices
EOF
exit "$status"
