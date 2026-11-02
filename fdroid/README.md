# F-Droid build recipe

`com.roshangupta.echoes.yml` is the build recipe for F-Droid's data repository
(https://gitlab.com/fdroid/fdroiddata). It goes in `metadata/com.roshangupta.echoes.yml` there.

F-Droid builds everything from source, including the engine:
1. The Godot 4.7.2-stable editor (`linuxbsd`, used headless for the export) and the Android
   release template (arm64), from the `godot` srclib at the 4.7.2-stable commit.
2. The game is exported unsigned (`package/signed=false`, set by the prebuild step) to `echoes.apk`.
   F-Droid signs it with its own key.

## Releasing a new version
1. Bump `version/code` and `version/name` in `export_presets.cfg`.
2. Add `fastlane/metadata/android/en-US/changelogs/<versionCode>.txt`.
3. Commit, then tag `v<versionName>` (for example `v1.6`) and push the tag.
F-Droid's update checker reads the tags and `export_presets.cfg` (see `UpdateCheckData`).

## Engine version
If the game moves to a newer Godot, update the srclib commit, the templates folder name
(`4.7.2.stable`) and `ndk` (from Godot's `platform/android/java/app/config.gradle`, `ndkVersion`).
