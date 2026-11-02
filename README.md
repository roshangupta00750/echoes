# ECHOES

**Every level, your past runs come back as echoes. Don't touch them.**

https://github.com/user-attachments/assets/8a606bdb-8be3-43f7-bf5d-d86016d37bb1

*A full run on Normal, up to level 7 (1:36, with sound), recorded on an Android phone.*

## Download

**[⬇ Download ECHOES for Android (APK)](https://github.com/roshangupta00750/echoes/releases/latest/download/echoes.apk)**: one click and the file downloads.

- Every version, with release notes: **[Releases](https://github.com/roshangupta00750/echoes/releases)**
- **iPhone / iPad:** not on the App Store. You install it yourself from a Mac or a Windows PC with your free Apple ID. See [Install on iPhone or iPad](#install-on-iphone-or-ipad).
- Coming soon on **F-Droid**.
- Needs Android 7.0 or newer (64-bit / arm64, which is almost every phone from the last few years).

## Install the APK

### On your phone (easiest)
1. On the phone, open the **Download** link above.
2. Tap the downloaded **echoes.apk**, in the notification or in your *Files / Downloads* app.
3. Android asks to allow installs from this source the first time. Tap **Settings** → turn on **Allow from this source** → go back.
4. Tap **Install**, then **Open**.

If you already have an older test build of ECHOES that was signed differently, Android says *"App not installed"*.
Uninstall the old one first.

### From a computer, over USB
First, on the phone: **Settings → About phone → tap "Build number" 7 times**, then
**Settings → Developer options → turn on USB debugging**. Plug the phone in and tap **Allow** when it asks.

**Mac** (Terminal):
```bash
brew install android-platform-tools        # needs Homebrew: https://brew.sh
cd ~/Downloads
adb devices                                # your phone should be listed as "device"
adb install -r echoes.apk
```

**Windows** (PowerShell):
```powershell
winget install Google.PlatformTools
# close and reopen PowerShell, then:
cd $HOME\Downloads
adb devices
adb install -r echoes.apk
```

**Linux** (Debian / Ubuntu; on Fedora use `sudo dnf install android-tools`):
```bash
sudo apt install adb
cd ~/Downloads
adb devices
adb install -r echoes.apk
```

## Install on iPhone or iPad
ECHOES isn't on the App Store, and Apple doesn't allow installing an app file straight onto an iPhone the way an APK
goes onto Android. Instead you plug the iPhone or iPad into a computer once and install the game from there.
It's signed with **your own Apple ID**, and the free one you already use for the App Store and iCloud is enough.
You don't need to pay for anything.

**What you need**
- An iPhone or iPad on iOS / iPadOS 14 or newer
- A USB cable for it
- A Mac (way A, below) or a Windows PC (way B). Way B also works on a Mac without Xcode.
- Your Apple ID and password

**Good to know before you start**
- With a free Apple ID the game runs for **7 days**. After that it won't open until you plug in and install again.
  That takes a minute, and your progress, medals and best scores are kept.
- A free Apple ID can have at most 3 self-installed apps on a device at the same time.

### Step 1: get the device ready (once)
1. Unlock the iPhone/iPad and plug it into the computer. When it asks **Trust This Computer?**, tap **Trust** and enter your passcode.
2. On iOS 16 or newer, turn on **Developer Mode**: **Settings → Privacy & Security → Developer Mode → On**. The device restarts. After it restarts, tap **Turn On** and enter your passcode.
   If you don't see *Developer Mode* in that menu yet, do way A or B below first. The option appears after the first install try.
   Then turn it on and run the install again.

### Way A: from a Mac with Xcode
1. Install **Xcode** from the Mac App Store. It's free but large, so give it a while. Open it once and let it finish installing its components.
2. In Xcode: **Xcode → Settings → Accounts → +** at the bottom left **→ Apple ID**, and sign in.
3. From the [latest release](https://github.com/roshangupta00750/echoes/releases/latest), download
   **ECHOES-ios-project.tgz** and **install-on-iphone.command**. Leave both in your **Downloads** folder.
4. Plug in the iPhone/iPad and keep it unlocked. Open **Terminal** (press ⌘ Space and type *Terminal*) and run:
   ```bash
   cd ~/Downloads
   bash install-on-iphone.command
   ```
   The script builds the game, signs it with your Apple ID and installs it. The first build takes a few minutes.
   When it says **RESULT: INSTALLED**, the game is on your home screen. If something is missing, the script stops
   and says what to fix (no Xcode, not signed in, device not found). It keeps its files in an `ECHOES-ios` folder next to it, and a full log in `ECHOES-ios-install-log.txt`.
5. Continue with [Step 2](#step-2-trust-the-app-once).

### Way B: from Windows, or a Mac without Xcode (Sideloadly)
1. **On Windows only:** install **iTunes** and **iCloud for Windows** from Apple's website (apple.com), not from the
   Microsoft Store. Sideloadly needs Apple's own versions to see the device.
2. Install **Sideloadly** from <https://sideloadly.io>.
3. Download **ECHOES.ipa** from the [latest release](https://github.com/roshangupta00750/echoes/releases/latest).
4. Plug in the iPhone/iPad, unlock it, and open Sideloadly. Your device should appear at the top.
5. Drag **ECHOES.ipa** into Sideloadly, type your Apple ID in the *Apple account* box, and press **Start**.
   Enter your Apple ID password when asked, and the code Apple sends if you use two-factor sign-in.
6. Wait for **Done**. Then continue with Step 2.

### Step 2: trust the app (once)
The first time you tap **ECHOES** on the home screen, iOS says *"Untrusted Developer"*. Fix that once:
**Settings → General → VPN & Device Management** → tap your Apple ID under *Developer App* → **Trust**.
Now open ECHOES. The device needs to be online for this one check.

### Every 7 days (free Apple ID)
When ECHOES stops opening, plug in and do way A step 4, or way B steps 4–6, again. You don't need to redo
Step 1 or Step 2. Your progress stays on the device.

### Updating to a new version
Delete the old **ECHOES-ios-project.tgz** / **ECHOES.ipa** from Downloads first. Otherwise the browser saves the new
one as *"… (1)"*. Then download the new files from the latest release and install the same way, right over the old
version. Your progress is kept. Use the same way (A or B) each time: the two install the game under different
names, so switching gives you a second copy with its own progress.

### On the iPhone or iPad
- **Controls:** touch, tilt and tilt + touch all work. If tilt feels wrong, use **SETTINGS → CALIBRATE TILT**.
- **LAN games:** iOS asks *"ECHOES would like to find devices on your local network"* the first time. Tap **Allow**,
  or the game can't see or host LAN games. You can change it later in **Settings → Privacy & Security → Local Network**.
  If a host still isn't listed, use **ENTER ADDRESS** with the address shown on the host's screen.
  iPhones, iPads and Android phones can all play together on the same Wi-Fi, as long as everyone has the same version.
- **Sharing a score:** **SHARE** opens the iOS share menu with your score card and a line of text, ready for
  WhatsApp, Instagram, Messages or *Save Image*.

### If something goes wrong
| What you see | What to do |
|---|---|
| *Untrusted Developer* | Step 2 above |
| *Unable to Verify App* | Connect the device to the internet and open ECHOES again |
| ECHOES stopped opening after a week | The 7-day free signing ran out. Install again (see *Every 7 days*) |
| *Developer Mode required* | Step 1, item 2 |
| Mac script says *NO_DEVICE* | Unlock the device, replug the cable, tap Trust, check Developer Mode is on |
| Mac script says *NO_APPLE_ID* | Sign in under Xcode → Settings → Accounts, then run it again |
| Sideloadly: *maximum number of apps* | A free Apple ID allows 3 self-installed apps. Delete one you don't use and try again |
| Sideloadly doesn't see the device (Windows) | Install iTunes and iCloud from Apple's website, not the Microsoft Store, and replug |

## Features
- **Modes:** Normal, Hard and Extreme. In Extreme the newest echo hunts you and shards drift if you wait. Each mode opens by clearing level 6 of the one before.
- **Goals:** a Daily Run with the same start for everyone and a daily streak, 14 missions, bronze/silver/gold medals at levels 5/10/15, and unlockable trails and echo colours.
- **Fair deaths:** safe spawns, rings on resting echoes, path previews at 3-2-1, and a replay of the past self that caught you.
- **LAN multiplayer** on the same Wi-Fi or hotspot: everyone's runs become echoes for everyone. Get caught and you come back as a **zombie** that hunts the living. Last human standing wins.
- **Controls:** touch (a floating stick), tilt, or tilt to steer and touch to go, with a 3-step tilt calibration.
- **Sharing:** a 1080×1080 score card that draws every one of your past runs, shared through the phone's share menu (Android, iPhone and iPad).
- No ads, no accounts, no analytics, no tracking.

## Run it from the source code (for players, forks and contributors)

### 1. Get the code
Fork the repository on GitHub (the **Fork** button, top right) if you want your own copy to change, then:
```bash
git clone https://github.com/roshangupta00750/echoes.git     # or your fork's URL
cd echoes
```
No git? Use **Code → Download ZIP** on the GitHub page and unzip it.

### 2. Install Godot 4.7.2
ECHOES is made with **Godot 4.7.2 (standard, not .NET)**. Download it from
<https://github.com/godotengine/godot/releases/tag/4.7.2-stable>:

| System  | File to download | How to start it |
|---|---|---|
| Mac     | `Godot_v4.7.2-stable_macos.universal.zip` | unzip, move **Godot.app** to Applications, open it |
| Windows | `Godot_v4.7.2-stable_win64.exe.zip` | unzip, run `Godot_v4.7.2-stable_win64.exe` |
| Linux   | `Godot_v4.7.2-stable_linux.x86_64.zip` | unzip, `chmod +x Godot_v4.7.2-stable_linux.x86_64`, run it |

### 3. Play it on your computer
In Godot: **Import** → choose the `echoes` folder (its `project.godot`) → **Import & Edit** → press **F5** (▶ Play).
Use the mouse or WASD / arrow keys to move, Enter to start, Esc to pause.

Or from a terminal, inside the `echoes` folder:
```bash
# Mac
/Applications/Godot.app/Contents/MacOS/Godot --path .
# Windows (PowerShell)
& "C:\path\to\Godot_v4.7.2-stable_win64.exe" --path .
# Linux
~/Godot_v4.7.2-stable_linux.x86_64 --path .
```

### 4. Build your own APK
You need, once:
- **Godot's export templates:** in Godot, **Editor → Manage Export Templates → Download and Install**.
- **Java 17** and the **Android SDK**. The simplest way on every system is to install [Android Studio](https://developer.android.com/studio), open **More Actions → SDK Manager**, and install *Android SDK Platform 36*, *Build-Tools 36* and *Platform-Tools*. Or, without Android Studio:
  - Mac: `brew install openjdk@17 && brew install --cask android-commandlinetools && sdkmanager "platform-tools" "platforms;android-36" "build-tools;36.1.0"`
  - Windows: `winget install EclipseAdoptium.Temurin.17.JDK`, then [command-line tools](https://developer.android.com/studio#command-line-tools-only) and the same `sdkmanager` line
  - Linux: `sudo apt install openjdk-17-jdk`, then [command-line tools](https://developer.android.com/studio#command-line-tools-only) and the same `sdkmanager` line
- In Godot: **Editor → Editor Settings → Export → Android**: set **Java SDK Path** and **Android SDK Path**. Godot normally creates a debug signing key for you (it uses Java's `keytool`).

Then **Project → Export… → Android → Export Project** (untick *Export With Debug* for a release). Or from a terminal:
```bash
# Mac
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --export-debug Android build/echoes.apk
# Windows (PowerShell; the _console.exe prints progress)
& "C:\path\to\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --export-debug Android build\echoes.apk
# Linux
~/Godot_v4.7.2-stable_linux.x86_64 --headless --path . --export-debug Android build/echoes.apk
```
The APK lands in `build/echoes.apk`. Install it with the `adb install -r` commands above.

For a **release** build signed with your own key, set these three environment variables and use `--export-release` instead of `--export-debug`:
`GODOT_ANDROID_KEYSTORE_RELEASE_PATH`, `GODOT_ANDROID_KEYSTORE_RELEASE_USER`, `GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD`.

### 5. Build for iPhone / iPad from source (Mac)
In Godot, **Project → Export… → iOS → Export Project**. The preset already has *Export Project Only* on and exports an
Xcode project into `build/ios/`. Then, with the iPhone plugged in:
```bash
bash tools/ios/install-on-iphone.command      # builds, signs with your Apple ID, installs
bash tools/ios/make-ipa.command               # or: an unsigned ECHOES.ipa for Sideloadly
```

### Test flags
User arguments go after `--`, for example `Godot --path . -- --autoplay --mode=hard`:
- `--autoplay [--mode=normal|hard|extreme]`: a bot plays and prints its result
- `--host --players=N` / `--join=IP`: LAN bots
- `--shot=PATH --shot_at=SECONDS --quit_after_shot`: take a screenshot

## Project layout
- `scripts/game.gd`: the rules, the echoes, zombies and drawing
- `scripts/main.gd`: menus, HUD, flow, saves, daily/missions/medals, controls, sharing, the LAN lobby
- `scripts/net.gd`: ENet host/join and LAN discovery (UDP broadcast)
- `scripts/art.gd`, `scripts/sound.gd`: pixel text and audio playback
- `shaders/crt.gdshader`: the CRT look
- `assets/`: fonts, icon layers, audio
- `tools/`: scripts that generate the audio, the icon and the store images
- `fastlane/`: the store listing (texts and screenshots) that F-Droid reads
- `fdroid/`: the F-Droid build recipe (see `fdroid/README.md`)

## License
- Code: [Apache License 2.0](LICENSE) (see also [NOTICE](NOTICE))
- Art and audio (everything in `assets/`, and the store images): [CC BY-SA 4.0](LICENSE-ASSETS.md)
- Built with [Godot Engine](https://godotengine.org) (MIT)

## Privacy
ECHOES has no ads, no accounts, no analytics and no tracking. The network permissions are used only for
LAN games on your own Wi-Fi or hotspot. Your progress stays on your phone.

## Author
Roshan Kumar Gupta
