#!/bin/bash
# Builds an UNSIGNED ECHOES.ipa for sideloading tools such as Sideloadly (Mac or Windows),
# which sign it with the player's own Apple ID when they install it. Needs Xcode on this Mac.
cd "$(dirname "$0")"
exec > >(tee ipa-log.txt) 2>&1
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
PROJ=ios
if [ ! -d ios/ECHOES.xcodeproj ]; then
  if [ -f ECHOES-ios-project.tgz ]; then tar xzf ECHOES-ios-project.tgz; elif [ -d ../../build/ios/ECHOES.xcodeproj ]; then PROJ=../../build/ios; bash add-native-share.sh "$PROJ"; fi
fi
xcodebuild -project "$PROJ/ECHOES.xcodeproj" -scheme ECHOES -configuration Release \
  -destination generic/platform=iOS -derivedDataPath build-unsigned \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build 2>&1 | tail -15
APP=build-unsigned/Build/Products/Release-iphoneos/ECHOES.app
[ -d "$APP" ] || { echo "RESULT: BUILD_FAILED"; read -t 60 -p "Press Enter"; exit 1; }
rm -rf Payload && mkdir Payload && cp -R "$APP" Payload/ && rm -f ECHOES.ipa && zip -qry ECHOES.ipa Payload && rm -rf Payload
ls -la ECHOES.ipa && echo "RESULT: IPA_READY"
read -t 60 -p "Press Enter to close"
