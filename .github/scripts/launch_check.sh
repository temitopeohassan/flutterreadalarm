#!/usr/bin/env bash
# Installs an APK on the running emulator, opens ReadAlarm, and fails if it
# isn't still running after a while. Prints the crash from logcat if any.
#   launch_check.sh <apk> <label> [seconds]
set -u
apk=$1
label=$2
wait=${3:-30}
pkg=com.readalarm.readalarm

echo "::group::$label: install"
adb uninstall "$pkg" >/dev/null 2>&1 || true
adb install "$apk"
echo "::endgroup::"

adb logcat -c
adb shell monkey -p "$pkg" -c android.intent.category.LAUNCHER 1 >/dev/null
sleep "$wait"

mkdir -p logcat
adb logcat -d > "logcat/$label.txt"
pid=$(adb shell pidof "$pkg" | tr -d '\r')
adb exec-out screencap -p > "logcat/$label.png" || true

if grep -q "FATAL EXCEPTION" "logcat/$label.txt" || [ -z "$pid" ]; then
  echo "::error::$label: ReadAlarm crashed or closed"
  grep -n -A80 -E "FATAL EXCEPTION|Abort message|backtrace:" "logcat/$label.txt" | head -300
  echo "--- ReadAlarm log ---"
  grep -n -i -E "flutter|readalarm|AndroidRuntime|Ads|Billing" "logcat/$label.txt" | tail -150
  exit 1
fi
echo "$label: ReadAlarm still running after ${wait}s (pid $pid)"
grep -n -i -E "flutter.*(error|exception)" "logcat/$label.txt" | head -40 || true
