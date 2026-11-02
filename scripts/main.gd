extends Node2D
## ECHOES. Menu -> solo, or a LAN match (host or join) -> levels -> results.
## Controls (settings): TOUCH (drag anywhere), TILT (tilt the phone), TILT + HOLD (tilt to steer, hold a finger to go).
## Keys on a computer: WASD/arrows, Enter, Esc, M mute.

var game: EchoGame
var sound: Sound
var net: Net
var ui_layer: CanvasLayer
var ui: Node2D
var crt_layer: CanvasLayer
var crt: ColorRect
var cmat: ShaderMaterial
var screen := "title"        # title, settings, join, keypad, lobby, play, paused, over
var stick_on := false
var stick_o := Vector2.ZERO
var stick_p := Vector2.ZERO
var stick_r := 22.0           # how far the thumb moves for full speed, in game pixels: about 7 mm on any screen
var stick_id := -1
var touches := {}            # finger index -> position (TILT + HOLD: any finger down means go)
var save := {"best": 0, "best_level": 0, "sound": true, "plays": 0, "control": "touch", "sens": 1, "flip_x": false, "flip_y": false, "last_ip": "",
	"mode": "normal", "unl_hard": false, "unl_extreme": false, "crt": true, "name": "",
	"stats": {}, "missions": [], "streak": 0, "best_streak": 0, "daily_day": 0, "daily_best": 0}
var over_at := 0.0
const REPLAY := 1.0          # solo: the death replay plays this long before the results come up
var t_ui := 0.0
var args := {}
var view := Vector2(384, 216)
var ui_oy := 0.0            # on screens taller than 16:9 (iPad, 4:3) the interface sits in a centred 216 px band
var buttons: Array = []      # [Rect2, Callable] rebuilt every frame by the screen being drawn
var new_best := false
var just_unlocked := ""      # "hard" / "extreme": unlocked during the run that just ended
var mp_mode := "normal"      # the mode the host picked for the LAN match
var sharing := false         # true for the frames the share card is captured: the card is drawn instead of the screen
var daily_run := false       # this solo run is today's daily run
var hud_score := 0
var safe_l := 0.0            # notch / rounded corners, in game pixels: the HUD keeps clear of them
var safe_r := 0.0
var card_tex: ImageTexture   # iOS: the share card shown full-screen to screenshot
var card_open := false
var card_at := 0.0
var hud_got := 0
var pip_pop := 0.0
var score_pop := 0.0
var toast := ""              # missions completed: a gold box at the top
var toast_t := 0.0
var run_close := 0           # close calls this run, for the missions
var run_start_level := 0     # the mode's best level when this run began: medals won mid-run
var over_tip := TIPS[0]
var name_edit: LineEdit
const UNLOCK_AT := 6         # clear this level to open the next mode
const STORE_LINK := ""       # the Play Store link, once there is one: added to shared scores
# medals: reach these levels in a mode
const MEDALS := [[5, "BRONZE", Color(0.85, 0.52, 0.28)], [10, "SILVER", Color(0.82, 0.86, 0.95)], [15, "GOLD", Color(1.0, 0.8, 0.25)]]
# looks you unlock: [id, name, what opens it]
const TRAILS := [["classic", "CLASSIC", ""], ["spark", "SPARK", "HARD BRONZE"], ["rainbow", "RAINBOW", "10 MISSIONS"], ["gold", "GOLD", "GOLD MEDAL"]]
const PALETTES := [["neon", "NEON", ""], ["sunset", "SUNSET", "5 MISSIONS"], ["violet", "VIOLET", "NORMAL SILVER"]]
const PALETTE_COLS := {
	"neon": [Color(1.0, 0.25, 0.7), Color(1.0, 0.5, 0.1), Color(0.62, 0.38, 1.0), Color(0.55, 1.0, 0.25), Color(1.0, 0.3, 0.3), Color(0.3, 0.45, 1.0), Color(1.0, 0.62, 0.55), Color(0.88, 0.45, 1.0)],
	"sunset": [Color(1, 0.3, 0.45), Color(1, 0.45, 0.15), Color(0.95, 0.2, 0.6), Color(1, 0.6, 0.45), Color(0.85, 0.3, 0.85), Color(1, 0.3, 0.25), Color(0.75, 0.2, 0.45), Color(1, 0.45, 0.75)],
	"violet": [Color(0.62, 0.38, 1), Color(0.88, 0.45, 1), Color(0.45, 0.35, 1), Color(1, 0.35, 0.85), Color(0.72, 0.58, 1), Color(0.5, 0.5, 1), Color(0.96, 0.62, 1), Color(0.75, 0.3, 0.92)]}
# what to learn, shown one at a time on the results screen
const TIPS := ["KEEP YOUR PATH SHORT AND TIDY: EVERY MOVE COMES BACK.",
	"ECHOES WAIT WHERE THEIR RUN STARTED.  WATCH THEIR RINGS RUN OUT.",
	"AT 3-2-1, THE DOTS SHOW WHERE EACH ECHO GOES FIRST.",
	"BRUSH PAST AN ECHO AND OUT AGAIN FOR CLOSE-CALL POINTS.",
	"A FAST LEVEL MEANS A SHORT ECHO, AND MORE TIME BONUS.",
	"CIRCLES COME BACK AS CIRCLES.  ZIGZAGS COME BACK AS ZIGZAGS."]
const MISSIONS := [
	["first", "FIRST STEPS", "CLEAR LEVEL 3"],
	["five", "FIVE OF YOU", "CLEAR LEVEL 5"],
	["ten", "TEN OF YOU", "CLEAR LEVEL 10"],
	["thread", "THREAD NEEDLES", "5 CLOSE CALLS/RUN"],
	["dare", "DAREDEVIL", "15 CLOSE CALLS/RUN"],
	["quick", "QUICK HANDS", "CLEAR WITH 7S LEFT"],
	["hard5", "HARD WON", "LEVEL 5 ON HARD"],
	["ext5", "EXTREMIST", "LEVEL 5, EXTREME"],
	["collect", "COLLECTOR", "500 SHARDS"],
	["regular", "REGULAR", "PLAY 25 RUNS"],
	["daily", "DAILY HABIT", "3-DAY STREAK"],
	["party", "PARTY", "LAN, 3+ PLAYERS"],
	["winner", "SURVIVOR", "WIN A LAN MATCH"],
	["share", "SHOW OFF", "SHARE A SCORE"]]
var tip := ""
var tip_t := 0.0
var msg := ""
var msg_t := 0.0
# multiplayer
var roster: Array = []       # [[id, name]], the host's order
var mp_seed := 0
var snap_acc := 0.0
var sent_runs_ver := -1
var keypad_ip := ""
var joining_ip := ""
var join_at := 0.0
# tilt
var tilt_zero := Vector3.ZERO
var tilt_have := false
var tilt_dir := Vector2.ZERO

class Layer extends Node2D:
	var f: Callable
	func _draw() -> void: f.call(self)

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_load()
	sound = Sound.new(); add_child(sound); sound.set_on(bool(save.get("sound", true)))
	net = Net.new(); add_child(net)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func(): _note("COULD NOT CONNECT TO " + joining_ip); _go_join())
	multiplayer.server_disconnected.connect(func(): _note("THE HOST LEFT"); net.close(); _title())
	ui_layer = CanvasLayer.new(); ui_layer.layer = 30; add_child(ui_layer)   # above the CRT: text stays crisp
	ui = Layer.new(); ui.f = _draw_ui; ui_layer.add_child(ui)
	crt_layer = CanvasLayer.new(); crt_layer.layer = 20; add_child(crt_layer)
	crt = ColorRect.new(); crt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cmat = ShaderMaterial.new(); cmat.shader = load("res://shaders/crt.gdshader"); crt.material = cmat
	crt_layer.add_child(crt)
	crt.visible = bool(save.get("crt", true))
	_title()
	# already on a tilt control from an earlier version, but never calibrated: do it now
	if save["control"] != "touch" and not save.has("tilt_r") and args.is_empty(): _go_calib("title")
	# tests: --autoplay (solo bot), --host (bot host, starts when --players joined), --join=IP (bot client)
	if args.has("autoplay"): _start_solo()
	if args.has("host"): _host()
	if args.has("join"): _join(String(args["join"]))
	if args.has("listen_test"):
		_go_join()
		get_tree().create_timer(3.5).timeout.connect(func(): print("FOUND HOSTS ", net.hosts.keys()); get_tree().quit())

func _load() -> void:
	# the save, or if that is missing or broken, the backup
	for path in ["user://save.json", "user://save.json.bak"]:
		if not FileAccess.file_exists(path): continue
		var d = JSON.parse_string(FileAccess.get_file_as_string(path))
		if d is Dictionary:
			for k in d: save[k] = d[k]
			break
	# 1.2.2 turned the tilt the right way round: earlier flip choices would now reverse it again
	if int(save.get("tilt_v", 1)) < 2:
		save["flip_x"] = false; save["flip_y"] = false; save["tilt_v"] = 2
	# 1.1 kept one best: it was a NORMAL best
	if not save.has("best_normal"):
		save["best_normal"] = int(save.get("best", 0)); save["level_normal"] = int(save.get("best_level", 0))
	# modes now open at level 6: anyone who already got that far keeps the next mode
	if int(save.get("level_normal", 0)) > UNLOCK_AT: save["unl_hard"] = true
	if int(save.get("level_hard", 0)) > UNLOCK_AT: save["unl_extreme"] = true
	if not save["stats"] is Dictionary: save["stats"] = {}
	if not save["missions"] is Array: save["missions"] = []

# ------------------------------------------------------------------ modes: NORMAL, then HARD and EXTREME, each opened by clearing level UNLOCK_AT of the one before
func unlocked(m: String) -> bool:
	return m == "normal" or bool(save.get("unl_" + m, false))

func best_of(m: String) -> int: return int(save.get("best_" + m, 0))
func level_of(m: String) -> int: return int(save.get("level_" + m, 0))

func _solo_mode() -> String:
	var m := String(args.get("mode", save.get("mode", "normal")))
	if not m in EchoGame.MODES: m = "normal"
	if not args.has("mode") and not unlocked(m): m = "normal"
	return m

func _pick_mode(m: String) -> void:
	if unlocked(m):
		save["mode"] = m; _save()
	else:
		var prev: String = EchoGame.MODES[EchoGame.MODES.find(m) - 1]
		_note("CLEAR LEVEL %d ON %s TO UNLOCK %s" % [UNLOCK_AT, EchoGame.MODE_NAMES[prev], EchoGame.MODE_NAMES[m]])

func _save() -> void:
	# never write over the only copy: a temp file first, the last good save kept as .bak, then the swap
	var f := FileAccess.open("user://save.json.tmp", FileAccess.WRITE)
	if f == null: return
	f.store_string(JSON.stringify(save)); f.close()
	var d := DirAccess.open("user://")
	if d == null: return
	if d.file_exists("save.json"):
		if d.file_exists("save.json.bak"): d.remove("save.json.bak")
		d.rename("save.json", "save.json.bak")
	d.rename("save.json.tmp", "save.json")

func _note(s: String) -> void:
	msg = s; msg_t = 3.5

func _tip(s: String) -> void:
	tip = s; tip_t = 3.2

# ------------------------------------------------------------------ games
func _new_game(role: String, local: int, ros: Array, seed_ := 0, demo := false, mode := "normal", daily := false) -> void:
	if game: game.queue_free()
	game = EchoGame.new(); game.name = "Game"; game.sound = sound; game.demo = demo; game.daily = daily
	add_child(game); move_child(game, 0)
	if demo: game.start_demo()
	game.setup(role, local, ros, seed_, mode)
	game.event.connect(_on_game_event)
	game.report.connect(_on_report)
	tilt_have = false

func _title() -> void:
	_new_game("solo", 1, [[1, "YOU"]], 0, true)
	screen = "title"
	sound.play_music("music_title", -6.0)

