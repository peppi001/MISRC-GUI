#!/usr/bin/env bash
# Android CI smoke test: install APK, launch NativeActivity, check that it stays alive.
# No USB device or remote monitor server is required or simulated here.
set -Eeuo pipefail

PACKAGE=dev.misrc.gui
ACTIVITY=dev.misrc.gui.MainActivity
LOG_DIR="${TEST_LOG_DIR:-$PWD/.ci-artifacts/emulator-logs}"
mkdir -p "$LOG_DIR"

collect_logs() {
  result=$?
  echo "Smoke test exit code: $result" > "$LOG_DIR/result.txt"
  if command -v adb >/dev/null 2>&1; then
    adb logcat -d -v threadtime > "$LOG_DIR/logcat.txt" 2>&1 || true
    adb shell dumpsys activity activities > "$LOG_DIR/activities.txt" 2>&1 || true
    adb shell dumpsys package "$PACKAGE" > "$LOG_DIR/package.txt" 2>&1 || true
    adb shell screencap -p /sdcard/misrc-test.png >/dev/null 2>&1 && \
      adb pull /sdcard/misrc-test.png "$LOG_DIR/screen.png" >/dev/null 2>&1 || true
  fi
  if (( result != 0 )); then
    echo "FAILED: installation, launch, permission, or liveness check. See emulator log artifact." >&2
  fi
}
trap collect_logs EXIT

APK="$(find .ci-artifacts/android-emulator-apk -maxdepth 1 -name '*_x86_64.apk' -print -quit)"
[[ -n "$APK" && -s "$APK" ]] || { echo 'Missing x86_64 APK!' >&2; exit 1; }

adb wait-for-device
adb shell getprop ro.build.version.release | tr -d '\r' | tee "$LOG_DIR/android-version.txt"
ACTUAL_API="$(adb shell getprop ro.build.version.sdk | tr -d '\r')"
echo "API=$ACTUAL_API expected=$EXPECTED_API" | tee "$LOG_DIR/api.txt"
[[ "$ACTUAL_API" == "$EXPECTED_API" ]] || { echo 'Wrong emulator API' >&2; exit 1; }

# Refuse accidental ARM emulator tests or incompatible system images.
EMU_ABIS="$(adb shell getprop ro.product.cpu.abilist | tr -d '\r')"
echo "Emulator ABIs: $EMU_ABIS" | tee "$LOG_DIR/abi.txt"
[[ ",$EMU_ABIS," == *",x86_64,"* ]] || { echo 'Emulator lacks x86_64 ABI' >&2; exit 1; }

# Fresh system image. If APK is malformed/missing symbols, this must fail.
adb install -r -t "$APK" | tee "$LOG_DIR/install.txt"
adb shell pm path "$PACKAGE" | tee "$LOG_DIR/apk-path.txt" | grep -q 'package:'

# Both permissions must be present and granted (these are normal permissions).
adb shell dumpsys package "$PACKAGE" > "$LOG_DIR/package-before-launch.txt"
for permission in INTERNET ACCESS_NETWORK_STATE; do
  grep -Eq "android.permission.${permission}: granted=true" "$LOG_DIR/package-before-launch.txt" || {
    echo "Permission $permission not granted/visible in dumpsys package" >&2
    exit 1
  }
done

adb logcat -c
adb shell am start -W -n "$PACKAGE/$ACTIVITY" | tee "$LOG_DIR/launch.txt"
# A NativeActivity that immediately crashes with JNI/EGL/ELF errors will be gone.
sleep 12
PID="$(adb shell pidof "$PACKAGE" 2>/dev/null | tr -d '\r' || true)"
echo "PID=$PID" | tee "$LOG_DIR/pid.txt"
[[ "$PID" =~ ^[0-9]+$ ]] || { echo 'MISRC process not alive after launch' >&2; exit 1; }

# Check that the activity is still the resumed foreground application.
adb shell dumpsys activity activities > "$LOG_DIR/activity-post-launch.txt"
if ! grep -Eq '(mResumedActivity|topResumedActivity|ResumedActivity|resumed=true).*dev\.misrc\.gui' "$LOG_DIR/activity-post-launch.txt"; then
  echo 'WARNING: could not confirm resumed window from dumpsys; process is alive.'
fi

echo "PASS: Android API $ACTUAL_API, APK installed, native process running, INTERNET + ACCESS_NETWORK_STATE granted" | tee "$LOG_DIR/pass.txt"
