#!/bin/bash
# Tests for bin/pab.
#
# adb and paboutput are replaced with fakes on PATH, so every case runs without a
# phone, headphones, or any audio hardware. Each fake reads a scenario from an
# environment variable, which lets one fake cover many device topologies.

set -uo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  \033[32mok\033[0m   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  \033[31mFAIL\033[0m %s\n     expected: %s\n     actual:   %s\n' "$1" "$2" "$3"; }
is()   { [ "$2" = "$3" ] && ok "$1" || bad "$1" "$3" "$2"; }
has()  { case "$2" in *"$3"*) ok "$1";; *) bad "$1" "contains '$3'" "$2";; esac; }

# ------------------------------------------------------------------- fakes

FAKEBIN="$(mktemp -d)"
trap 'rm -rf "$FAKEBIN" "$TMPCFG"' EXIT

cat > "$FAKEBIN/adb" <<'FAKE'
#!/bin/bash
# FAKE_DEVICES: newline-separated "<serial>\t<state>" rows.
# FAKE_PROPS:   "<serial>|<prop>=<value>" rows.
case "$1" in
  devices)
    echo "List of devices attached"
    printf '%b\n' "${FAKE_DEVICES:-}"
    ;;
  -s)
    serial="$2"; shift 2
    if [ "$1" = "shell" ]; then
      shift
      if [ "$1" = "getprop" ]; then
        want="$2"
        printf '%b\n' "${FAKE_PROPS:-}" | while IFS='|' read -r s kv; do
          [ "$s" = "$serial" ] || continue
          case "$kv" in "$want="*) echo "${kv#*=}";; esac
        done
      fi
      # Deliberately consume stdin, exactly as real `adb shell` does. This is
      # what broke device enumeration before `</dev/null` was added.
      cat >/dev/null 2>&1 || true
    fi
    ;;
  connect) echo "connected to $2" ;;
esac
FAKE

cat > "$FAKEBIN/paboutput" <<'FAKE'
#!/bin/bash
# FAKE_OUTPUTS: JSON array. FAKE_DEFAULT: "<uid>\t<name>".
case "${1:-get}" in
  list) printf '%s\n' "${FAKE_OUTPUTS:-[]}" ;;
  get)  printf '%b\n' "${FAKE_DEFAULT:-}" ;;
  set)  [ "${FAKE_SET_OK:-1}" = "1" ] && exit 0 || exit 1 ;;
esac
FAKE

# pab checks for scrcpy before doing anything. The tests never get as far as
# launching it, but the dependency check must pass on a machine without it —
# which is every CI runner.
cat > "$FAKEBIN/scrcpy" <<'FAKE'
#!/bin/bash
exit 0
FAKE

chmod +x "$FAKEBIN/adb" "$FAKEBIN/paboutput" "$FAKEBIN/scrcpy"

TMPCFG="$(mktemp -d)"
export XDG_CONFIG_HOME="$TMPCFG"
export PATH="$FAKEBIN:$PATH"

# Load pab's functions without running its dispatcher, then force it to use the
# fake helper (pab resolves paboutput relative to itself).
PAB_SOURCED=1
# shellcheck source=/dev/null
source "$ROOT/bin/pab"
PABOUTPUT="$FAKEBIN/paboutput"
# pab exports PATH with the real SDK ahead of everything; put the fakes back.
export PATH="$FAKEBIN:$PATH"

echo "pab"

# ------------------------------------------------------------ pure helpers

is "norm_uid strips the mpv-style prefix" \
   "$(norm_uid 'coreaudio/AppleHDA:out')" "AppleHDA:out"
is "norm_uid leaves a bare UID alone" \
   "$(norm_uid 'AppleHDA:out')" "AppleHDA:out"
is "esc_json escapes double quotes" \
   "$(esc_json 'a"b')" 'a\"b'
is "esc_json escapes backslashes" \
   "$(esc_json 'a\b')" 'a\\b'

# --------------------------------------------------------- adb enumeration

export FAKE_DEVICES='ABC123\tdevice\n10.0.0.5:5555\tdevice'
export FAKE_PROPS='ABC123|ro.product.model=Pixel 9\nABC123|ro.serialno=ABC123\n10.0.0.5:5555|ro.product.model=Pixel 9\n10.0.0.5:5555|ro.serialno=ABC123'

is "usb_serial finds the cabled device"   "$(usb_serial)" "ABC123"
is "tcp_serial finds the wireless device" "$(tcp_serial)" "10.0.0.5:5555"

# Regression: `adb shell` reads stdin. Without `</dev/null` it drained the serial
# list feeding the loop and only the first device was ever reported.
PHONES="$(list_adb_json)"
is "list_adb_json reports BOTH transports" \
   "$(printf '%s' "$PHONES" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')" "2"
is "list_adb_json exposes the shared hardware serial" \
   "$(printf '%s' "$PHONES" | python3 -c 'import json,sys; print(len({d["serialno"] for d in json.load(sys.stdin)}))')" "1"
has "list_adb_json labels the wireless entry" "$PHONES" '"kind":"wifi"'

# devices that are listed but not ready must be ignored
export FAKE_DEVICES='ABC123\tunauthorized\n10.0.0.5:5555\tdevice'
is "unauthorized devices are skipped" "$(usb_serial)" ""
export FAKE_DEVICES='ABC123\tdevice\n10.0.0.5:5555\tdevice'