func _start_solo() -> void:
	net.close()
	if daily_run: _new_game("solo", 1, [[1, "YOU"]], _today() * 31 + 7, false, "normal", true)
	else: _new_game("solo", 1, [[1, "YOU"]], 0, false, _solo_mode())
	just_unlocked = ""; run_close = 0
	run_start_level = level_of(game.mode)
	if not daily_run:
		game.trail_style = String(save.get("trail", "classic"))
		game.hues = PALETTE_COLS.get(String(save.get("palette", "neon")), PALETTE_COLS["neon"])
	screen = "play"
	save["plays"] = int(save["plays"]) + 1
	_stat("runs", 1)
	if int(save["stats"].get("runs", 0)) >= 25: _mission("regular")
	_save()
	sound.sfx("sfx_select", -2, 1.0, 0)
	sound.play_music("music_game", -7.0)
	_tip(_control_tip())

func _control_tip() -> String:
	match save["control"]:
		"tilt": return "TILT THE PHONE TO MOVE.  GRAB 5 SHARDS."
		"tilt_hold": return "TILT TO STEER.  TOUCH ANYWHERE TO GO, LIFT TO STOP."
	return "DRAG ANYWHERE TO MOVE.  GRAB 5 SHARDS."

func _on_game_event(kind: String, d: Dictionary) -> void:
	# the host passes every event on to the clients
	if game.role == "host": h_event.rpc(kind, d)
	_local_event(kind, d)

func _local_event(kind: String, d: Dictionary) -> void:
	match kind:
		"clear":
			var lv: int = d["level"]
			if game.me().get("alive", false):
				_stat("levels", 1)
				if lv >= 3: _mission("first")
				if lv >= 5: _mission("five")
				if lv >= 10: _mission("ten")
				if lv >= 5 and game.mode == "hard": _mission("hard5")
				if lv >= 5 and game.mode == "extreme": _mission("ext5")
				if not d.get("timeout", false) and game.lvl_time() - game.lt >= 7.0: _mission("quick")
			if not game.multi():
				if lv >= UNLOCK_AT and not daily_run: _unlock_after(game.mode)
				if game.mode == "extreme" and lv == 1:
					_tip("THE SPIKED ECHO HUNTS YOU.  SHARDS WON'T WAIT.")
				else: match lv:
					1: _tip("THAT GHOST IS YOU, FROM LEVEL 1.  DON'T TOUCH IT.")
					2: _tip("EVERY LEVEL, ONE MORE OF YOU.")
					3: _tip("KEEP YOUR PATH TIDY: EVERY MOVE COMES BACK.")
					4: _tip("BRUSH PAST THEM FOR BONUS POINTS.")
				# a medal, the moment you reach its level
				if not daily_run:
					for md in MEDALS:
						if lv + 1 == int(md[0]) and run_start_level < int(md[0]):
							toast = "%s MEDAL!  %s LEVEL %d" % [md[1], EchoGame.MODE_NAMES[game.mode], md[0]]; toast_t = 3.0
							sound.sfx("sfx_best", -4, 1.0, 0)
			else:
				if lv == 1: _tip("TAKE A SHARD EVERY LEVEL OR TURN.  CAUGHT = ZOMBIE.")
			if lv == 7: sound.play_music("music_intense", -6.0)
		"shard":
			if d["id"] == game.local_id:
				_stat("shards", 1)
				if int(save["stats"].get("shards", 0)) >= 500: _mission("collect")
		"close":
			if d["id"] == game.local_id:
				_stat("close", 1); run_close += 1
				if run_close >= 5: _mission("thread")
				if run_close >= 15: _mission("dare")
		"caught":
			if d["id"] == game.local_id:
				_stat("caught" if int(d.get("by", -1)) >= 0 or int(d.get("z", -1)) >= 0 else "timeups", 1)
				if not game.multi(): _solo_over()
				else: _tip("YOU'RE A ZOMBIE NOW.  CATCH THE OTHERS!")
		"over":
			_mp_over()

func _unlock_after(m: String) -> void:
	var i := EchoGame.MODES.find(m)
	if i < 0 or i >= EchoGame.MODES.size() - 1: return
	var nxt: String = EchoGame.MODES[i + 1]
	if unlocked(nxt): return
	save["unl_" + nxt] = true; _save()
	just_unlocked = nxt
	_tip(EchoGame.MODE_NAMES[nxt] + " MODE UNLOCKED!")
	sound.sfx("sfx_best", -4, 1.0, 0)

func medals_of(m: String) -> int:
	var n := 0
	for md in MEDALS: if level_of(m) >= int(md[0]): n += 1
	return n

func next_medal(m: String) -> Array:
	for md in MEDALS: if level_of(m) < int(md[0]): return md
	return []

func _cos_open(req: String) -> bool:
	match req:
		"": return true
		"HARD BRONZE": return level_of("hard") >= 5
		"10 MISSIONS": return (save["missions"] as Array).size() >= 10
		"GOLD MEDAL": return level_of("normal") >= 15 or level_of("hard") >= 15 or level_of("extreme") >= 15
		"5 MISSIONS": return (save["missions"] as Array).size() >= 5
		"NORMAL SILVER": return level_of("normal") >= 10
	return false

func _mission_progress(id: String) -> String:
	var st: Dictionary = save["stats"]
	match id:
		"collect": return "%d/500" % mini(int(st.get("shards", 0)), 500)
		"regular": return "%d/25" % mini(int(st.get("runs", 0)), 25)
		"daily": return "%d/3" % mini(int(save.get("streak", 0)), 3)
		"thread": return "%d/5" % mini(int(st.get("best_close", 0)), 5)
		"dare": return "%d/15" % mini(int(st.get("best_close", 0)), 15)
	return ""

func _solo_over() -> void:
	var st: Dictionary = save["stats"]
	st["best_close"] = maxi(int(st.get("best_close", 0)), run_close)
	# the first few times, always the one that matters most; then any of them
	over_tip = TIPS[0] if int(st.get("runs", 0)) <= 3 else TIPS[randi() % TIPS.size()]
	screen = "over"; over_at = t_ui
	sound.stop_music()
	var m := game.mode
	if daily_run:
		var today := _today()
		if int(save.get("daily_day", 0)) != today:
			var prev := int(save.get("daily_day", 0))
			save["streak"] = int(save.get("streak", 0)) + 1 if prev == _day_before(today) else 1
			save["daily_day"] = today; save["daily_best"] = 0
			save["best_streak"] = maxi(int(save.get("best_streak", 0)), int(save["streak"]))
		new_best = game.score_of(1) > int(save["daily_best"])
		if new_best: save["daily_best"] = game.score_of(1)
		if int(save["streak"]) >= 3: _mission("daily")
	else:
		new_best = game.score_of(1) > best_of(m)
		if new_best: save["best_" + m] = game.score_of(1)
		if game.level > level_of(m): save["level_" + m] = game.level
	_save()
	get_tree().create_timer(1.1).timeout.connect(func():
		if new_best: sound.sfx("sfx_best", -2, 1.0, 0)
		else: sound.sfx("jingle_gameover", -3, 1.0, 0))

func _mp_over() -> void:
	screen = "over"; over_at = t_ui
	sound.stop_music()
	var won: bool = game.winner == game.local_id
	if game.order.size() >= 3: _mission("party")
	if won and game.order.size() >= 2: _mission("winner")
	_save()
	get_tree().create_timer(0.9).timeout.connect(func(): sound.sfx("sfx_best" if won else "jingle_gameover", -2, 1.0, 0))

# ------------------------------------------------------------------ LAN: hosting
func _host() -> void:
	var err := net.host()
	if err != OK: _note("COULD NOT HOST (PORT %d BUSY?)" % Net.PORT); return
	roster = [[1, _my_name() if String(save.get("name", "")) != "" else "HOST"]]
	net.info = {"name": roster[0][1], "n": 1, "open": true}
	screen = "lobby"
	sound.sfx("sfx_select", -2, 1.0, 0)

func _on_peer_connected(id: int) -> void:
	if not multiplayer.is_server(): return
	# a match already running: no room
	if screen in ["play", "paused"] or roster.size() >= 8:
		net.peer.disconnect_peer(id); return

func _on_peer_disconnected(id: int) -> void:
	if multiplayer.is_server():
		for r in roster.duplicate():
			if r[0] == id: roster.erase(r); _note("%s LEFT" % r[1])
		net.info["n"] = roster.size()
		h_lobby.rpc(roster, mp_mode)
		if game and game.role == "host": game.remove_player(id)

@rpc("any_peer", "call_remote", "reliable")
func c_hello(name_: String) -> void:
	if not multiplayer.is_server(): return
	var id := multiplayer.get_remote_sender_id()
	for r in roster: if r[0] == id: return
	var n := _name_clean(name_)
	if n == "" or n == "PLAYER": n = "P%d" % (roster.size() + 1)
	var taken := false
	for r in roster: if String(r[1]) == n: taken = true
	if taken: n = n.left(8) + str(roster.size() + 1)
	roster.append([id, n])
	net.info["n"] = roster.size()
	sound.sfx("sfx_select", -6, 1.4, 0)
	h_lobby.rpc(roster, mp_mode)

func _host_start() -> void:
	if not multiplayer.is_server(): return
	mp_seed = randi() % 1000000 + 1
	net.info["open"] = false
	if args.has("mode"): mp_mode = String(args["mode"])
	h_start.rpc(roster, mp_seed, mp_mode)
	_begin_mp("host", 1, roster, mp_seed, mp_mode)

func _host_mode(m: String) -> void:
	# in a LAN match every mode is open: it's a party, let the room decide
	mp_mode = m
	h_lobby.rpc(roster, mp_mode)

func _begin_mp(role: String, local: int, ros: Array, seed_: int, mode := "normal") -> void:
	_new_game(role, local, ros, seed_, false, mode)
	sent_runs_ver = -1
	screen = "play"
	sound.sfx("sfx_select", -2, 1.0, 0)
	sound.play_music("music_game", -7.0)
	_tip(_control_tip())

func _host_tick(dt: float) -> void:
	snap_acc += dt
	if snap_acc < 1.0 / 30.0: return
	snap_acc = 0.0
	if game.runs_ver != sent_runs_ver:
		sent_runs_ver = game.runs_ver
		h_runs.rpc(game.runs)
	h_snap.rpc(game.snapshot())

func _back_to_lobby() -> void:
	# the host takes everyone back to the lobby for another match
	net.info["open"] = true
	h_lobby_screen.rpc()
	_new_game("solo", 1, [[1, "YOU"]], 0, true)
	screen = "lobby"
	sound.play_music("music_title", -6.0)

# ------------------------------------------------------------------ LAN: joining
func _go_join() -> void:
	net.close()
	net.listen()
	screen = "join"

func _join(ip: String) -> void:
	ip = ip.strip_edges()
	if ip.count(".") != 3: _note("THAT ISN'T AN ADDRESS"); return
	joining_ip = ip; join_at = t_ui
	save["last_ip"] = ip; _save()
	net.stop_listen()
	var err := net.join(ip)
	if err != OK: _note("COULD NOT CONNECT"); return
	screen = "connecting"

func _on_connected() -> void:
	c_hello.rpc_id(1, String(save.get("name", "")))
	screen = "lobby"
	sound.sfx("sfx_select", -2, 1.0, 0)

@rpc("authority", "call_remote", "reliable")
func h_lobby(ros: Array, mode := "normal") -> void:
	roster = ros; mp_mode = mode

@rpc("authority", "call_remote", "reliable")
func h_lobby_screen() -> void:
	_new_game("solo", 1, [[1, "YOU"]], 0, true)
	screen = "lobby"
	sound.play_music("music_title", -6.0)

@rpc("authority", "call_remote", "reliable")
func h_start(ros: Array, seed_: int, mode := "normal") -> void:
	roster = ros; mp_mode = mode
	_begin_mp("client", multiplayer.get_unique_id(), ros, seed_, mode)

@rpc("authority", "call_remote", "unreliable_ordered")
func h_snap(s: Array) -> void:
	if game and game.role == "client": game.apply_snapshot(s)

@rpc("authority", "call_remote", "reliable")
func h_runs(arr: Array) -> void:
	if game and game.role == "client": game.set_runs(arr)

@rpc("authority", "call_remote", "reliable")
func h_event(kind: String, d: Dictionary) -> void:
	if game and game.role == "client":
		game.on_event(kind, d)
		_local_event(kind, d)

