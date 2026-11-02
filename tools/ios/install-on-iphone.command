#!/bin/bash
# ECHOES for iPhone / iPad: builds the game with Xcode, signs it with YOUR Apple ID (a free one is fine),
# and installs it on the iPhone or iPad plugged into this Mac. Double-click to run.
#
# One-time setup:
#   1. Install Xcode from the Mac App Store and open it once (accept the license).
#   2. Xcode > Settings > Accounts > "+" > Apple ID: sign in.
#   3. Plug in the iPhone/iPad, unlock it, tap "Trust This Computer".
#   4. On the iPhone/iPad: Settings > Privacy & Security > Developer Mode > On (it restarts).
# With a free Apple ID the app works for 7 days; run this again to renew it.

cd "$(dirname "$0")"
exec > >(tee ios-install-log.txt) 2>&1
echo "ECHOES iOS installer: $(date)"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fail() { echo; echo "RESULT: $1"; echo "$2"; read -t 120 -p "Press Enter to close"; exit 1; }

[ -d "$DEVELOPER_DIR" ] || fail NO_XCODE "Install Xcode from the Mac App Store, open it once, then run this again."
xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1 || fail XCODE_FIRST_LAUNCH "Open Xcode once and let it finish installing its components, then run this again."

# the Xcode project: next to this script (from the GitHub release), or exported by Godot into build/ios
PROJ=ios
if [ ! -d ios/ECHOES.xcodeproj ]; then
  if [ -f ECHOES-ios-project.tgz ]; then
    echo "Unpacking the Xcode project..."; tar xzf ECHOES-ios-project.tgz || fail NO_PROJECT "Could not unpack ECHOES-ios-project.tgz."
  elif [ -d ../../build/ios/ECHOES.xcodeproj ]; then
    PROJ=../../build/ios
  else
    fail NO_PROJECT "Put ECHOES-ios-project.tgz (from the GitHub release) next to this script, or export the iOS preset from Godot first."
  fi
fi

# your Apple ID's team (Xcode > Settings > Accounts)
TEAM=$(defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier 2>/dev/null | grep -m1 -E 'teamID' | sed -E 's/.*= *"?([A-Z0-9]{10})"?;.*/\1/')
[ -z "$TEAM" ] && TEAM=$(defaults read com.apple.dt.Xcode IDEProvisioningTeams 2>/dev/null | grep -m1 -E 'teamID' | sed -E 's/.*= *"?([A-Z0-9]{10})"?;.*/\1/')
if [ -z "$TEAM" ]; then
  open -a Xcode
  fail NO_APPLE_ID "In Xcode: Settings > Accounts > + > Apple ID, sign in, then run this again."
fi
echo "Apple team: $TEAM"
# a bundle id of your own, so nobody's free account collides with anyone else's
BUNDLE="com.roshangupta.echoes.$(echo "$TEAM" | tr 'A-Z' 'a-z')"
echo "Bundle id: $BUNDLE"

# the plugged-in iPhone / iPad
xcrun devicectl list devices --json-output /tmp/echoes_devices.json >/dev/null 2>&1
DEV=$(/usr/bin/python3 - <<'PY'
import json
try:
    d = json.load(open("/tmp/echoes_devices.json"))
    for dev in d.get("result", {}).get("devices", []):
        hw = dev.get("hardwareProperties", {}); cp = dev.get("connectionProperties", {})
        if hw.get("platform") == "iOS" and cp.get("pairingState") == "paired" and cp.get("tunnelState") != "unavailable":
            print(dev.get("identifier")); break
except Exception:
    pass
PY
)
[ -z "$DEV" ] && fail NO_DEVICE "Plug in the iPhone/iPad, unlock it, tap Trust, turn on Developer Mode (Settings > Privacy & Security), then run this again."
echo "Device: $DEV"

echo "--- building (the first time takes a few minutes)..."
xcodebuild -project "$PROJ/ECHOES.xcodeproj" -scheme ECHOES -configuration Release \
  -destination generic/platform=iOS -derivedDataPath build \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
  DEVELOPMENT_TEAM="$TEAM" PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE" \
  CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="Apple Development" build 2>&1 | tail -25
APP=build/Build/Products/Release-iphoneos/ECHOES.app
[ -d "$APP" ] || fail BUILD_FAILED "The build failed: the lines above say why. ios-install-log.txt has everything."

echo "--- installing on the device..."
xcrun devicectl device install app --device "$DEV" "$APP" || fail INSTALL_FAILED "Keep the device unlocked and plugged in, then run this again."
echo "RESULT: INSTALLED"
if ! xcrun devicectl device process launch --device "$DEV" "$BUNDLE" >/dev/null 2>&1; then
  echo "First time only: on the iPhone/iPad open Settings > General > VPN & Device Management,"
  echo "tap your Apple ID under Developer App, tap Trust. Then open ECHOES from the home screen."
fi
echo "DONE. With a free Apple ID, ECHOES keeps working for 7 days; run this again to renew it."
read -t 60 -p "Press Enter to close"
