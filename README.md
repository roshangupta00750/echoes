# ECHOES

A retro neon arcade game for Android, made with Godot 4.7.

Every level you grab 5 gold shards before the clock runs out. Then your run comes back: an **echo** that replays exactly what you did. Touch a moving echo and you're out. Level 10 means dodging nine of yourself.

## Features
- **Modes:** Normal, Hard and Extreme (Extreme has a hunter echo that leans toward you, and drifting shards). Each mode opens by clearing level 6 of the one before.
- **Goals:** a Daily Run with the same start for everyone and a streak, 14 missions, bronze/silver/gold medals at levels 5/10/15, and unlockable trails and echo colours.
- **Fairness:** safe spawns, wait-rings on resting echoes, path previews at 3-2-1, and a death replay that shows which past self caught you.
- **LAN multiplayer** on the same Wi-Fi or hotspot: everyone's runs become echoes for everyone. Anyone caught comes back as a **zombie** and hunts the living. Last human standing wins.
- **Controls:** touch (floating stick), tilt, or tilt + touch, with a 3-step tilt calibration.
- **Sharing:** a 1080×1080 score card showing every one of your past runs, shared through the Android share sheet.

## Project layout
- `scripts/game.gd`: the rules, the echoes, zombies and drawing
- `scripts/main.gd`: menus, HUD, flow, saves, daily/missions/medals, controls, sharing, LAN lobby
- `scripts/net.gd`: ENet host/join and LAN discovery (UDP broadcast)
- `scripts/art.gd`, `scripts/sound.gd`: pixel text and procedural audio playback
- `shaders/crt.gdshader`: the CRT look
- `assets/`: fonts, icon layers, audio
- `tools/`: scripts that generate the audio, the icon and the store images

## Running
Open the folder in Godot 4.7 (GL Compatibility). Android export needs the Android SDK; see `export_presets.cfg`.

Test flags (user args after `--`):
- `--autoplay [--mode=normal|hard|extreme]`
- `--host --players=N` / `--join=IP`
- `--shot=PATH --shot_at=SECONDS --quit_after_shot`

## License
- Code: [MIT](LICENSE)
- Art and audio (everything in `assets/`, and the store images): [CC BY-SA 4.0](LICENSE-ASSETS.md)
- Built with [Godot Engine](https://godotengine.org) (MIT)

## Privacy
ECHOES has no ads, no accounts, no analytics and no tracking. The network permissions are used only for
LAN games on your own Wi-Fi/hotspot. Your progress stays on your phone.

## Author
Roshan Kumar Gupta