## a client judged itself caught, or took the shard: tell the host, which checks it and decides
func _on_report(kind: String, d: Dictionary) -> void:
	if game.role != "client": return
	if kind == "died": c_died.rpc_id(1, int(d["by"]), int(d.get("z", -1)))
	elif kind == "take": c_take.rpc_id(1, int(d["n"]))
	elif kind == "zcatch": c_zcatch.rpc_id(1, int(d["v"]))

@rpc("any_peer", "call_remote", "reliable")
func c_died(by: int, z := -1) -> void:
	if game and game.role == "host": game.remote_caught(multiplayer.get_remote_sender_id(), by, z)

@rpc("any_peer", "call_remote", "reliable")
func c_zcatch(v: int) -> void:
	if game and game.role == "host": game.remote_zcatch(multiplayer.get_remote_sender_id(), v)

@rpc("any_peer", "call_remote", "reliable")
func c_take(n: int) -> void:
	if game and game.role == "host": game.remote_take(multiplayer.get_remote_sender_id(), n)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func c_pos(pos: Vector2) -> void:
	if game and game.role == "host": game.set_remote(multiplayer.get_remote_sender_id(), pos)

func _client_tick(dt: float) -> void:
	snap_acc += dt
	if snap_acc < 1.0 / 30.0: return
	snap_acc = 0.0
	var p := game.me()
	if not p.is_empty() and (p["alive"] or p.get("zombie", false)): c_pos.rpc_id(1, p["pos"])

func _leave() -> void:
	net.close(); roster.clear()
	_title()

# ------------------------------------------------------------------ input
func _input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		var p: Vector2 = e.position
		if e.pressed: touches[e.index] = p
		else: touches.erase(e.index)
		if e.pressed:
			# buttons first, on every screen
			for b in buttons:
				if (b[0] as Rect2).grow(3).has_point(p - Vector2(0, ui_oy)):
					sound.sfx("sfx_move", -6, 1.0, 0); (b[1] as Callable).call(); return
			if screen == "title": return
			if screen == "name":
				if name_edit: name_edit.grab_focus()
				return
			if screen == "over": return              # only the buttons: a stray tap shouldn't throw away the results
			if screen == "paused": _resume(); return
			if screen == "play" and stick_id < 0 and save["control"] == "touch":
				stick_id = e.index; stick_on = true; stick_o = p; stick_p = p
		elif e.index == stick_id:
			stick_id = -1; stick_on = false
	elif e is InputEventScreenDrag:
		touches[e.index] = e.position
		if e.index == stick_id: stick_p = e.position
	elif e is InputEventKey and e.pressed and not e.echo:
		if screen == "name":
			if e.keycode == KEY_ESCAPE: _name_close(); screen = "settings"
			return
		if screen == "keypad":
			if e.keycode >= KEY_0 and e.keycode <= KEY_9: _kp(char(e.unicode))
			elif e.keycode == KEY_PERIOD: _kp(".")
			elif e.keycode == KEY_BACKSPACE: _kp("<")
			elif e.keycode == KEY_ENTER: _join(keypad_ip)
			elif e.keycode == KEY_ESCAPE: screen = "join"
			return
		match e.keycode:
			KEY_ENTER, KEY_SPACE:
				if screen == "title": _start_solo()
				elif screen == "over" and t_ui - over_at > REPLAY + 1.0 and not game.multi(): _start_solo()
				elif screen == "paused": _resume()
			KEY_ESCAPE, KEY_P:
				if screen == "play" and not game.multi(): _pause()
				elif screen == "paused": _resume()
				elif screen in ["settings", "join"]: _title()
				elif screen == "calib": screen = calib_back
			KEY_M:
				save["sound"] = not bool(save["sound"]); sound.set_on(save["sound"]); _save()

# ------------------------------------------------------------------ sharing a score: a picture of the result + a line of text
func _share_text() -> String:
	var g := game
	var mn: String = EchoGame.MODE_NAMES[g.mode]
	if g.multi():
		var res := "I WON" if g.winner == g.local_id else "I played"
		return "%s a %d-player %s match of ECHOES, where everyone's past runs come back to hunt you. Level %d. Can you survive us?" % [res, g.order.size(), mn, g.level]
	var t := "I reached level %d on %s in ECHOES with %d of my own echoes chasing me. Score %d. Can you beat me?" % [g.level, "DAILY RUN #%d" % _today() if daily_run else mn, g.runs.size(), g.score_of(1)]
	return t + ("  " + STORE_LINK if STORE_LINK != "" else "")

func _share() -> void:
	if sharing or card_open: return
	_mission("share")
	sharing = true
	var img: Image = await _render_card()
	sharing = false
	var path := OS.get_user_data_dir() + "/echoes_score.png"
	img.save_png(path)
	var text := _share_text()
	if OS.get_name() == "Android" and Engine.has_singleton("AndroidRuntime"):
		_android_share(path, text)
	elif OS.get_name() == "iOS" or args.has("ios_card"):
		DisplayServer.clipboard_set(text)
		if FileAccess.file_exists("user://.share_ready") and not args.has("ios_card"):
			# the app's native part (tools/ios/native) watches for this file and opens the iOS share sheet
			# with the picture and the text. Written under another name first, so it's never read half-done.
			var f := FileAccess.open("user://share_request.tmp", FileAccess.WRITE)
			if f:
				f.store_string(text); f.close()
				DirAccess.rename_absolute(OS.get_user_data_dir() + "/share_request.tmp", OS.get_user_data_dir() + "/share_request.txt")
				return
		# no native part (an older build): show the card big, to screenshot
		# shrunk smoothly to exactly the size it's shown at, so the small text stays readable
		var small: Image = img.duplicate()
		var side := int(view.y - 28.0)
		small.resize(side, side, Image.INTERPOLATE_LANCZOS)
		card_tex = ImageTexture.create_from_image(small); card_open = true; card_at = t_ui
	else:
		DisplayServer.clipboard_set(text)
		_note("PICTURE SAVED, TEXT COPIED")
		print("share ", path, " | ", text)
		if not args.has("shot") and not args.has("share_test") and not args.has("over_shots"): OS.shell_open(path)

## the share card is drawn on its own square 360x360 canvas (no CRT on it), then scaled to 1080x1080
func _render_card() -> Image:
	var sv := SubViewport.new()
	sv.size = Vector2i(360, 360); sv.transparent_bg = false
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sv.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	var lay := Layer.new(); lay.f = func(ci): _draw_card_sq(ci, Vector2(360, 360))
	sv.add_child(lay); add_child(sv)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := sv.get_texture().get_image()
	sv.queue_free()
	img.resize(1080, 1080, Image.INTERPOLATE_NEAREST)
	return img

## Android: put the picture in the phone's gallery, then open the share sheet (WhatsApp, Instagram, ...).
## If the picture can't be added, the text is shared on its own.
func _android_share(path: String, text: String) -> void:
	var rt = Engine.get_singleton("AndroidRuntime")
	var act = rt.getActivity()
	if act == null: _note("COULD NOT OPEN SHARING"); return
	var media = JavaClassWrapper.wrap("android.provider.MediaStore$Images$Media")
	var uri_s = media.insertImage(act.getContentResolver(), path, "ECHOES score", text) if media else null
	var intent_c = JavaClassWrapper.wrap("android.content.Intent")
	var it = intent_c.Intent("android.intent.action.SEND")
	if uri_s != null and String(uri_s) != "":
		var uri = JavaClassWrapper.wrap("android.net.Uri").parse(String(uri_s))
		it.setType("image/png")
		it.putExtra("android.intent.extra.STREAM", uri)
		it.addFlags(1)                 # FLAG_GRANT_READ_URI_PERMISSION
	else:
		it.setType("text/plain")
	it.putExtra("android.intent.extra.TEXT", text)
	var chooser = intent_c.createChooser(it, "Share your score")
	var go = func(): act.startActivity(chooser if chooser != null else it)
	act.runOnUiThread(rt.createRunnableFromGodotCallable(go))

func _share_footer(ci: CanvasItem) -> void:
	var w := view.x; var h := view.y
	Art.text(ci, "ECHOES", Vector2(w / 2, h - 40), Color(0.4, 1, 1), true, 1)
	Art.text(ci, "YOUR PAST SELVES COME BACK.  CAN YOU BEAT ME?", Vector2(w / 2, h - 18), Color(1, 0.85, 0.4), false, 1)

# ------------------------------------------------------------------ daily run, stats and missions
func _today() -> int:
	var d := Time.get_date_dict_from_system()
	return int(d["year"]) * 10000 + int(d["month"]) * 100 + int(d["day"])

func _day_before(day: int) -> int:
	var u := Time.get_unix_time_from_datetime_dict({"year": day / 10000, "month": (day / 100) % 100, "day": day % 100, "hour": 12}) - 86400
	var d := Time.get_date_dict_from_unix_time(int(u))
	return int(d["year"]) * 10000 + int(d["month"]) * 100 + int(d["day"])

func _daily_line() -> String:
	var today := _today(); var dd := int(save.get("daily_day", 0)); var st := int(save.get("streak", 0))
	if dd == today: return "TODAY'S DAILY BEST  %d   -   STREAK  %d" % [int(save.get("daily_best", 0)), st]
	if st > 0 and dd == _day_before(today): return "PLAY TODAY'S DAILY RUN TO KEEP YOUR %d-DAY STREAK" % st
	return "A NEW DAILY RUN EVERY DAY: SAME START FOR EVERYONE"

func _stat(k: String, n) -> void:
	var st: Dictionary = save["stats"]
	st[k] = st.get(k, 0) + n

func _mission(id: String) -> void:
	var done: Array = save["missions"]
	if done.has(id): return
	done.append(id); _save()
	for m in MISSIONS:
		if m[0] == id: toast = "MISSION COMPLETE:  " + m[1]; toast_t = 3.0
	sound.sfx("sfx_best", -6, 1.2, 0)

# ------------------------------------------------------------------ your name, for LAN games
func _my_name() -> String:
	var n := String(save.get("name", ""))
	return n if n != "" else "PLAYER"

func _name_clean(t: String) -> String:
	var out := ""
	for ch in t.to_upper():
		if (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9") or ch == " ": out += ch
	return out.strip_edges().left(10)

func _go_name() -> void:
	if name_edit == null:
		# an invisible text box: it brings up the phone's keyboard; the name is drawn in the game's own font
		name_edit = LineEdit.new(); name_edit.max_length = 12
		name_edit.position = Vector2(-4000, -4000); name_edit.size = Vector2(120, 24)
		name_edit.text_submitted.connect(func(_t): _name_done())
		ui_layer.add_child(name_edit)
	name_edit.text = String(save.get("name", ""))
	screen = "name"
	name_edit.grab_focus(); name_edit.caret_column = name_edit.text.length()

func _name_close() -> void:
	if name_edit: name_edit.release_focus()
	if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD): DisplayServer.virtual_keyboard_hide()

func _name_done() -> void:
	if name_edit: save["name"] = _name_clean(name_edit.text); _save()
	_name_close(); screen = "settings"

func _pause() -> void:
	if game.multi(): return           # a LAN match doesn't stop for one player
	screen = "paused"; game.process_mode = Node.PROCESS_MODE_DISABLED

func _resume() -> void:
	screen = "play"; game.process_mode = Node.PROCESS_MODE_INHERIT; tilt_have = false
	if game.state == "play": game.hold_t = 1.5        # 3-2-1, so she isn't thrown straight back in

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		if screen == "play": _pause()
	if what == NOTIFICATION_WM_GO_BACK_REQUEST: _back()

## the phone's Back button: one step back, never straight out of the game
func _back() -> void:
	match screen:
		"title": get_tree().quit()
		"play":
			if game.multi(): _note("TO LEAVE A LAN GAME, WAIT FOR THE RESULTS")
			else: _pause()
		"paused": _resume()
		"settings", "join": _title()
		"keypad": screen = "join"
		"calib": screen = calib_back
		"name": _name_close(); screen = "settings"
		"stats": _title()
		"style": screen = "stats"
		"connecting": _go_join()
		"lobby": _leave()
		"over":
			if game.multi(): _leave()
			else: _title()
		_: _title()

func _kp(c: String) -> void:
	if c == "<": keypad_ip = keypad_ip.left(maxi(keypad_ip.length() - 1, 0))
	elif keypad_ip.length() < 15: keypad_ip += c

