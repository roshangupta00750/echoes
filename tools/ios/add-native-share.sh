#!/bin/bash
# Adds the iOS share sheet to an Xcode project exported by Godot: bash add-native-share.sh path/to/ios
# Safe to run more than once.
set -e
D="$1/ECHOES"; N="$(cd "$(dirname "$0")" && pwd)/native"
[ -f "$D/dummy.swift" ] || { echo "no Godot iOS project at $1"; exit 1; }
grep -q echoes_share_boot "$D/dummy.swift" || { echo; cat "$N/EchoesShare.swift"; } >> "$D/dummy.swift"
grep -q echoes_share_boot "$D/dummy.cpp" || { echo; cat "$N/boot.cpp"; } >> "$D/dummy.cpp"
# saving the picture to Photos from the share sheet needs this line in Info.plist
P="$D/ECHOES-Info.plist"
if ! grep -q NSPhotoLibraryAddUsageDescription "$P"; then
  if [ -x /usr/libexec/PlistBuddy ]; then
    /usr/libexec/PlistBuddy -c "Add :NSPhotoLibraryAddUsageDescription string Saves your ECHOES score card to Photos." "$P"
  else
    python3 -c "import plistlib,sys; p=sys.argv[1]; d=plistlib.load(open(p,'rb')); d['NSPhotoLibraryAddUsageDescription']='Saves your ECHOES score card to Photos.'; plistlib.dump(d,open(p,'wb'))" "$P"
  fi
fi
echo "share sheet added"
