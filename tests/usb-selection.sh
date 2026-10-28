#!/usr/bin/env bash
set -Eeuo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "$tmp_dir"' EXIT

cat > "$tmp_dir/adb" <<'ADB'
#!/usr/bin/env bash
if [[ "$1" == devices ]]; then
  printf 'List of devices attached\n%s\n' "$TEST_DEVICES"
elif [[ "$1" == -s && "$3" == get-state && "$2" == phone ]]; then
  printf 'device\n'
else
  exit 1
fi
ADB
cat > "$tmp_dir/sudo" <<'SUDO'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$TEST_SUDO_ARGS"
SUDO
chmod +x "$tmp_dir/adb" "$tmp_dir/sudo"
export PATH="$tmp_dir:$PATH"
export TEST_SUDO_ARGS="$tmp_dir/sudo-args"
export TEST_DEVICES=$'emulator-5554\tdevice product:emulator model:Emulator\nphone\tdevice usb:1 model:Pixel\nunauthorized\tunauthorized'

run_selection() {
  bash -c 'source <(sed "$ d" "$1"); usb_select_serial "${2:-}"' _ "$project_dir/bin/pdanet" "${1:-}"
}

[[ "$(run_selection 0)" == emulator-5554 ]]
[[ "$(run_selection 1)" == phone ]]
[[ "$(PDANET_ADB_SERIAL=phone run_selection)" == phone ]]
[[ "$(PDANET_ADB_SERIAL=phone run_selection 0)" == emulator-5554 ]]
if run_selection > "$tmp_dir/out" 2>&1; then exit 1; fi
grep -qE '0: emulator-5554 device.*model:Emulator' "$tmp_dir/out"
grep -qE '1: phone device.*model:Pixel' "$tmp_dir/out"
if run_selection 2 > "$tmp_dir/out" 2>&1; then exit 1; fi
grep -qE 'Device index 2 is not available' "$tmp_dir/out"
[[ "$(bash -c 'source <(sed "$ d" "$1"); usb_turn_on() { printf "on:%s" "$1"; }; usb_run_test() { printf "test:%s" "$1"; }; usb_main "$2" "${3:-}"' _ "$project_dir/bin/pdanet" 1)" == on:1 ]]
[[ "$(bash -c 'source <(sed "$ d" "$1"); usb_run_test() { printf "test:%s" "$1"; }; usb_main "$2" "$3"' _ "$project_dir/bin/pdanet" test 1)" == test:1 ]]
export TEST_DEVICES=$'phone\tdevice model:Pixel'
[[ "$(run_selection)" == phone ]]
export TEST_DEVICES=$'emulator-5554\tdevice model:Emulator\nphone\tdevice model:Pixel'
if (( EUID != 0 )); then
  "$project_dir/bin/pdanet" usb 1
  grep -qxE 'PDANET_ADB_SERIAL=phone' "$TEST_SUDO_ARGS"
  grep -qxE 'on' "$TEST_SUDO_ARGS"
fi
printf 'USB selection tests passed.\n'