# ------------------------------------------------------------------ movement: touch, tilt, or tilt + hold
func _raw_g() -> Vector3:
	var g := Input.get_gravity()
	if g.length() < 0.1: g = Input.get_accelerometer()
	return g

func _tilt() -> Vector2:
	var g := _raw_g()
	if g.length() < 0.1: return Vector2.ZERO
	# the moment a level starts (and on resume), however she holds the phone is "level"
	if not tilt_have or (game and game.state == "ready"):
		tilt_zero = g; tilt_have = true
	var d := g - tilt_zero
	var v := Vector2(-d.x, -d.y)
	# calibrated: the directions this phone reported when she tipped it right and away
	if save.has("tilt_r") and save.has("tilt_u"):
		var R := _v3(save["tilt_r"]); var U := _v3(save["tilt_u"])
		v = Vector2(d.dot(R), -d.dot(U))
	if save["flip_x"]: v.x = -v.x
	if save["flip_y"]: v.y = -v.y
	var div: float = [4.2, 2.8, 1.8][clampi(int(save["sens"]), 0, 2)]
	v /= div
	if v.length() < 0.12: v = Vector2.ZERO          # a small dead zone, so a still hand stands still
	return v.limit_length(1.0)

func _v3(a) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2])) if a is Array and a.size() == 3 else Vector3.ZERO

# ------------------------------------------------------------------ tilt calibration: hold, tip right, tip away
var calib_step := 0          # 0 hold still + tap, 1 tip right, 2 back to level, 3 tip away, 4 done
var calib_g0 := Vector3.ZERO
var calib_r := Vector3.ZERO
var calib_hold := 0.0
var calib_back := "settings"

func _go_calib(back := "settings") -> void:
	calib_back = back; calib_step = 0; calib_hold = 0.0
	screen = "calib"

func _calib_start() -> void:
	calib_g0 = _raw_g()
	if calib_g0.length() < 0.1: _note("THIS PHONE GIVES NO TILT READINGS"); return
	calib_step = 1; calib_hold = 0.0
	sound.sfx("sfx_select", -4, 1.0, 0)

func _calib_tick(dt: float) -> void:
	if calib_step < 1 or calib_step > 3: return
	var d := _raw_g() - calib_g0
	match calib_step:
		1, 3:
			calib_hold = calib_hold + dt if d.length() > 2.2 else 0.0
			if calib_hold > 0.45:
				var n := d.normalized()
				if calib_step == 1:
					calib_r = n; calib_step = 2; calib_hold = 0.0
					sound.sfx("sfx_shard1", -4, 1.0, 0)
				else:
					if absf(n.dot(calib_r)) > 0.7:
						_note("THAT WAS THE SAME WAY AS RIGHT.  TRY AGAIN."); calib_step = 0; return
					save["tilt_r"] = [calib_r.x, calib_r.y, calib_r.z]; save["tilt_u"] = [n.x, n.y, n.z]
					save["flip_x"] = false; save["flip_y"] = false
					_save(); tilt_have = false
					print("TILT CALIBRATED right=", calib_r, " away=", n, " zero=", calib_g0)
					calib_step = 4; sound.sfx("sfx_clear", -4, 1.0, 0)
		2:
			calib_hold = calib_hold + dt if d.length() < 1.2 else 0.0
			if calib_hold > 0.3: calib_step = 3; calib_hold = 0.0

func _draw_calib(ci: CanvasItem) -> void:
	var w := view.x; var h := view.y
	_dim(ci); ci.draw_rect(_full(), Color(0, 0, 0, 0.5))
	Art.text(ci, "CALIBRATE TILT", Vector2(w / 2, 8), Color(1, 0.4, 0.85), true, 1)
	var c := Vector2(w / 2, h / 2 + 4)
	var lines := ["", ""]
	match calib_step:
		0: lines = ["HOLD THE PHONE THE WAY YOU PLAY.", "KEEP IT STILL, THEN TAP START."]
		1: lines = ["TIP THE RIGHT SIDE OF THE PHONE DOWN", "AND HOLD IT THERE."]
		2: lines = ["GOOD.  NOW BACK TO HOW YOU STARTED.", ""]
		3: lines = ["TIP THE FAR EDGE DOWN, AWAY FROM YOU", "(LIKE ROLLING A BALL AWAY)  AND HOLD."]
		4: lines = ["DONE.  THE DOT NOW FOLLOWS YOUR PHONE.", "CHECK IT IN THE TILT TEST."]
	Art.text(ci, lines[0], Vector2(w / 2, 34), Color(1, 1, 1), false, 1)
	Art.text(ci, lines[1], Vector2(w / 2, 46), Color(0.85, 0.85, 0.9), false, 1)
	# a big arrow for the direction asked for
	var dir := Vector2.ZERO
	if calib_step == 1: dir = Vector2.RIGHT
	elif calib_step == 3: dir = Vector2.UP
	if dir != Vector2.ZERO:
		var k := 0.6 + 0.4 * sin(t_ui * 6.0)
		var tip := c + dir * 30.0
		ci.draw_line(c - dir * 22.0, tip, Color(0.4, 1, 1, k), 3.0)
		var side := dir.orthogonal() * 9.0
		ci.draw_colored_polygon(PackedVector2Array([tip + dir * 8.0, tip + side, tip - side]), Color(0.4, 1, 1, k))
		ci.draw_rect(Rect2(c.x - 50, c.y + 44, 100 * clampf(calib_hold / 0.45, 0.0, 1.0), 3), Color(0.4, 1, 1))
	if calib_step == 4:
		var t := _tilt()
		ci.draw_rect(Rect2(c - Vector2(40, 24), Vector2(80, 48)), Color(1, 0.4, 0.85, 0.6), false, 1.0)
		ci.draw_circle(c + Vector2(t.x * 36, t.y * 20), 4, Color(0.4, 1, 1))
	if calib_step == 0:
		_button(ci, Rect2(w / 2 - 110, h - 34, 104, 20), "START", _calib_start, true, Color(0.4, 1, 1))
		_button(ci, Rect2(w / 2 + 6, h - 34, 104, 20), "CANCEL", func(): screen = calib_back)
	elif calib_step == 4:
		_button(ci, Rect2(w / 2 - 110, h - 34, 104, 20), "OK", func(): screen = calib_back, true, Color(0.4, 1, 1))
		_button(ci, Rect2(w / 2 + 6, h - 34, 104, 20), "AGAIN", func(): _go_calib(calib_back))
	else:
		_button(ci, Rect2(w / 2 - 52, h - 34, 104, 20), "RESTART", func(): _go_calib(calib_back))

func _movement() -> Vector2:
	var mv := Vector2.ZERO
	match String(save["control"]):
		"touch":
			if stick_on:
				var d := stick_p - stick_o
				var R := stick_r
				if d.length() > R: stick_o = stick_p - d.normalized() * R; d = stick_p - stick_o
				mv = d / R
				if mv.length() < 0.12: mv = Vector2.ZERO
		"tilt":
			mv = _tilt()
		"tilt_hold":
			var t := _tilt()
			if t.length() > 0.15: tilt_dir = t.normalized()
			mv = tilt_dir if not touches.is_empty() else Vector2.ZERO
	var k := Vector2(float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),
		float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
	if k != Vector2.ZERO: mv = k.normalized()
	return mv

# ------------------------------------------------------------------ frame
func _process(dt: float) -> void:
	t_ui += dt; tip_t = maxf(0.0, tip_t - dt); msg_t = maxf(0.0, msg_t - dt)
	toast_t = maxf(0.0, toast_t - dt); score_pop = maxf(0.0, score_pop - dt); pip_pop = maxf(0.0, pip_pop - dt)
	if screen == "play" and game and not game.demo: _stat("time", dt)
	view = get_viewport_rect().size
	var ws := DisplayServer.window_get_size()
	if ws.x > 0 and OS.has_feature("mobile"):
		var sa := DisplayServer.get_display_safe_area()
		var k := view.x / float(ws.x)
		safe_l = maxf(0.0, sa.position.x * k); safe_r = maxf(0.0, (ws.x - sa.end.x) * k)
		# full speed after the same thumb movement on every screen. On a big screen (iPad) 22 game pixels
		# is twice as far for the thumb as on a phone, which made the stick feel slow.
		var dpi := DisplayServer.screen_get_dpi()
		if dpi >= 100: stick_r = clampf(7.0 / 25.4 * dpi * k, 11.0, 22.0)
	crt.size = view
	var mv := _movement()
	if (args.has("autoplay") or args.has("host") or args.has("join")) and game and not game.demo and (game.me().get("alive", false) or game.me().get("zombie", false)):
		mv = game._demo_move()
	if game and not game.demo: game.move_in = mv if screen == "play" or screen == "over" else Vector2.ZERO
	if game and game.role == "host": _host_tick(dt)
	if game and game.role == "client": _client_tick(dt)
	if screen == "connecting" and t_ui - join_at > 6.0: _note("NO ANSWER FROM " + joining_ip); _go_join()
	if screen == "calib": _calib_tick(dt)
	_test_hooks()
	cmat.set_shader_parameter("shake", game.shake if game else 0.0)
	cmat.set_shader_parameter("flash", game.flash * 0.6 if game else 0.0)
	ui.queue_redraw()

func _test_hooks() -> void:
	# test: --over_shots=DIR saves the death replay and the results screen
	if args.has("over_shots") and screen == "over" and not game.multi():
		if t_ui - over_at > 0.5 and not has_meta("s1"):
			set_meta("s1", 1); get_viewport().get_texture().get_image().save_png(String(args["over_shots"]) + "/replay.png")
		if t_ui - over_at > REPLAY + 1.4 and not has_meta("s2"):
			set_meta("s2", 1); get_viewport().get_texture().get_image().save_png(String(args["over_shots"]) + "/over.png")
	if args.has("share_test") and screen == "over" and t_ui - over_at > REPLAY + 1.5 and not has_meta("shared"):
		set_meta("shared", 1); _share()
	if args.has("card_shot") and card_open and t_ui - card_at > 0.4 and not has_meta("card_shot"):
		set_meta("card_shot", 1); get_viewport().get_texture().get_image().save_png(String(args["card_shot"])); print("card shot")
	if args.has("autoplay") and not args.has("stay") and screen == "over" and t_ui - over_at > REPLAY + (3.0 if args.has("share_test") else 2.0):
		print("RESULT mode %s level %d score %d echoes %d killed_by %d" % [game.mode, game.level, game.score_of(1), game.runs.size(), game.killed_by]); get_tree().quit()
	if args.has("host") and screen == "lobby" and roster.size() >= int(args.get("players", "2")) and not has_meta("started"):
		set_meta("started", 1); print("HOST starting with ", roster); _host_start()
	if (args.has("host") or args.has("join")) and screen == "over" and t_ui - over_at > 1.5 and not has_meta("done"):
		set_meta("done", 1)
		var rows := []
		for id in game.order: rows.append("%s:%d%s" % [game.players[id]["name"], game.players[id]["score"], "*" if id == game.winner else ""])
		print("MP RESULT mode %s me=%d level %d  %s  runs %d" % [game.mode, game.local_id, game.level, " ".join(rows), game.runs.size()])
		get_tree().create_timer(1.0).timeout.connect(func(): get_tree().quit())
	if args.has("shot") and t_ui >= float(args.get("shot_at", "5")) and not has_meta("shot"):
		set_meta("shot", 1)
		if args.has("screen"): _test_screen(String(args["screen"]))
		get_tree().create_timer(0.3).timeout.connect(func():
			get_viewport().get_texture().get_image().save_png(args["shot"]); print("shot ", args["shot"])
			if args.has("quit_after_shot"): get_tree().quit())