# ------------------------------------------------------------ audio devices

export FAKE_OUTPUTS='[{"uid":"BuiltInSpeakerDevice","name":"MacBook Pro Speakers","default":true},{"uid":"AA-BB:output","name":"Some AirPods Max","default":false}]'
export FAKE_DEFAULT='BuiltInSpeakerDevice\tMacBook Pro Speakers'

AIRPODS_MATCH="AirPods Max"; OUTPUT_UID=""
is "target matches the configured device name" "$(target_output_uid)" "AA-BB:output"

AIRPODS_MATCH="airpods max"
is "device-name matching is case-insensitive" "$(target_output_uid)" "AA-BB:output"

AIRPODS_MATCH="Headphones That Do Not Exist"
is "absent device yields no target" "$(target_output_uid)" ""

AIRPODS_MATCH="AirPods Max"; OUTPUT_UID="BuiltInSpeakerDevice"
is "an explicit UID overrides name matching" "$(target_output_uid)" "BuiltInSpeakerDevice"

OUTPUT_UID="coreaudio/AA-BB:output"
is "an explicit UID accepts the legacy prefix" "$(target_output_uid)" "AA-BB:output"

OUTPUT_UID="NoSuchDevice"
is "a disconnected explicit UID yields no target" "$(target_output_uid)" ""
OUTPUT_UID=""

is "output_name_for resolves a display name" \
   "$(output_name_for 'AA-BB:output')" "Some AirPods Max"
is "default_output_uid reads the current default" \
   "$(default_output_uid)" "BuiltInSpeakerDevice"

# --------------------------------------------------------------- transport

PHONE_SERIAL=""
is "auto prefers USB when both links are up" \
   "$(select_transport auto)" "ABC123 $BUFFER_USB wired"
is "wifi selects the wireless serial and its buffer" \
   "$(select_transport wifi)" "10.0.0.5:5555 $BUFFER_WIFI wireless"
is "usb selects the cabled serial and its buffer" \
   "$(select_transport usb)" "ABC123 $BUFFER_USB wired"

# Wi-Fi jitter needs the larger buffer; USB must never inherit it.
[ "$BUFFER_WIFI" -gt "$BUFFER_USB" ] \
  && ok "wireless buffer exceeds wired buffer" \
  || bad "wireless buffer exceeds wired buffer" ">$BUFFER_USB" "$BUFFER_WIFI"

PHONE_SERIAL="10.0.0.5:5555"
is "an explicit wireless serial forces the wireless buffer" \
   "$(select_transport auto)" "10.0.0.5:5555 $BUFFER_WIFI wireless"
PHONE_SERIAL="ABC123"
is "an explicit wired serial forces the wired buffer" \
   "$(select_transport wifi)" "ABC123 $BUFFER_USB wired"
PHONE_SERIAL="GHOST"
has "an unknown explicit serial is rejected" \
    "$(select_transport auto 2>&1)" "is not connected"
PHONE_SERIAL=""

export FAKE_DEVICES='10.0.0.5:5555\tdevice'
has "usb transport reports the missing cable" \
    "$(select_transport usb 2>&1)" "no USB device"
export FAKE_DEVICES='ABC123\tdevice\n10.0.0.5:5555\tdevice'

has "an unknown transport name is rejected" \
    "$(select_transport banana 2>&1)" "unknown transport"

# --------------------------------------------------------------- info JSON

INFO="$(cmd_info)"
python3 -c 'import json,sys; json.loads(sys.argv[1])' "$INFO" 2>/dev/null \
  && ok "info emits valid JSON" || bad "info emits valid JSON" "parseable" "$INFO"
for k in device default_uid buffer_usb buffer_wifi output_buffer running outputs phones; do
  has "info includes '$k'" "$INFO" "\"$k\""
done

# A device name containing a quote must not break the JSON contract.
export FAKE_OUTPUTS='[{"uid":"X","name":"Nic'"'"'s \"Max\"","default":true}]'
python3 -c 'import json,sys; json.loads(sys.argv[1])' "$(cmd_info)" 2>/dev/null \
  && ok "info survives quotes in a device name" \
  || bad "info survives quotes in a device name" "parseable" "$(cmd_info)"

# --------------------------------------------------------------- run guard

export FAKE_OUTPUTS='[{"uid":"BuiltInSpeakerDevice","name":"MacBook Pro Speakers","default":true}]'
OUT="$("$ROOT/bin/pab" run --wired 2>&1)"
has "guarded run refuses when the target is absent" "$OUT" "no output device matching"
"$ROOT/bin/pab" run --wired >/dev/null 2>&1
is "guarded run exits 1 when the target is absent" "$?" "1"

has "an unknown flag is rejected" \
    "$("$ROOT/bin/pab" run --nonsense 2>&1)" "unknown option"
# --no-guard so the run reaches buffer validation instead of stopping at the
# device check; validation happens before scrcpy is ever launched.
has "a non-numeric buffer is rejected" \
    "$("$ROOT/bin/pab" run --wired --no-guard --buffer abc 2>&1)" "expects a number"

echo
printf '  %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