func _test_screen(s: String) -> void:
	match s:
		"settings": screen = "settings"
		"calib": _go_calib(); calib_step = 3; calib_hold = 0.25
		"join":
			screen = "join"; net.hosts = {"192.168.1.23": {"name": "HOST", "n": 2, "open": true, "seen": 1e9}}
		"keypad": screen = "keypad"; keypad_ip = "192.168.1."
		"lobby": screen = "lobby"; roster = [[1, "HOST"], [55, "P2"], [77, "P3"]]; net.hosting = true; mp_mode = "extreme"
		"stats":
			screen = "stats"; save["stats"] = {"runs": 31, "time": 2480.0, "shards": 612, "close": 140, "levels": 120, "caught": 25, "timeups": 6}
			save["missions"] = ["first", "five", "thread", "quick", "collect", "regular"]; save["streak"] = 2; save["best_streak"] = 4
		"name": _go_name(); name_edit.text = "ROSHAN"
		"style": screen = "style"; save["missions"] = ["first", "five", "thread", "quick", "collect", "regular"]; save["level_hard"] = 6
		"title_locked": save["unl_hard"] = true; save["unl_extreme"] = false; save["mode"] = "hard"; save["best_hard"] = 8420; save["level_hard"] = 7

# ------------------------------------------------------------------ interface
# Buttons come in four looks: primary (filled: the one thing to do next), selected / unselected options,
# and locked. Every button is at least 22 px tall (about 7 mm on a phone).
func _btn(ci: CanvasItem, r: Rect2, label: String, f: Callable, kind := "secondary", col := Color(0.4, 1, 1), big := false) -> void:
	buttons.append([r, f])
	match kind:
		"primary":
			ci.draw_rect(r.grow(2), Color(col, 0.18))
			ci.draw_rect(r, Color(col, 0.92))
			Art.text(ci, label, r.get_center() - Vector2(0, 8 if big else 4), Color(0.03, 0.01, 0.07), big, 1, Color(0, 0, 0, 0))
		"selected":
			ci.draw_rect(r, Color(col, 0.3))
			ci.draw_rect(r, col, false, 1.0)
			Art.text(ci, label, r.get_center() - Vector2(0, 8 if big else 4), Color(1, 1, 1), big, 1)
		"locked":
			ci.draw_rect(r, Color(0.06, 0.04, 0.09, 0.95))
			ci.draw_rect(r, Color(0.45, 0.45, 0.5, 0.5), false, 1.0)
			# a padlock, then the label
			var lp := Vector2(r.position.x + 8, r.get_center().y)
			ci.draw_arc(lp + Vector2(2.5, -2), 2.0, PI, TAU, 8, Color(0.6, 0.6, 0.65), 1.0)
			ci.draw_rect(Rect2(lp + Vector2(0, -1), Vector2(6, 5)), Color(0.6, 0.6, 0.65))
			Art.text(ci, label, r.get_center() + Vector2(5, -4), Color(0.55, 0.55, 0.6), false, 1)
		_:
			ci.draw_rect(r, Color(0.07, 0.03, 0.12, 0.96))
			ci.draw_rect(r, Color(col, 0.6), false, 1.0)
			Art.text(ci, label, r.get_center() - Vector2(0, 8 if big else 4), Color(0.9, 0.9, 0.96), big, 1)

## an option button, selected or not. Every option in the game selects the same way: cyan.
const SEL := Color(0.4, 1, 1)
const LBL := Color(0.6, 0.66, 0.8)      # labels are dim; values and buttons are bright
func _button(ci: CanvasItem, r: Rect2, label: String, f: Callable, on := false, _col := Color(1, 0.4, 0.85)) -> void:
	_btn(ci, r, label, f, "selected" if on else "secondary", SEL if on else Color(0.62, 0.45, 0.95))

func _heading(ci: CanvasItem, s: String) -> void:
	Art.text(ci, s, Vector2(view.x / 2, 6), Color(1, 0.4, 0.85), true, 1)

func _draw_ui(ci: CanvasItem) -> void:
	buttons.clear()
	ui_oy = 0.0
	var w := view.x; var h := view.y
	if card_open and card_tex:
		# iOS: the card, as big as fits, with how to share it
		ci.draw_rect(Rect2(Vector2.ZERO, view), Color(0.02, 0.0, 0.05))
		var side := float(card_tex.get_width())
		ci.draw_texture_rect(card_tex, Rect2(Vector2(roundf(w / 2 - side / 2), 3), Vector2(side, side)), false)
		Art.text(ci, "TAKE A SCREENSHOT TO SHARE IT.  THE TEXT IS COPIED.", Vector2(w / 2, h - 20), Color(1, 0.85, 0.35), false, 1)
		Art.text(ci, "TAP TO CLOSE", Vector2(w / 2, h - 10), Color(0.6, 0.66, 0.8), false, 1)
		buttons.append([Rect2(Vector2.ZERO, view), func(): card_open = false])
		return
	var full_h := view.y
	ui_oy = floorf(maxf(0.0, full_h - 216.0) / 2.0)
	view.y = full_h - 2.0 * ui_oy
	ci.draw_set_transform(Vector2(0, ui_oy))
	_draw_screen(ci)
	ci.draw_set_transform(Vector2.ZERO)
	view.y = full_h

func _draw_screen(ci: CanvasItem) -> void:
	var w := view.x; var h := view.y
	match screen:
		"title": _draw_title(ci)
		"settings": _draw_settings(ci)
		"calib": _draw_calib(ci)
		"join": _draw_join(ci)
		"keypad": _draw_keypad(ci)
		"stats": _draw_stats(ci)
		"style": _draw_style(ci)
		"name": _draw_name(ci)
		"connecting":
			_dim(ci)
			Art.text(ci, "CONNECTING TO " + joining_ip + " ...", Vector2(w / 2, h / 2 - 14), Color(1, 1, 1), false, 1)
			_btn(ci, Rect2(w / 2 - 55, h / 2 + 10, 110, 24), "CANCEL", _go_join)
		"lobby": _draw_lobby(ci)
		_: _draw_hud(ci)
	if toast_t > 0.0:
		var ta := clampf(toast_t, 0.0, 1.0)
		var tw := toast.length() * 6 + 16
		var tr := Rect2(w / 2 - tw / 2.0, 40, tw, 14)
		ci.draw_rect(tr, Color(0.1, 0.07, 0.0, 0.92 * ta)); ci.draw_rect(tr, Color(1, 0.8, 0.25, ta), false, 1.0)
		Art.text(ci, toast, tr.get_center() - Vector2(0, 4), Color(1, 0.85, 0.35, ta), false, 1)
	if msg_t > 0.0:
		var mw := msg.length() * 6 + 12
		ci.draw_rect(Rect2(w / 2 - mw / 2.0, h - 17, mw, 12), Color(0.08, 0, 0.04, 0.9 * clampf(msg_t, 0.0, 1.0)))
		Art.text(ci, msg, Vector2(w / 2, h - 15), Color(1, 0.6, 0.6, clampf(msg_t, 0.0, 1.0)), false, 1)

## menus sit on an almost solid panel, so the arena never runs through the text
func _dim(ci: CanvasItem) -> void:
	ci.draw_rect(_full(), Color(0.02, 0.0, 0.05, 0.9))

## the whole screen, in band coordinates
func _full() -> Rect2:
	return Rect2(0, -ui_oy, view.x, view.y + 2.0 * ui_oy)

func _draw_hud(ci: CanvasItem) -> void:
	var w := view.x; var h := view.y
	var g := game
	var p := g.me()
	var lx := 8.0 + safe_l
	Art.text(ci, "LEVEL %d" % g.level, Vector2(lx, 4), Color(1, 0.4, 0.85), true)
	var mname: String = "DAILY" if daily_run and not g.multi() else EchoGame.MODE_NAMES[g.mode]
	Art.text(ci, mname, Vector2(lx, 22), Color(EchoGame.MODE_COLS[g.mode], 0.9))
	if not g.multi() and not daily_run:
		# the next medal you haven't got, and haven't already passed this run, on the same line (clear of the arena)
		for md in MEDALS:
			if int(md[0]) > g.level and int(md[0]) > level_of(g.mode):
				Art.text(ci, "%s AT %d" % [md[1], md[0]], Vector2(lx + Art.text_w(mname) + 6, 22), Color(md[2], 0.75)); break
	# the score pops when it goes up
	var sc := int(p.get("score", 0))
	if sc != hud_score: hud_score = sc; score_pop = 0.25
	var sp := score_pop / 0.25
	Art.text(ci, "%d" % sc, Vector2(w / 2, 4 - 2.0 * sp), Color(1, 1, 1).lerp(EchoGame.GOLD, sp), true, 1)
	if g.multi():
		var y := 5.0
		for id in g.order:
			var q: Dictionary = g.players[id]
			var name: String = "YOU" if id == g.local_id else q["name"]
			var zq: bool = q.get("zombie", false)
			Art.text(ci, "%s%s %d" % ["Z " if zq else "", name, q["score"]], Vector2(w - 6 - safe_r, y), EchoGame.ZCOL if zq else Color(q["col"], 1.0 if q["alive"] else 0.35), false, 2)
			y += 9.0
	else:
		# how many of you there are: a ring like an echo, and the count
		ci.draw_arc(Vector2(w - 34 - safe_r, 12), 4.0, 0, TAU, 14, Color(1, 0.5, 0.2), 1.5)
		Art.text(ci, "%d" % g.runs.size(), Vector2(w - 26 - safe_r, 4), Color(1, 0.6, 0.3), true)
		# pause: up by the score, away from where a thumb rests
		var pr := Rect2(w / 2 + 70, 3, 24, 22)
		buttons.append([pr, _pause])
		ci.draw_rect(pr, Color(1, 1, 1, 0.08)); ci.draw_rect(pr, Color(1, 1, 1, 0.35), false, 1.0)
		ci.draw_rect(Rect2(pr.position + Vector2(8, 6), Vector2(3, 10)), Color(1, 1, 1, 0.85))
		ci.draw_rect(Rect2(pr.position + Vector2(13, 6), Vector2(3, 10)), Color(1, 1, 1, 0.85))
	# shards this level: big gold pips; the newest one pops
	if g.got != hud_got: hud_got = g.got; pip_pop = 0.3
	for i in EchoGame.SHARDS:
		var c := Vector2(w / 2 - 32 + i * 16, 29)
		var lit := i < g.got
		var sz := 5.5 + (2.5 * pip_pop / 0.3 if i == g.got - 1 else 0.0)
		var pts := PackedVector2Array([c + Vector2(0, -sz), c + Vector2(sz, 0), c + Vector2(0, sz), c + Vector2(-sz, 0)])
		if lit: ci.draw_colored_polygon(pts, EchoGame.GOLD)
		ci.draw_polyline(pts + PackedVector2Array([pts[0]]), Color(EchoGame.GOLD, 0.95 if lit else 0.4), 1.0)
	# time left: a 5 px bar, white, then orange, then flashing red
	var left := clampf(1.0 - g.lt / g.lvl_time(), 0.0, 1.0)
	var bw := 330.0; var bx := w / 2 - bw / 2; var by := h - 8.0
	ci.draw_rect(Rect2(bx, by, bw, 5), Color(1, 1, 1, 0.15))
	var tc := Color(0.95, 0.95, 1.0)
	if left < 0.5: tc = Color(1, 0.65, 0.25)
	if left < 0.25: tc = Color(1, 0.3, 0.35) if int(t_ui * 8.0) % 2 == 0 else Color(1, 1, 1)
	ci.draw_rect(Rect2(bx, by, bw * left, 5), tc)
	# big messages go in the half of the arena away from where the level starts, never over the players
	var my := (h / 2 - 44) if g.origin_pt.y > 10.0 else (h / 2 + 34)
	if g.state == "ready":
		Art.text(ci, str(maxi(3 - int(g.state_t / 0.4), 1)), Vector2(w / 2, my), Color(1, 1, 1), true, 1)
		if g.level >= 2 and not g.multi():
			Art.text(ci, "+1 ECHO  -  %d OF YOU NOW" % g.runs.size(), Vector2(w / 2, my + 18), Color(1, 0.6, 0.9), false, 1)
	if g.hold_t > 0.0 and screen == "play":
		Art.text(ci, str(int(ceil(g.hold_t / 0.5))), Vector2(w / 2, my), Color(1, 1, 1), true, 1)
	if g.state == "play" and g.state_t < 0.5:
		Art.text(ci, "GO!", Vector2(w / 2, my), Color(0.5, 1, 1, 1.0 - g.state_t * 2.0), true, 1)
	if g.state == "clear":
		Art.text(ci, "LEVEL %d CLEAR" % g.level, Vector2(w / 2, my), Color(0.6, 1, 0.8), true, 1)
		Art.text(ci, "NEXT: ONE MORE OF YOU", Vector2(w / 2, my + 18), Color(1, 0.6, 0.9), false, 1)
	# LAN: a human with no shard yet, near the end of a level, is about to turn
	if g.multi() and g.state == "play" and p.get("alive", false) and int(p.get("got", 0)) == 0 and g.lvl_time() - g.lt < 5.0:
		Art.text(ci, "NO SHARD YET!  TAKE ONE OR TURN", Vector2(w / 2, 44), Color(1, 0.4, 0.4, 0.6 + 0.4 * sin(t_ui * 10.0)), false, 1)
	# tips sit below the arena, on black, where nothing else is
	if tip_t > 0.0 and g.state != "clear":
		Art.text(ci, tip, Vector2(w / 2, h - 18), Color(1, 1, 0.75, clampf(tip_t, 0.0, 1.0)), false, 1)
	if stick_on and screen == "play":
		var so := stick_o - Vector2(0, ui_oy)
		ci.draw_arc(so, stick_r, 0, TAU, 24, Color(1, 1, 1, 0.15), 1.0)
		ci.draw_circle(so + (stick_p - stick_o).limit_length(stick_r), 5, Color(0.4, 1, 1, 0.3))
	if save["control"] == "tilt_hold" and screen == "play" and touches.is_empty() and g.state == "play":
		Art.text(ci, "TOUCH ANYWHERE TO GO", Vector2(w / 2, h / 2 + 24), Color(1, 1, 1, 0.5 + 0.5 * sin(t_ui * 6.0)), false, 1)
	if screen == "paused":
		_dim(ci)
		Art.text(ci, "PAUSED", Vector2(w / 2, h / 2 - 44), Color(1, 0.4, 0.85), true, 1)
		_btn(ci, Rect2(w / 2 - 75, h / 2 - 16, 150, 28), "CONTINUE", _resume, "primary", Color(0.4, 1, 1))
		_btn(ci, Rect2(w / 2 - 75, h / 2 + 20, 150, 24), "QUIT TO MENU", func(): game.process_mode = Node.PROCESS_MODE_INHERIT; _title())
	if screen == "over":
		if g.multi(): _draw_mp_over(ci)
		else: _draw_over(ci)

func _draw_title(ci: CanvasItem) -> void:
	var w := view.x; var h := view.y
	ci.draw_rect(_full(), Color(0.02, 0.0, 0.05, 0.8))
	var cols := [Color(1, 0.25, 0.7), Color(1, 0.5, 0.1), Color(0.62, 0.38, 1.0)]
	for k in range(3, 0, -1):
		# three faint echoes of the logo, a pixel or two behind it, drifting slowly
		var off := Vector2(sin(t_ui * 1.3 + k) * 0.8 + k * 1.0, cos(t_ui * 1.1 + k) * 0.5 + k * 0.6).round()
		_big(ci, "ECHOES", Vector2(w / 2, 26) + off, Color(cols[k - 1], 0.22), 2)
	_big(ci, "ECHOES", Vector2(w / 2, 26), Color(0.4, 1, 1), 2)
	Art.text(ci, "EVERY LEVEL, YOUR PAST SELVES COME BACK.  DON'T TOUCH THEM.", Vector2(w / 2, 47), Color(1, 1, 1), false, 1)
	var m := _solo_mode()
	_mode_row(ci, 58, m, _pick_mode, false, 228.0)
	var mc: Color = EchoGame.MODE_COLS[m]
	var x := w / 2 - 114
	var pr := Rect2(x, 85, 228, 34)
	_btn(ci, pr, "", func(): daily_run = false; _start_solo(), "primary", mc)
	Art.text(ci, "PLAY " + EchoGame.MODE_NAMES[m], Vector2(w / 2, 88), Color(0.03, 0.01, 0.07), true, 1, Color(0, 0, 0, 0))
	var nm := next_medal(m)
	var sub := "GRAB 5 SHARDS.  DODGE YOURSELF."
	# at most 34 characters, so it always fits inside the button
	if best_of(m) > 0: sub = "BEST %d  -  %s AT LEVEL %d" % [best_of(m), nm[1], nm[0]] if not nm.is_empty() else "BEST %d  -  ALL MEDALS" % best_of(m)
	Art.text(ci, sub, Vector2(w / 2, 107), Color(0.03, 0.01, 0.07, 0.8), false, 1, Color(0, 0, 0, 0))
	_btn(ci, Rect2(x, 125, 111, 24), "DAILY RUN", func(): daily_run = true; _start_solo(), "secondary", Color(1, 0.8, 0.25))
	_btn(ci, Rect2(x + 117, 125, 111, 24), "PROGRESS", func(): screen = "stats")
	# your medals in this mode, beside PLAY
	for k in MEDALS.size():
		var md: Array = MEDALS[k]
		var mpos := Vector2(pr.end.x + 14 + k * 14, pr.get_center().y)
		if level_of(m) >= int(md[0]): ci.draw_circle(mpos, 5.0, md[2]); ci.draw_circle(mpos, 2.0, Color(1, 1, 1, 0.8))
		else: ci.draw_arc(mpos, 5.0, 0, TAU, 14, Color(md[2], 0.45), 1.0)
	var tw := (228.0 - 12.0) / 3.0
	_btn(ci, Rect2(x, 155, tw, 24), "HOST LAN", _host)
	_btn(ci, Rect2(x + tw + 6, 155, tw, 24), "JOIN LAN", _go_join)
	_btn(ci, Rect2(x + 2 * (tw + 6), 155, tw, 24), "SETTINGS", func(): screen = "settings")
	Art.text(ci, _daily_line(), Vector2(w / 2, 188), Color(1, 0.8, 0.3, 0.9), false, 1)

## NORMAL / HARD / EXTREME. Locked modes say what opens them (solo only; a LAN match can play any mode).
func _mode_row(ci: CanvasItem, y: float, cur: String, f: Callable, all_open: bool, width := 228.0) -> void:
	var gap := 6.0
	var bw := (width - gap * 2) / 3.0
	var x0 := view.x / 2 - width / 2
	for i in EchoGame.MODES.size():
		var m: String = EchoGame.MODES[i]
		var open := all_open or unlocked(m)
		var r := Rect2(x0 + i * (bw + gap), y, bw, 22)
		if open: _btn(ci, r, EchoGame.MODE_NAMES[m], func(): f.call(m), "selected" if m == cur else "secondary", EchoGame.MODE_COLS[m])
		else: _btn(ci, r, EchoGame.MODE_NAMES[m], func(): f.call(m), "locked")

func _pick_control(c: String) -> void:
	save["control"] = c; tilt_have = false; _save()
	# the first time she picks a tilt control, learn which way this phone tilts
	if c != "touch" and not save.has("tilt_r"): _go_calib("settings")

func _draw_settings(ci: CanvasItem) -> void:
	var w := view.x; var h := view.y
	_dim(ci)
	_heading(ci, "SETTINGS")
	var x0 := w / 2 - 182
	var ox := x0 + 72
	var lc := LBL
	Art.text(ci, "CONTROL", Vector2(x0, 35), lc)
	var opts := [["touch", "TOUCH"], ["tilt", "TILT"], ["tilt_hold", "TILT + TOUCH"]]
	for i in opts.size():
		var o: Array = opts[i]
		_button(ci, Rect2(ox + i * 96, 28, 90, 22), o[1], func(): _pick_control(o[0]), save["control"] == o[0], Color(0.4, 1, 1))
	var desc := {"touch": "DRAG ANYWHERE ON THE SCREEN TO MOVE.", "tilt": "TILT THE PHONE. HOW YOU HOLD IT AT 'GO' IS LEVEL.", "tilt_hold": "TILT TO STEER. TOUCH ANYWHERE TO GO, LIFT TO STOP."}
	Art.text(ci, desc[save["control"]], Vector2(ox, 54), Color(0.85, 0.85, 0.9))
	Art.text(ci, "TILT SPEED", Vector2(x0, 73), lc)
	var sn := ["LOW", "MEDIUM", "HIGH"]
	for i in 3:
		_button(ci, Rect2(ox + i * 96, 66, 90, 22), sn[i], func(): save["sens"] = i; _save(), int(save["sens"]) == i)
	Art.text(ci, "INVERT X", Vector2(x0, 101), lc)
	_button(ci, Rect2(ox, 94, 90, 22), "ON" if save["flip_x"] else "OFF", func(): save["flip_x"] = not save["flip_x"]; _save(), save["flip_x"])
	Art.text(ci, "INVERT Y", Vector2(ox + 96, 101), lc)
	_button(ci, Rect2(ox + 150, 94, 80, 22), "ON" if save["flip_y"] else "OFF", func(): save["flip_y"] = not save["flip_y"]; _save(), save["flip_y"])
	Art.text(ci, "SOUND", Vector2(x0, 129), lc)
	_button(ci, Rect2(ox, 122, 90, 22), "ON" if save["sound"] else "OFF", func(): save["sound"] = not save["sound"]; sound.set_on(save["sound"]); _save(), save["sound"])
	Art.text(ci, "CRT", Vector2(ox + 96, 129), lc)
	_button(ci, Rect2(ox + 150, 122, 80, 22), "ON" if save["crt"] else "OFF", func(): save["crt"] = not save["crt"]; crt.visible = save["crt"]; _save(), save["crt"])
	_btn(ci, Rect2(ox, 150, 134, 22), "CALIBRATE TILT" + ("  !" if not save.has("tilt_r") else ""), func(): _go_calib("settings"))
	_btn(ci, Rect2(ox + 140, 150, 140, 22), "NAME: " + _my_name(), _go_name)
	# a live tilt test: tap the box to re-centre
	var box := Rect2(w / 2 + 126, 94, 62, 50)
	buttons.append([box, func(): tilt_have = false])
	ci.draw_rect(box, Color(0.07, 0.03, 0.12, 0.95)); ci.draw_rect(box, Color(1, 0.4, 0.85, 0.6), false, 1.0)
	Art.text(ci, "TILT TEST", box.position + Vector2(box.size.x / 2, 3), Color(0.8, 0.8, 0.9), false, 1)
	var t := _tilt()
	ci.draw_circle(box.get_center() + Vector2(4, 5) + Vector2(t.x * 24, t.y * 16), 4, Color(0.4, 1, 1))
	_btn(ci, Rect2(x0, h - 30, 110, 24), "BACK", _title)

func _draw_join(ci: CanvasItem) -> void:
	var w := view.x; var h := view.y
	_dim(ci)
	_heading(ci, "JOIN LAN GAME")
	Art.text(ci, "SAME WI-FI OR HOTSPOT AS THE HOST.  GAMES FOUND:", Vector2(w / 2, 30), Color(0.85, 0.85, 0.9), false, 1)
	var y := 44.0
	if net.hosts.is_empty():
		Art.text(ci, "LOOKING" + ".".repeat(int(t_ui * 2.0) % 4), Vector2(w / 2, y + 8), Color(0.6, 0.6, 0.7), false, 1)
	for ip in net.hosts:
		var hst: Dictionary = net.hosts[ip]
		var label := "%s   %s   %d PLAYER%s%s" % [hst["name"], ip, int(hst["n"]), "" if int(hst["n"]) == 1 else "S", "" if hst["open"] else "  (PLAYING)"]
		_btn(ci, Rect2(w / 2 - 150, y, 300, 24), label, func(): _join(ip), "primary" if hst["open"] else "locked", Color(0.4, 1, 1))
		y += 28.0
	_btn(ci, Rect2(w / 2 - 150, h - 58, 146, 24), "ENTER ADDRESS", func(): keypad_ip = String(save.get("last_ip", "")); screen = "keypad")
	_btn(ci, Rect2(w / 2 + 4, h - 58, 146, 24), "BACK", _leave)
	Art.text(ci, "NOT LISTED?  ASK THE HOST FOR THE ADDRESS ON THEIR SCREEN.", Vector2(w / 2, h - 26), Color(0.7, 0.7, 0.8), false, 1)

func _draw_keypad(ci: CanvasItem) -> void:
	var w := view.x; var h := view.y
	_dim(ci)
	_heading(ci, "HOST ADDRESS")
	var fr := Rect2(w / 2 - 110, 27, 174, 20)
	ci.draw_rect(fr, Color(0, 0, 0, 0.9)); ci.draw_rect(fr, Color(0.4, 1, 1, 0.8), false, 1.0)
	Art.text(ci, keypad_ip + ("_" if int(t_ui * 2) % 2 == 0 else " "), fr.get_center() - Vector2(0, 4), Color(1, 1, 1), false, 1)
	var keys := ["1", "2", "3", "4", "5", "6", "7", "8", "9", ".", "0", "<"]
	for i in keys.size():
		var k: String = keys[i]
		_btn(ci, Rect2(w / 2 - 110 + (i % 3) * 60, 54 + (i / 3) * 30, 54, 26), "DEL" if k == "<" else k, func(): _kp(k), "secondary", Color(0.4, 1, 1), true)
	_btn(ci, Rect2(w / 2 + 76, 54, 80, 30), "JOIN", func(): _join(keypad_ip), "primary", Color(0.4, 1, 1), true)
	_btn(ci, Rect2(w / 2 + 76, 90, 80, 24), "BACK", func(): screen = "join")

func _draw_lobby(ci: CanvasItem) -> void:
	var w := view.x; var h := view.y
	_dim(ci)
	var is_host: bool = net.hosting
	_heading(ci, "LAN GAME")
	if is_host:
		var ips := net.local_ips()
		Art.text(ci, "YOUR ADDRESS:  " + ("  /  ".join(ips) if not ips.is_empty() else "NOT ON A NETWORK"), Vector2(w / 2, 27), Color(1, 0.85, 0.4), false, 1)
		Art.text(ci, "FRIENDS: JOIN LAN GAME, ON THE SAME WI-FI OR YOUR HOTSPOT.", Vector2(w / 2, 38), Color(0.8, 0.8, 0.9), false, 1)
		_mode_row(ci, 50, mp_mode, _host_mode, true, 240.0)
	else:
		Art.text(ci, "CONNECTED.  WAITING FOR THE HOST TO START" + ".".repeat(int(t_ui * 2.0) % 4), Vector2(w / 2, 30), Color(0.8, 0.8, 0.9), false, 1)
		Art.text(ci, "MODE:  " + EchoGame.MODE_NAMES.get(mp_mode, "NORMAL"), Vector2(w / 2, 52), EchoGame.MODE_COLS.get(mp_mode, Color.WHITE), true, 1)
	# players, in two columns of four
	for i in roster.size():
		var r: Array = roster[i]
		var col: Color = EchoGame.P_COLS[i % EchoGame.P_COLS.size()]
		var p := Vector2(w / 2 - 120 + (i / 4) * 130, 84 + (i % 4) * 15)
		ci.draw_circle(p + Vector2(0, 4), 4.0, col); ci.draw_circle(p + Vector2(0, 4), 2.4, Color(1, 1, 1))
		var me_: bool = (is_host and r[0] == 1) or (not is_host and r[0] == multiplayer.get_unique_id())
		Art.text(ci, String(r[1]) + ("  (YOU)" if me_ else ""), p + Vector2(10, 0), col)
	if is_host:
		if roster.size() < 2: Art.text(ci, "WAITING FOR PLAYERS  (YOU CAN START ALONE)", Vector2(w / 2, h - 46), Color(0.6, 0.6, 0.7), false, 1)
		_btn(ci, Rect2(w / 2 - 122, h - 32, 140, 26), "START", _host_start, "primary", Color(0.4, 1, 1))
		_btn(ci, Rect2(w / 2 + 24, h - 32, 98, 26), "CLOSE", _leave)
	else:
		_btn(ci, Rect2(w / 2 - 60, h - 32, 120, 26), "LEAVE", _leave)

## the big font, drawn at k times for the logo and big numbers
func _big(ci: CanvasItem, s: String, c: Vector2, col: Color, k: int) -> void:
	var f := Art.t("font_big")
	var cw := 12 * k; var ch := 16 * k
	var x0 := c.x - s.length() * cw / 2.0
	for i in s.length():
		var code := s.unicode_at(i) - 32
		ci.draw_texture_rect_region(f, Rect2(Vector2(x0 + i * cw, c.y - ch / 2.0).round(), Vector2(cw, ch)), Rect2((code % 16) * 12, (code / 16) * 16, 12, 16), col)

func _draw_over(ci: CanvasItem) -> void:
	var w := view.x; var h := view.y
	var a := clampf((t_ui - over_at - REPLAY) / 0.6, 0.0, 1.0)
	if a <= 0.0: return             # the death replay is still playing
	ci.draw_rect(_full(), Color(0.02, 0, 0.05, 0.97 * a))
	var g := game
	var mc: Color = EchoGame.MODE_COLS[g.mode]
	var badge: String = "DAILY RUN" if daily_run else EchoGame.MODE_NAMES[g.mode]
	var bwid: int = badge.length() * 12 + 16
	ci.draw_rect(Rect2(w / 2 - bwid / 2.0, 5, bwid, 20), Color(mc, 0.85 * a))
	Art.text(ci, badge, Vector2(w / 2, 7), Color(0.03, 0.01, 0.07, a), true, 1, Color(0, 0, 0, 0))
	# 1: the score.  2: one headline.  3: the details.  4: an unlock, as a badge.
	_big(ci, "%d" % g.score_of(1), Vector2(w / 2, 46), Color(1, 1, 1, a), 2)
	var best_label := "TODAY'S BEST" if daily_run else "%s BEST" % EchoGame.MODE_NAMES[g.mode]
	var best_val := int(save.get("daily_best", 0)) if daily_run else best_of(g.mode)
	var why := "TIME UP  -  %d OF 5 SHARDS" % g.got if g.killed_by < 0 else "CAUGHT BY YOUR LEVEL %d SELF" % (g.killed_by + 1)
	if new_best: Art.text(ci, "NEW %s!" % best_label, Vector2(w / 2, 68), Color(1, 0.85, 0.3, a * (0.7 + 0.3 * sin(t_ui * 8.0))), true, 1)
	else: Art.text(ci, "LEVEL %d   -   %d ECHOES" % [g.level, g.runs.size()], Vector2(w / 2, 68), Color(mc, a), true, 1)
	var line2 := ("LEVEL %d  -  %d ECHOES  -  " % [g.level, g.runs.size()] if new_best else "") + why
	Art.text(ci, line2, Vector2(w / 2, 90), Color(1, 0.62, 0.82, a), false, 1)
	Art.text(ci, "SHARDS %d   +   CLOSE CALLS %d   +   TIME %d" % [g.sc_shards, g.sc_close, g.sc_bonus], Vector2(w / 2, 102), Color(LBL, a), false, 1)
	if not new_best: Art.text(ci, "%s  %d" % [best_label, best_val], Vector2(w / 2, 114), Color(LBL, a), false, 1)
	if daily_run: Art.text(ci, "DAILY STREAK  %d" % int(save.get("streak", 0)), Vector2(w / 2, 126), Color(1, 0.8, 0.3, a), false, 1)
	Art.text(ci, "TIP: " + over_tip, Vector2(w / 2, 140), Color(0.5, 0.55, 0.68, a), false, 1)
	if just_unlocked != "":
		var uc: Color = EchoGame.MODE_COLS[just_unlocked]
		var ub := Rect2(w / 2 - 120, 152, 240, 24)
		ci.draw_rect(ub, Color(uc, 0.15 * a)); ci.draw_rect(ub, Color(uc, a), false, 1.0)
		Art.text(ci, "%s UNLOCKED" % EchoGame.MODE_NAMES[just_unlocked], Vector2(ub.position.x + 8, ub.get_center().y - 4), Color(uc, a))
		if t_ui - over_at > REPLAY + 1.0:
			_btn(ci, Rect2(ub.end.x - 94, ub.position.y + 3, 90, 18), "PLAY " + EchoGame.MODE_NAMES[just_unlocked], func(): save["mode"] = just_unlocked; _save(); daily_run = false; _start_solo(), "primary", uc)
	if t_ui - over_at > REPLAY + 1.0:
		_btn(ci, Rect2(w / 2 - 152, h - 32, 132, 26), "TRY AGAIN", _start_solo, "primary", Color(0.4, 1, 1))
		_btn(ci, Rect2(w / 2 - 14, h - 32, 80, 26), "SHARE", _share, "secondary", Color(1, 0.8, 0.25))
		_btn(ci, Rect2(w / 2 + 72, h - 32, 80, 26), "MENU", _title)

func _mp_ranked() -> Array:
	# the winner first, then everyone else by score
	var g := game
	var ids: Array = g.order.duplicate()
	ids.sort_custom(func(x, y):
		if x == g.winner: return true
		if y == g.winner: return false
		return g.players[x]["score"] > g.players[y]["score"])
	return ids

func _draw_mp_over(ci: CanvasItem) -> void:
	var w := view.x; var h := view.y
	var a := clampf((t_ui - over_at) / 0.8, 0.0, 1.0)
	ci.draw_rect(_full(), Color(0.02, 0, 0.05, 0.86 * a))
	var g := game
	var title := "NOBODY SURVIVED"
	if g.winner >= 0: title = "YOU WIN!" if g.winner == g.local_id else "%s WINS" % g.players[g.winner]["name"]
	Art.text(ci, title, Vector2(w / 2, 10), Color(1, 0.85, 0.3, a) if g.winner == g.local_id else Color(1, 0.4, 0.7, a), true, 1)
	Art.text(ci, "%s  -  LAST HUMAN STANDING AFTER LEVEL %d" % [EchoGame.MODE_NAMES[g.mode], g.level], Vector2(w / 2, 30), Color(EchoGame.MODE_COLS[g.mode], a), false, 1)
	var ids := _mp_ranked()
	var y := 46.0
	for i in ids.size():
		var q: Dictionary = g.players[ids[i]]
		var name: String = "YOU" if ids[i] == g.local_id else q["name"]
		Art.text(ci, "%d.  %s%s" % [i + 1, name, "   WINNER" if ids[i] == g.winner else ""], Vector2(w / 2 - 100, y), Color(q["col"], a))
		Art.text(ci, "%d" % q["score"], Vector2(w / 2 + 100, y), Color(1, 1, 1, a), false, 2)
		y += 14.0
	if t_ui - over_at > 1.3:
		if g.role == "host":
			_btn(ci, Rect2(w / 2 - 152, h - 32, 132, 26), "PLAY AGAIN", _back_to_lobby, "primary", Color(0.4, 1, 1))
			_btn(ci, Rect2(w / 2 - 14, h - 32, 80, 26), "SHARE", _share, "secondary", Color(1, 0.8, 0.25))
			_btn(ci, Rect2(w / 2 + 72, h - 32, 80, 26), "END", _leave)
		else:
			Art.text(ci, "WAITING FOR THE HOST" + ".".repeat(int(t_ui * 2.0) % 4), Vector2(w / 2, h - 46), Color(0.7, 0.7, 0.8), false, 1)
			_btn(ci, Rect2(w / 2 - 104, h - 32, 100, 26), "SHARE", _share, "secondary", Color(1, 0.8, 0.25))
			_btn(ci, Rect2(w / 2 + 4, h - 32, 100, 26), "LEAVE", _leave)

func _draw_stats(ci: CanvasItem) -> void:
	var w := view.x; var h := view.y
	_dim(ci)
	_heading(ci, "PROGRESS")
	# medals, per mode
	var mx0 := w / 2 - 188
	for i in EchoGame.MODES.size():
		var m: String = EchoGame.MODES[i]
		var x := mx0 + i * 128
		Art.text(ci, EchoGame.MODE_NAMES[m], Vector2(x, 27), EchoGame.MODE_COLS[m])
		for k in MEDALS.size():
			var md: Array = MEDALS[k]
			var c := Vector2(x + 58 + k * 13, 31)
			if level_of(m) >= int(md[0]): ci.draw_circle(c, 4.5, md[2])
			else: ci.draw_arc(c, 4.5, 0, TAU, 12, Color(md[2], 0.4), 1.0)
	var st: Dictionary = save["stats"]
	var x0 := w / 2 - 188
	var rows := [["RUNS", st.get("runs", 0)], ["MINUTES", int(float(st.get("time", 0.0)) / 60.0)], ["SHARDS", st.get("shards", 0)],
		["CLOSE CALLS", st.get("close", 0)], ["LEVELS", st.get("levels", 0)], ["CAUGHT", st.get("caught", 0)], ["TIME UPS", st.get("timeups", 0)],
		["BEST NORMAL", "LV %d" % level_of("normal")], ["BEST HARD", "LV %d" % level_of("hard")], ["BEST EXTREME", "LV %d" % level_of("extreme")],
		["DAILY STREAK", save.get("streak", 0)], ["LONGEST", save.get("best_streak", 0)]]
	for i in rows.size():
		var y := 44.0 + i * 11.0
		Art.text(ci, rows[i][0], Vector2(x0, y), LBL)
		Art.text(ci, str(rows[i][1]), Vector2(x0 + 128, y), Color(1, 1, 1), false, 2)
	var done: Array = save["missions"]
	var mx := w / 2 - 50
	Art.text(ci, "MISSIONS  %d / %d" % [done.size(), MISSIONS.size()], Vector2(mx, 44), Color(1, 0.8, 0.3))
	for i in MISSIONS.size():
		var mi: Array = MISSIONS[i]
		var y := 55.0 + i * 9.5
		var ok := done.has(mi[0])
		ci.draw_rect(Rect2(mx, y, 6, 6), Color(1, 0.8, 0.25) if ok else Color(1, 1, 1, 0.15))
		Art.text(ci, mi[1], Vector2(mx + 10, y), Color(1, 0.85, 0.35) if ok else Color(0.9, 0.9, 0.95))
		var pg := "" if ok else _mission_progress(mi[0])
		Art.text(ci, mi[2], Vector2(mx + 98, y), LBL if not ok else Color(0.85, 0.75, 0.5))
		if pg != "": Art.text(ci, pg, Vector2(w - 6, y), Color(1, 1, 1, 0.85), false, 2)
	_btn(ci, Rect2(x0, h - 28, 110, 24), "BACK", _title)
	_btn(ci, Rect2(x0 + 118, h - 28, 110, 24), "STYLE", func(): screen = "style", "secondary", Color(1, 0.8, 0.25))

func _draw_style(ci: CanvasItem) -> void:
	var w := view.x; var h := view.y
	_dim(ci)
	_heading(ci, "STYLE")
	var x0 := w / 2 - 182
	Art.text(ci, "TRAIL", Vector2(x0, 35), LBL)
	for i in TRAILS.size():
		var t: Array = TRAILS[i]
		var r := Rect2(x0 + 70 + i * 74, 28, 70, 22)
		if _cos_open(t[2]): _button(ci, r, t[1], func(): save["trail"] = t[0]; _save(), String(save.get("trail", "classic")) == t[0])
		else:
			_btn(ci, r, t[1], func(): _note("UNLOCK: " + t[2]), "locked")
			Art.text(ci, t[2], r.get_center() + Vector2(0, 13), Color(0.5, 0.5, 0.6), false, 1)
	Art.text(ci, "COLOURS", Vector2(x0, 79), LBL)
	for i in PALETTES.size():
		var pl: Array = PALETTES[i]
		var r := Rect2(x0 + 70 + i * 98, 72, 94, 22)
		if _cos_open(pl[2]): _button(ci, r, pl[1], func(): save["palette"] = pl[0]; _save(), String(save.get("palette", "neon")) == pl[0])
		else:
			_btn(ci, r, pl[1], func(): _note("UNLOCK: " + pl[2]), "locked")
			Art.text(ci, pl[2], r.get_center() + Vector2(0, 13), Color(0.5, 0.5, 0.6), false, 1)
	# a little preview: you, running a loop with your trail, among echoes in your colours
	var box := Rect2(w / 2 - 110, 112, 220, 70)
	ci.draw_rect(box, Color(0.04, 0.02, 0.08)); ci.draw_rect(box, Color(1, 0.3, 0.85, 0.7), false, 1.0)
	var cols: Array = PALETTE_COLS.get(String(save.get("palette", "neon")), PALETTE_COLS["neon"])
	for k in 6:
		var ep := box.get_center() + Vector2(cos(t_ui * 0.7 + k) * 80, sin(t_ui * 0.9 + k * 1.7) * 24)
		ci.draw_circle(ep, 3.5, cols[k]); ci.draw_circle(ep, 1.9, Color(0.02, 0, 0.05))
	var ts := String(save.get("trail", "classic"))
	for k in 14:
		var tt := t_ui - k * 0.04
		var tp := box.get_center() + Vector2(cos(tt * 2.0) * 50, sin(tt * 2.0) * 20)
		var tc := Color(0.4, 1, 1)
		match ts:
			"gold": tc = EchoGame.GOLD
			"rainbow": tc = Color.from_hsv(fmod(tt * 0.3, 1.0), 0.75, 1.0)
			"spark": tc = Color(1, 1, 1)
		var fa := 1.0 - k / 14.0
		if ts == "spark": ci.draw_rect(Rect2((tp + Vector2(sin(k * 7.0) * 3, cos(k * 5.0) * 3)).round(), Vector2(1, 1)), Color(tc, fa))
		else: ci.draw_circle(tp, 4.3 * fa, Color(tc, 0.26 * fa))
	var pp := box.get_center() + Vector2(cos(t_ui * 2.0) * 50, sin(t_ui * 2.0) * 20)
	ci.draw_circle(pp, 5.1, Color(1, 1, 1)); ci.draw_circle(pp, 4.1, Color(0.4, 1, 1)); ci.draw_circle(pp, 2.3, Color(1, 1, 1))
	_btn(ci, Rect2(x0, h - 28, 110, 24), "BACK", func(): screen = "stats")

func _draw_name(ci: CanvasItem) -> void:
	var w := view.x; var h := view.y
	_dim(ci)
	_heading(ci, "YOUR NAME")
	Art.text(ci, "SHOWN TO THE OTHERS IN LAN GAMES.  LETTERS AND NUMBERS, UP TO 10.", Vector2(w / 2, 30), Color(0.8, 0.8, 0.9), false, 1)
	var fr := Rect2(w / 2 - 90, 50, 180, 26)
	ci.draw_rect(fr, Color(0, 0, 0, 0.9)); ci.draw_rect(fr, Color(0.4, 1, 1, 0.9), false, 1.0)
	var t := _name_clean(name_edit.text) if name_edit else ""
	Art.text(ci, t + ("_" if int(t_ui * 2) % 2 == 0 else " "), fr.get_center() - Vector2(0, 8), Color(1, 1, 1), true, 1)
	Art.text(ci, "TAP THE BOX IF THE KEYBOARD DOESN'T SHOW", Vector2(w / 2, 84), Color(0.6, 0.6, 0.7), false, 1)
	buttons.append([fr, func(): if name_edit: name_edit.grab_focus()])
	_btn(ci, Rect2(w / 2 - 122, 104, 140, 26), "DONE", _name_done, "primary", Color(0.4, 1, 1))
	_btn(ci, Rect2(w / 2 + 24, 104, 98, 26), "CANCEL", func(): _name_close(); screen = "settings")

# ------------------------------------------------------------------ the share card: you and every one of your past selves
func _card_date() -> String:
	var d := _today()
	return "%04d-%02d-%02d" % [d / 10000, (d / 100) % 100, d % 100]

func _draw_card_sq(ci: CanvasItem, S: Vector2) -> void:
	var g := game
	ci.draw_rect(Rect2(Vector2.ZERO, S), Color(0.02, 0.0, 0.05))
	var cx := S.x / 2
	# the logo and what was played
	for k in range(3, 0, -1):
		_big(ci, "ECHOES", Vector2(cx + k * 1.5, 26 + k * 0.8), Color([Color(1, 0.25, 0.7), Color(1, 0.5, 0.1), Color(0.62, 0.38, 1.0)][k - 1], 0.35), 2)
	_big(ci, "ECHOES", Vector2(cx, 26), Color(0.4, 1, 1), 2)
	var mc: Color = EchoGame.MODE_COLS[g.mode]
	var badge: String = ("DAILY RUN  " + _card_date()) if daily_run and not g.multi() else (EchoGame.MODE_NAMES[g.mode] + ("  LAN" if g.multi() else ""))
	var bwid: int = badge.length() * 6 + 14
	ci.draw_rect(Rect2(cx - bwid / 2.0, 46, bwid, 13), mc)
	Art.text(ci, badge, Vector2(cx, 49), Color(0.03, 0.01, 0.07), false, 1, Color(0, 0, 0, 0))
	# every run you made, as neon trails in the arena
	var ar := EchoGame.ARENA
	var k := (S.x - 24.0) / ar.size.x
	var oc := Vector2(cx, 66 + ar.size.y * k / 2.0)
	var ab := Rect2(oc + ar.position * k, ar.size * k)
	for x in range(0, int(ab.size.x), 12): ci.draw_line(ab.position + Vector2(x, 0), ab.position + Vector2(x, ab.size.y), Color(0.35, 0.15, 0.6, 0.2), 1.0)
	for y in range(0, int(ab.size.y), 12): ci.draw_line(ab.position + Vector2(0, y), ab.position + Vector2(ab.size.x, y), Color(0.35, 0.15, 0.6, 0.2), 1.0)
	ci.draw_rect(ab, Color(1.0, 0.3, 0.85, 0.9), false, 1.0)
	for i in g.runs.size():
		var pts: PackedVector2Array = g.runs[i]["pts"]
		var line := PackedVector2Array()
		for j in range(0, pts.size(), 3): line.append(oc + pts[j] * k)
		if line.size() >= 2:
			var col := g.echo_col(i)
			ci.draw_polyline(line, Color(col, 0.22), 3.0)
			ci.draw_polyline(line, Color(col, 0.9), 1.0)
	var pm: Dictionary = g.me()
	if not pm.is_empty():
		var pp: Vector2 = oc + pm["pos"] * k
		if not g.multi() and g.state == "dead":
			# where you were caught
			ci.draw_line(pp + Vector2(-6, -6), pp + Vector2(6, 6), Color(1, 1, 1), 2.0)
			ci.draw_line(pp + Vector2(-6, 6), pp + Vector2(6, -6), Color(1, 1, 1), 2.0)
			# the label goes above the X, or below it when the X is at the top edge (clear of the mode badge)
			var top := oc.y + EchoGame.ARENA.position.y * k
			var lp := pp + (Vector2(0, -16) if pp.y - 16.0 > top + 2.0 else Vector2(0, 9))
			lp.x = clampf(lp.x, 38.0, S.x - 38.0)
			Art.text(ci, "CAUGHT HERE", lp, Color(1, 1, 1), false, 1)
		else:
			ci.draw_circle(pp, 6.0, Color(0.4, 1, 1, 0.3)); ci.draw_circle(pp, 3.5, Color(0.4, 1, 1)); ci.draw_circle(pp, 2.0, Color(1, 1, 1))
	# the numbers
	var ty := ab.end.y + 10
	if g.multi():
		var res := "I WON!" if g.winner == g.local_id else "%d PLAYERS" % g.order.size()
		_big(ci, res, Vector2(cx, ty + 22), Color(1, 0.85, 0.3), 2)
		Art.text(ci, "LAST HUMAN STANDING AFTER LEVEL %d" % g.level, Vector2(cx, ty + 46), mc, false, 1)
	else:
		var sc := "%d" % g.score_of(1)
		_big(ci, sc, Vector2(cx, ty + 22), Color(1, 1, 1), 3 if sc.length() <= 6 else 2)
		Art.text(ci, "LEVEL %d" % g.level, Vector2(cx, ty + 44), mc, true, 1)
		var why := "  -  CAUGHT BY MY LEVEL %d SELF" % (g.killed_by + 1) if g.killed_by >= 0 else ""
		Art.text(ci, "ME VS %d PAST SELVES%s" % [g.runs.size(), why], Vector2(cx, ty + 62), Color(1, 0.62, 0.9), false, 1)
	Art.text(ci, "CAN YOU BEAT ME?", Vector2(cx, S.y - 30), Color(1, 0.85, 0.35), true, 1)
	Art.text(ci, STORE_LINK if STORE_LINK != "" else "EVERY LEVEL, YOUR PAST SELVES COME BACK.", Vector2(cx, S.y - 12), Color(0.6, 0.62, 0.75), false, 1)
