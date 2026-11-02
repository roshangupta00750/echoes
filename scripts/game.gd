class_name EchoGame extends Node2D
## ECHOES: grab five shards per level. Every level, each player's run comes back as an echo that replays
## exactly what they did. Touch any echo and you're out.
##  - solo: one player; the clock running out also ends you.
##  - host: runs the match for everyone on the LAN and sends snapshots.
##  - client: draws the host's snapshots; moves its own player locally and reports where it is.

signal event(kind: String, data: Dictionary)
signal report(kind: String, data: Dictionary)   # client -> host: "I was caught", "I took the shard"

const ARENA := Rect2(-165, -78, 330, 156)
const SHARDS := 5
const LEVEL_TIME := 15.0           # NORMAL, levels 1-10 (see lvl_time)
const P_R := 3.5                   # a player's radius
const PICK_R := 14.0               # touching the shard's glow counts
const SPEED := 92.0
const MODES := ["normal", "hard", "extreme"]
const MODE_NAMES := {"normal": "NORMAL", "hard": "HARD", "extreme": "EXTREME"}
const MODE_COLS := {"normal": Color(0.4, 1.0, 1.0), "hard": Color(1.0, 0.6, 0.15), "extreme": Color(1.0, 0.25, 0.3)}
const LEASH := 16.0                # EXTREME: how far the newest echo may bend off its path toward you
const LEASH_SPEED := 30.0
const SHARD_STILL := 4.0           # EXTREME: a shard nobody takes starts to drift after this long
const SHARD_DRIFT := 22.0
# LAN: caught players come back as zombies, steered by that person, and convert whoever they touch
const ZOMBIE_SPEED := 0.9          # of a human's speed
const ZOMBIE_GRACE := 1.5          # seconds a new zombie must wait before it can catch anyone
const ZOMBIE_PTS := 300            # x level, for each person a zombie catches
const LUNGE_RANGE := 34.0          # a zombie this close to a human lunges at them
const LUNGE_T := 0.35
const LUNGE_SPEED := 1.75          # x a human's speed, during a lunge
const LUNGE_CD := 3.0
const SILENT_OUT := 1.5            # LAN: a player the host hasn't heard from for this long is caught
## echo colours: none of them cyan (you) or gold (the shards)
const HUES := [Color(1.0, 0.25, 0.7), Color(1.0, 0.5, 0.1), Color(0.62, 0.38, 1.0), Color(0.55, 1.0, 0.25),
	Color(1.0, 0.3, 0.3), Color(0.3, 0.45, 1.0), Color(1.0, 0.62, 0.55), Color(0.88, 0.45, 1.0)]
## LAN players (and so their echoes): no gold, and no green (that's the zombies)
const P_COLS := [Color(0.3, 1.0, 1.0), Color(1.0, 0.5, 0.1), Color(1.0, 0.3, 0.7), Color(0.62, 0.38, 1.0),
	Color(1, 1, 1), Color(0.3, 0.45, 1.0), Color(1.0, 0.3, 0.3), Color(1.0, 0.62, 0.55)]
const GOLD := Color(1.0, 0.8, 0.25)
const ZCOL := Color(0.78, 1.0, 0.12)       # the zombie toxic yellow-green

var sound: Sound
var demo := false
var role := "solo"                 # solo, host, client
var mode := "normal"               # normal, hard, extreme
var local_id := 1
var players := {}                  # id -> {pos, vel, alive, score, got, col, name, rec, target}
var order: Array = []              # ids, in join order
var runs: Array = []               # {pts: PackedVector2Array, owner: int, lv: int}
var runs_ver := 0                  # bumped whenever runs change, so the host knows to send them
var level := 1
var shard := Vector2.ZERO
var shard_goal := Vector2.ZERO     # EXTREME: where a drifting shard is heading
var shard_t := 0.0                 # how long the current shard has waited
var got := 0                       # shards taken this level, by anyone
var lt := 0.0
var state := "ready"               # ready, play, clear, dead (solo), over (multiplayer)
var state_t := 0.0
var move_in := Vector2.ZERO
var near_cd := {}
var trail: Array = []
var parts: Array = []
var popups: Array = []
var rings: Array = []              # [pos, life, colour, size]: expanding rings for pickups, near misses, clears
var shake := 0.0
var flash := 0.0
var killed_by := -1                # solo: which level's echo got you (-1: the clock)
var killer := -1                   # solo: index of the echo that got you, for the death replay
var hold_t := 0.0                  # after a resume: 3-2-1 before the game moves again
var origin_pt := Vector2.ZERO      # where this level starts: away from where the echoes wait
var near_in := {}                  # "player:echo" -> true while you're brushing past it
var sc_shards := 0                 # the local player's score, split up for the results
var sc_close := 0
var sc_bonus := 0
var dead_runs: Array = []
var self_out := false              # client: I touched an echo and told the host; stop moving
var take_sent := -1                # client: which shard (by count) I've already claimed
var daily := false                 # the daily run: shards come from their own seeded sequence, the same for everyone
var shard_rng := RandomNumberGenerator.new()
var lunge_t := 0.0                 # the local zombie's lunge
var lunge_cd := 0.0
var zclaim_at := {}
var hues: Array = HUES             # the echo colours (the player's chosen palette, in solo)
var trail_style := "classic"       # the player's chosen trail: classic, spark, gold, rainbow                # local zombie: victim id -> when I last claimed a catch
var winner := -1
var rng := RandomNumberGenerator.new()
var beat := 0.0
var bpm := 128.0
var hit_stop := 0.0
var last_tick := 99

# ------------------------------------------------------------------ setup
func setup(role_: String, local: int, roster: Array, seed_ := 0, mode_ := "normal") -> void:
	role = role_; local_id = local
	mode = mode_ if mode_ in MODES else "normal"
	rng.seed = seed_ if seed_ != 0 else randi()
	shard_rng.seed = rng.seed ^ 0x5eed
	players.clear(); order.clear()
	for i in roster.size():
		var r: Array = roster[i]
		var id: int = r[0]
		order.append(id)
		players[id] = {"pos": Vector2.ZERO, "vel": Vector2.ZERO, "alive": true, "zombie": false, "grace": 0.0, "score": 0, "got": 0,
			"col": P_COLS[i % P_COLS.size()], "name": String(r[1]), "rec": PackedVector2Array(), "target": Vector2.ZERO,
			"seen": Time.get_ticks_msec()}
	_begin_level()

func me() -> Dictionary: return players.get(local_id, {})
func score_of(id: int) -> int: return int(players[id]["score"]) if players.has(id) else 0
func multi() -> bool: return role != "solo"
func alive_count() -> int:
	var n := 0
	for id in order: if players[id]["alive"]: n += 1
	return n

# ------------------------------------------------------------------ the difficulty modes
## NORMAL: levels 1-5 are what they always were; from level 8 the echoes get a little faster every level,
## and from level 11 there are 13 seconds. HARD and EXTREME start faster and tighter, and ramp the same way.
func lvl_time() -> float:
	match mode:
		"hard": return 14.0
		"extreme": return 13.0
	return 14.0 if level >= 11 else LEVEL_TIME

func g_delay() -> float:           # how long after you the echoes leave their start
	return {"normal": 1.0, "hard": 0.8, "extreme": 0.8}[mode]

func g_rest() -> float:            # frames an echo rests at its start between loops
	return {"normal": 60.0, "hard": 40.0, "extreme": 30.0}[mode]

func g_speed() -> float:           # echo replay speed
	var base: float = {"normal": 1.0, "hard": 1.15, "extreme": 1.25}[mode]
	return base + 0.03 * maxi(0, level - 7)

func g_r() -> float:               # an echo's radius
	return 4.5 if mode == "extreme" else 3.5

func max_echoes() -> int:          # no fading out in solo; a crowded LAN match keeps the newest 24
	return 24 if multi() else 60

## EXTREME: the echoes from the latest level are hunters. They still follow their path, but lean toward you.
func is_hunter(i: int) -> bool:
	return mode == "extreme" and not demo and not runs.is_empty() and int(runs[i]["lv"]) == int(runs.back()["lv"])

## where echo i is now: its replayed path, plus a hunter's lean
func echo_at(i: int, t := -1.0) -> Vector2:
	var off: Vector2 = runs[i].get("off", Vector2.ZERO)
	return ghost_pos(i, lt if t < 0.0 else t) + off

func _leash_tick(dt: float) -> void:
	for i in runs.size():
		var off: Vector2 = runs[i].get("off", Vector2.ZERO)
		var want := Vector2.ZERO
		if is_hunter(i) and ghost_live(i, lt):
			var base := ghost_pos(i, lt)
			var best := 1e9
			for id in order:
				var p: Dictionary = players[id]
				if not p["alive"]: continue
				var d: float = base.distance_to(p["pos"])
				if d < best: best = d; want = (p["pos"] - base).limit_length(LEASH)
		runs[i]["off"] = off.move_toward(want, LEASH_SPEED * dt)

const SPAWNS := [Vector2(0, 0), Vector2(-60, 0), Vector2(60, 0), Vector2(-120, 0), Vector2(120, 0),
	Vector2(-60, -45), Vector2(60, -45), Vector2(0, -45), Vector2(-60, 45), Vector2(60, 45), Vector2(0, 45),
	Vector2(-120, -45), Vector2(120, -45), Vector2(-120, 45), Vector2(120, 45)]

## each echo waits where its run started, so a level starts at the spot furthest from all of them
func _pick_origin() -> Vector2:
	if runs.is_empty(): return Vector2.ZERO
	var best: Vector2 = SPAWNS[0]; var bd := -1.0
	for c in SPAWNS:
		var md := 1e9
		for r in runs:
			var pts: PackedVector2Array = r["pts"]
			if pts.size() > 0: md = minf(md, c.distance_to(pts[0]))
		if md > bd + 0.01: bd = md; best = c
	return best

func spawn_pos(id: int) -> Vector2:
	var n := order.size()
	if players.has(id) and players[id].get("zombie", false):
		var k2 := order.find(id)
		var side := -1.0 if origin_pt.x >= 0.0 else 1.0
		return Vector2(side * 140.0, -60.0 + float(k2 % 5) * 30.0)
	if n <= 1: return origin_pt
	var k := order.find(id)
	var p := origin_pt + Vector2.from_angle(TAU * k / n - PI / 2) * 18.0
	return p.clamp(ARENA.position + Vector2(8, 8), ARENA.end - Vector2(8, 8))

func _begin_level() -> void:
	got = 0; lt = 0.0; near_cd.clear(); near_in.clear(); trail.clear()
	if role != "client": origin_pt = _pick_origin()
	for r in runs: r["off"] = Vector2.ZERO
	state = "ready"; state_t = 0.0; last_tick = 99
	for id in order: players[id]["seen"] = Time.get_ticks_msec()
	for id in order:
		var p: Dictionary = players[id]
		p["pos"] = spawn_pos(id); p["target"] = p["pos"]; p["vel"] = Vector2.ZERO; p["rec"] = PackedVector2Array(); p["got"] = 0
	if role != "client": _new_shard()
	if level >= 2 and not demo: sound.sfx("sfx_spawn", -4, 1.0, 0)

func _rand_point() -> Vector2:
	return Vector2(rng.randf_range(ARENA.position.x + 14, ARENA.end.x - 14), rng.randf_range(ARENA.position.y + 14, ARENA.end.y - 14))

## EXTREME puts most shards on a spot one of your echoes will pass through
func _path_point() -> Vector2:
	if mode != "extreme" or runs.is_empty() or rng.randf() > 0.8: return _rand_point()
	var r: PackedVector2Array = runs[rng.randi() % runs.size()]["pts"]
	if r.is_empty(): return _rand_point()
	if r.size() < 150: return _rand_point()
	# not the first two seconds of the path: that's where the echo is right behind you at the start
	var s: Vector2 = r[rng.randi_range(120, r.size() - 1)] + Vector2(rng.randf_range(-6, 6), rng.randf_range(-6, 6))
	return s.clamp(ARENA.position + Vector2(14, 14), ARENA.end - Vector2(14, 14))

func _new_shard() -> void:
	shard_t = 0.0
	if daily:
		# the same sequence for everyone: it depends only on the date, never on where anyone is
		for tries in 20:
			var s2 := Vector2(shard_rng.randf_range(ARENA.position.x + 14, ARENA.end.x - 14), shard_rng.randf_range(ARENA.position.y + 14, ARENA.end.y - 14))
			if s2.distance_to(shard) >= 60.0 or tries == 19:
				shard = s2; shard_goal = shard; return
	var best := Vector2.ZERO; var best_n := 999
	for tries in 40:
		var s := _path_point()
		var ok := s.distance_to(shard) >= 50.0
		for id in order:
			if players[id]["alive"] and s.distance_to(players[id]["pos"]) < 60.0: ok = false
		# how crowded the spot is with echoes now, and over the next second
		var crowd := 0
		for i in runs.size():
			for la in [0.0, 0.5, 1.0]:
				if s.distance_to(echo_at(i, lt + la)) < 26.0: crowd += 1
		if crowd > 0: ok = false
		if ok:
			shard = s; shard_goal = _path_point(); return
		if crowd < best_n: best_n = crowd; best = s
	shard = best; shard_goal = _path_point()

# ------------------------------------------------------------------ echoes
## echo i replays run i. Before its start, and in the second's rest between loops, it waits at its start, harmless.
func ghost_pos(i: int, t: float) -> Vector2:
	var r: PackedVector2Array = runs[i]["pts"]
	if r.size() < 2: return r[0] if r.size() == 1 else Vector2.ZERO
	var gt := t - g_delay()
	if gt < 0.0: return r[0]
	var n := r.size()
	var f := fmod(gt * 60.0 * g_speed(), float(n) + g_rest())
	if f >= n - 1: return r[0]
	var i0 := int(f); var k := f - i0
	return r[i0].lerp(r[mini(i0 + 1, n - 1)], k)

func ghost_live(i: int, t: float) -> bool:
	var r: PackedVector2Array = runs[i]["pts"]
	var gt := t - g_delay()
	if r.size() < 2 or gt < 0.0: return false
	return fmod(gt * 60.0 * g_speed(), float(r.size()) + g_rest()) < r.size() - 1

## seconds until echo i is dangerous again (0: it is moving now)
func ghost_wait(i: int, t: float) -> float:
	var r: PackedVector2Array = runs[i]["pts"]
	if r.size() < 2: return 0.0
	var gt := t - g_delay()
	if gt < 0.0: return -gt
	var n := r.size(); var sp := 60.0 * g_speed()
	var f := fmod(gt * sp, float(n) + g_rest())
	if f < n - 1: return 0.0
	return (float(n) + g_rest() - f) / sp

func echo_col(i: int) -> Color:
	if multi(): return players[runs[i]["owner"]]["col"] if players.has(runs[i]["owner"]) else HUES[i % HUES.size()]
	return hues[i % hues.size()]

# ------------------------------------------------------------------ the tick
func _physics_process(dt: float) -> void:
	beat += dt * bpm / 60.0
	if hit_stop > 0.0:
		hit_stop -= dt; queue_redraw(); return
	if hold_t > 0.0:
		hold_t -= dt; queue_redraw(); return
	state_t += dt
	shake = maxf(0.0, shake - dt * 10.0); flash = maxf(0.0, flash - dt * 3.0)
	_tick_fx(dt)
	if role == "client": _client_tick(dt); queue_redraw(); return
	match state:
		"ready":
			var c := 3 - int(state_t / 0.4)
			if c != last_tick and c > 0 and not demo: last_tick = c; sound.sfx("sfx_tick", -6, 1.0, 0)
			if state_t >= 1.2 or demo:
				state = "play"; state_t = 0.0
				if not demo: sound.sfx("sfx_go", -4, 1.0, 0)
		"play": _play(dt)
		"clear":
			if state_t > 1.1:
				level += 1
				_begin_level()
	queue_redraw()

func _move_local(dt: float) -> void:
	var p := me()
	if p.is_empty() or not (p["alive"] or p["zombie"]): return
	var mv := move_in.limit_length(1.0)
	if demo: mv = _demo_move()
	var spd := SPEED * (ZOMBIE_SPEED if p["zombie"] else 1.0)
	if p["zombie"]:
		# a zombie that gets close lunges, by itself: no extra button, and humans in the open can be caught
		lunge_cd = maxf(0.0, lunge_cd - dt)
		var tgt := _nearest_human(local_id)
		if lunge_t <= 0.0 and lunge_cd <= 0.0 and tgt >= 0 and float(p["grace"]) <= 0.0 and players[tgt]["pos"].distance_to(p["pos"]) < LUNGE_RANGE:
			lunge_t = LUNGE_T; lunge_cd = LUNGE_CD
			if not demo: sound.sfx("sfx_close", -4, 0.6, 0)
		if lunge_t > 0.0:
			lunge_t -= dt; spd = SPEED * LUNGE_SPEED
			if tgt >= 0 and mv.length() < 0.2: mv = (players[tgt]["pos"] - p["pos"]).normalized()
	p["vel"] = p["vel"].lerp(mv * spd, 1.0 - exp(-dt * 16.0))
	p["pos"] += p["vel"] * dt
	p["pos"] = p["pos"].clamp(ARENA.position + Vector2(P_R, P_R), ARENA.end - Vector2(P_R, P_R))
	if p["vel"].length() > 10.0:
		var tcol: Color = p["col"]
		match trail_style:
			"gold": tcol = GOLD
			"rainbow": tcol = Color.from_hsv(fmod(beat * 0.08, 1.0), 0.75, 1.0)
			"spark": tcol = Color(1, 1, 1)
		trail.append([p["pos"] + (Vector2(rng.randf_range(-3, 3), rng.randf_range(-3, 3)) if trail_style == "spark" else Vector2.ZERO), 0.35, tcol])

func _play(dt: float) -> void:
	lt += dt
	_move_local(dt)
	# remote players: move toward what they last reported
	for id in order:
		if id == local_id: continue
		var p: Dictionary = players[id]
		p["pos"] = p["pos"].lerp(p["target"], 1.0 - exp(-dt * 25.0))
	for id in order:
		var p: Dictionary = players[id]
		if p["alive"]: p["rec"].append(p["pos"])
		if p["zombie"]: p["grace"] = maxf(0.0, float(p["grace"]) - dt)
	# zombies: the host judges itself, and its own zombie's catches (clients report in, like with the echoes)
	if multi() and players.has(local_id) and players[local_id]["alive"]:
		var z := zombie_touching(local_id)
		if z >= 0: _caught(local_id, -1, z)
	if multi(): _zombie_claims()
	# a phone that has gone quiet (locked, in the background, out of range) can't hide from the game
	if role == "host":
		var now := Time.get_ticks_msec()
		for id in order:
			if id != local_id and players[id]["alive"] and now - int(players[id].get("seen", now)) > int(SILENT_OUT * 1000.0):
				_caught(id, -1, -1)
				if state != "play": return
	# the echoes
	_leash_tick(dt)
	for id in order:
		var p: Dictionary = players[id]
		if not p["alive"] or demo: continue
		for i in runs.size():
			if not ghost_live(i, lt): continue
			var d: float = echo_at(i).distance_to(p["pos"])
			# every player is judged on their own screen (the host for itself, clients report in),
			# so nobody is caught by network lag
			if d < P_R + g_r() - 0.5 and (role != "host" or id == local_id):
				_caught(id, i); break
			# a near miss is a pass: in close, then out again. Hovering behind an echo doesn't pay.
			var key := str(id) + ":" + str(i)
			if d < 13.0: near_in[key] = true
			elif d > 16.0 and near_in.get(key, false):
				near_in[key] = false
				if lt - float(near_cd.get(key, -99.0)) > 2.5:
					near_cd[key] = lt
					p["score"] += 25 * level
					if id == local_id: sc_close += 25 * level
					_emit("close", {"id": id, "pts": 25 * level, "echo": i})
	if state != "play": return
	# EXTREME: a shard left alone drifts away along the echoes' paths
	shard_t += dt
	if mode == "extreme" and shard_t > SHARD_STILL:
		shard = shard.move_toward(shard_goal, SHARD_DRIFT * dt)
		if shard.distance_to(shard_goal) < 1.0: shard_goal = _path_point()
	# the shard: whoever touches its glow first
	for id in order:
		var p: Dictionary = players[id]
		if not p["alive"]: continue
		if role == "host" and id != local_id: continue      # clients claim their own shards
		if p["pos"].distance_to(shard) < PICK_R:
			if _take(id): return
			break
	# time
	var left := lvl_time() - lt
	if left <= 3.0 and int(ceil(left)) != last_tick and not demo:
		last_tick = int(ceil(left)); sound.sfx("sfx_tick", -4, 1.4, 0)
	if left <= 0.0 and not demo:
		if multi():
			# hiding doesn't win: when time runs out, a human who took no shard this level turns
			for id in order.duplicate():
				if players[id]["alive"] and int(players[id]["got"]) == 0:
					_caught(id, -1, -1)
					if state != "play": return
			_clear(true)
		else: _caught(local_id, -1)

## a player takes the shard. true when that cleared the level.
func _take(id: int) -> bool:
	var p: Dictionary = players[id]
	got += 1; p["got"] += 1
	p["score"] += 100 * level
	if id == local_id: sc_shards += 100 * level
	_emit("shard", {"id": id, "n": got, "at": shard})
	if got >= SHARDS: _clear(); return true
	_new_shard()
	return false

func _nearest_human(id: int) -> int:
	var best := -1; var bd := 1e9
	for h in order:
		if h == id or not players[h]["alive"]: continue
		var d: float = players[h]["pos"].distance_to(players[id]["pos"])
		if d < bd: bd = d; best = h
	return best

## the local zombie claims a catch it sees on its own screen (the victim's screen may not have seen it yet)
func _zombie_claims() -> void:
	var p := me()
	if p.is_empty() or not p.get("zombie", false) or float(p["grace"]) > 0.0: return
	var now := Time.get_ticks_msec()
	for h in order:
		if h == local_id or not players[h]["alive"]: continue
		if players[h]["pos"].distance_to(p["pos"]) < P_R * 2.0 + 2.0 and now - int(zclaim_at.get(h, -9999)) > 400:
			zclaim_at[h] = now
			if role == "host": remote_zcatch(local_id, h)
			else: emit_signal("report", "zcatch", {"v": h})

## host: zombie z says it caught v. Checked against the host's own view, with some room for lag.
func remote_zcatch(z: int, v: int) -> void:
	if role != "host" or state != "play" or not players.has(z) or not players.has(v): return
	if not players[z]["zombie"] or float(players[z]["grace"]) > 0.0 or not players[v]["alive"]: return
	if players[z]["pos"].distance_to(players[v]["pos"]) < P_R * 2.0 + 16.0: _caught(v, -1, z)

## the zombie (if any) touching living player id right now
func zombie_touching(id: int) -> int:
	var me_p: Dictionary = players[id]
	for zid in order:
		if zid == id: continue
		var z: Dictionary = players[zid]
		if z["zombie"] and float(z["grace"]) <= 0.0 and z["pos"].distance_to(me_p["pos"]) < P_R * 2.0 + 1.0:
			return zid
	return -1

## host: a client says an echo (by) or a zombie (z) caught it, or that it took shard number n
func remote_caught(id: int, by: int, z := -1) -> void:
	if role != "host" or state != "play" or not players.has(id) or not players[id]["alive"]: return
	if z >= 0 and players.has(z) and players[z]["zombie"]: _caught(id, -1, z)
	elif by >= 0 and by < runs.size(): _caught(id, by)

func remote_take(id: int, n: int) -> void:
	# the shard number must match, and the player must be near it in the host's view too
	if role == "host" and state == "play" and players.has(id) and players[id]["alive"] and got == n \
			and players[id]["pos"].distance_to(shard) < PICK_R + 26.0:
		_take(id)

func _caught(id: int, by: int, z := -1) -> void:
	var p: Dictionary = players[id]
	p["alive"] = false
	if multi():
		# not out: a zombie now, still steered by them
		p["zombie"] = true; p["grace"] = ZOMBIE_GRACE
		if z >= 0 and players.has(z):
			players[z]["score"] += ZOMBIE_PTS * level
			print("ZOMBIE CATCH level %d: %s caught %s" % [level, players[z]["name"], p["name"]])
	_emit("caught", {"id": id, "by": by, "z": z, "by_owner": runs[by]["owner"] if by >= 0 else -1, "by_lv": runs[by]["lv"] if by >= 0 else -1, "at": p["pos"]})
	if not multi():
		state = "dead"; state_t = 0.0; killed_by = runs[by]["lv"] - 1 if by >= 0 else -1; killer = by
		return
	# keep what she did this level as an echo, even cut short, but only from the next level:
	# appearing halfway along its path right now could land it on someone
	if p["rec"].size() > 30: dead_runs.append([p["rec"], id])
	if alive_count() <= (1 if order.size() > 1 else 0):
		_over()

func _clear(timeout := false) -> void:
	state = "clear"; state_t = 0.0
	var bonus := 0 if timeout else int((lvl_time() - lt) * 20.0) * level
	for id in order:
		var p: Dictionary = players[id]
		if not p["alive"]: continue
		var b := bonus if p["got"] > 0 or not multi() else 0
		p["score"] += b
		if id == local_id: sc_bonus += b
		_add_run(p["rec"], id)
	for d in dead_runs: _add_run(d[0], d[1])
	dead_runs.clear()
	_emit("clear", {"level": level, "bonus": bonus, "timeout": timeout})

func _add_run(pts: PackedVector2Array, owner: int) -> void:
	if pts.size() < 2: return
	runs.append({"pts": pts, "owner": owner, "lv": level})
	while runs.size() > max_echoes(): runs.pop_front()
	runs_ver += 1

func _over() -> void:
	state = "over"; state_t = 0.0
	winner = -1
	for id in order:
		if players[id]["alive"]: winner = id
	if winner >= 0: players[winner]["score"] += 500 * level
	_emit("over", {"winner": winner})

## every event: effects and sound here, and (host) the same event sent on to the clients by main
func _emit(kind: String, d: Dictionary) -> void:
	on_event(kind, d)
	emit_signal("event", kind, d)

func on_event(kind: String, d: Dictionary) -> void:
	match kind:
		"shard":
			_burst(d["at"], GOLD, 18)
			rings.append([d["at"], 0.45, GOLD, 22.0])
			var mine: bool = d["id"] == local_id
			if not demo: sound.sfx("sfx_shard%d" % clampi(int(d["n"]), 1, 5), -3 if mine else -9, 1.0, 0)
			if mine:
				_buzz(25); hit_stop = maxf(hit_stop, 0.045)
				_burst(d["at"], Color(1, 1, 0.8), 10)
			elif players.has(d["id"]): popups.append({"p": d["at"] + Vector2(0, -10), "s": players[d["id"]]["name"], "life": 0.7, "col": players[d["id"]]["col"]})
		"close":
			if d["id"] == local_id and not demo:
				popups.append({"p": me()["pos"] + Vector2(0, -10), "s": "CLOSE! +%d" % int(d["pts"]), "life": 0.9, "col": Color(1, 1, 1)})
				var ei: int = int(d.get("echo", -1))
				if ei >= 0 and ei < runs.size(): rings.append([echo_at(ei), 0.4, echo_col(ei), 14.0])
				sound.sfx("sfx_close", -6, 1.0, 120)
		"caught":
			var col: Color = players[d["id"]]["col"] if players.has(d["id"]) else Color.WHITE
			_burst(d["at"], col, 40)
			if d["id"] == local_id:
				shake = 1.0; flash = 0.6; hit_stop = 0.12; _buzz(400)
				sound.sfx("sfx_death", 0, 1.0, 0)
			else:
				shake = 0.4; sound.sfx("sfx_death", -8, 1.2, 0)
				if players.has(d["id"]):
					var word := " ZOMBIFIED" if multi() else " OUT"
					popups.append({"p": d["at"] + Vector2(0, -12), "s": players[d["id"]]["name"] + word, "life": 1.2, "col": col})
			if int(d.get("z", -1)) >= 0 and players.has(int(d["z"])):
				rings.append([d["at"], 0.6, ZCOL, 26.0])
		"clear":
			flash = 0.25
			for i in runs.size(): rings.append([echo_at(i), 0.5, echo_col(i), 12.0])
			if not demo: sound.sfx("sfx_clear", -2, 1.0, 0)
			if int(d["bonus"]) > 0: popups.append({"p": Vector2(0, -30), "s": "TIME BONUS +%d" % int(d["bonus"]), "life": 1.2, "col": Color(0.6, 1.0, 0.8)})
			if d.get("timeout", false): popups.append({"p": Vector2(0, -30), "s": "TIME!", "life": 1.2, "col": Color(1, 0.5, 0.5)})
		"over":
			flash = 0.4

func _buzz(ms: int) -> void:
	if OS.has_feature("mobile") and not demo: Input.vibrate_handheld(ms, 0.6)

# ------------------------------------------------------------------ network: host side
func set_remote(id: int, pos: Vector2) -> void:
	if not players.has(id): return
	players[id]["seen"] = Time.get_ticks_msec()
	if players[id]["alive"] or players[id]["zombie"]: players[id]["target"] = pos

func remove_player(id: int) -> void:
	if not players.has(id): return
	players[id]["zombie"] = false              # gone: not even a zombie
	if players[id]["alive"] and state in ["play", "ready", "clear"]:
		players[id]["alive"] = false
		if alive_count() <= (1 if order.size() > 1 else 0) and role == "host": _over()

func snapshot() -> Array:
	var ps: Array = []
	for id in order:
		var p: Dictionary = players[id]
		ps.append([id, p["pos"], p["alive"], p["score"], p["got"], p["zombie"], p["grace"]])
	var offs: Array = []
	for i in runs.size():
		var off: Vector2 = runs[i].get("off", Vector2.ZERO)
		if off != Vector2.ZERO: offs.append([i, off])
	return [lt, state, state_t, level, shard, got, ps, runs.size(), winner, offs, shard_t, origin_pt]

# ------------------------------------------------------------------ network: client side
var snap_lt := 0.0
func apply_snapshot(s: Array) -> void:
	var was_level := level
	snap_lt = s[0]
	if absf(lt - snap_lt) > 0.15 or s[1] != state: lt = snap_lt
	if s[1] != state: state_t = s[2]
	state = s[1]; level = s[3]; shard = s[4]; got = s[5]; winner = s[8]
	for r in runs: r["off"] = Vector2.ZERO
	if s.size() > 11: origin_pt = s[11]
	if s.size() > 10:
		shard_t = s[10]
		for row in s[9]:
			if int(row[0]) < runs.size(): runs[int(row[0])]["off"] = row[1]
	for row in s[6]:
		var id: int = row[0]
		if not players.has(id): continue
		var p: Dictionary = players[id]
		if id != local_id: p["target"] = row[1]
		elif not row[2] and p["alive"]: pass
		p["alive"] = row[2]; p["score"] = row[3]; p["got"] = row[4]
		if row.size() > 6: p["zombie"] = row[5]; p["grace"] = row[6]
	if level != was_level or not players.get(local_id, {}).get("alive", true):
		self_out = false
	if level != was_level:
		trail.clear(); take_sent = -1
		for id in order:
			players[id]["pos"] = spawn_pos(id); players[id]["target"] = players[id]["pos"]; players[id]["vel"] = Vector2.ZERO
		if level >= 2: sound.sfx("sfx_spawn", -4, 1.0, 0)

func set_runs(arr: Array) -> void:
	runs = arr

func _client_tick(dt: float) -> void:
	if state == "play":
		lt += dt; shard_t += dt
		lt = lerpf(lt, snap_lt, 0.05)
		_move_local(dt)
		# judge myself, on my own screen, and tell the host
		var p := me()
		if not p.is_empty() and p["alive"] and not self_out:
			for i in runs.size():
				if ghost_live(i, lt) and echo_at(i).distance_to(p["pos"]) < P_R + g_r() - 0.5:
					self_out = true; emit_signal("report", "died", {"by": i, "z": -1}); break
			if not self_out:
				var zt := zombie_touching(local_id)
				if zt >= 0: self_out = true; emit_signal("report", "died", {"by": -1, "z": zt})
			if not self_out and p["pos"].distance_to(shard) < PICK_R and take_sent != got:
				take_sent = got; emit_signal("report", "take", {"n": got})
		_zombie_claims()
		var pz := me()
		if not pz.is_empty() and pz.get("zombie", false): pz["grace"] = maxf(0.0, float(pz["grace"]) - dt)
	if state == "ready":
		var c := 3 - int(state_t / 0.4)
		if c != last_tick and c > 0: last_tick = c; sound.sfx("sfx_tick", -6, 1.0, 0)
	for id in order:
		if id == local_id: continue
		var p: Dictionary = players[id]
		p["pos"] = p["pos"].lerp(p["target"], 1.0 - exp(-dt * 18.0))

# ------------------------------------------------------------------ the title screen: a self-playing demo
func _demo_move() -> Vector2:
	var p := me()
	if p.get("zombie", false):
		var best := Vector2.ZERO; var bd := 1e9
		for id in order:
			if id != local_id and players[id]["alive"]:
				var dd: float = players[id]["pos"].distance_to(p["pos"])
				if dd < bd: bd = dd; best = players[id]["pos"] - p["pos"]
		return best.normalized()
	var v: Vector2 = (shard - p["pos"]).normalized()
	for i in runs.size():
		# where the echo is now, and where it will be in a moment (a person sees it coming)
		for la in [0.0, 0.25]:
			if la > 0.0 and not ghost_live(i, lt + la): continue
			var d: Vector2 = p["pos"] - echo_at(i, lt + la)
			if d.length() < 28.0: v += d.normalized() * (28.0 - d.length()) / 9.0
	for id in order:
		if id != local_id and players[id].get("zombie", false):
			var dz: Vector2 = p["pos"] - players[id]["pos"]
			if dz.length() < 40.0: v += dz.normalized() * (40.0 - dz.length()) / 8.0
	return v.normalized()

func start_demo() -> void:
	demo = true
	for k in 4:
		var r := PackedVector2Array(); var p := Vector2.ZERO; var a := rng.randf() * TAU
		for i in 600:
			a += sin(i * 0.02 + k) * 0.05 + 0.01 * (k + 1)
			p += Vector2.from_angle(a) * 1.4
			if p.x < ARENA.position.x + 8 or p.x > ARENA.end.x - 8: a = PI - a
			if p.y < ARENA.position.y + 8 or p.y > ARENA.end.y - 8: a = -a
			p = p.clamp(ARENA.position + Vector2(6, 6), ARENA.end - Vector2(6, 6))
			r.append(p)
		runs.append({"pts": r, "owner": -1, "lv": k + 1})

# ------------------------------------------------------------------ effects
func _burst(at: Vector2, col: Color, n: int) -> void:
	for i in n:
		var a := rng.randf() * TAU; var s := rng.randf_range(40, 170)
		parts.append({"p": at, "v": Vector2.from_angle(a) * s, "life": rng.randf_range(0.35, 0.9), "col": col})

func _tick_fx(dt: float) -> void:
	for t in trail: t[1] -= dt
	trail = trail.filter(func(t): return t[1] > 0.0)
	for q in parts:
		q["p"] += q["v"] * dt; q["v"] *= 1.0 - dt * 3.0; q["life"] -= dt
	parts = parts.filter(func(q): return q["life"] > 0.0)
	for q in popups:
		q["p"].y -= dt * 18.0; q["life"] -= dt
	popups = popups.filter(func(q): return q["life"] > 0.0)
	for q in rings: q[1] -= dt
	rings = rings.filter(func(q): return q[1] > 0.0)

# ------------------------------------------------------------------ drawing
## LAN names: at the start of a level, and for players near you; not a cloud of labels all the time
func _show_label(id: int) -> bool:
	if state == "ready" or (state == "play" and state_t < 2.0): return true
	if id == local_id: return false
	var mp: Dictionary = me()
	return not mp.is_empty() and players[id]["pos"].distance_to(mp["pos"]) < 50.0

func origin() -> Vector2:
	var v := get_viewport_rect().size
	var o := v / 2.0 + Vector2(0, 8)
	if shake > 0.0: o += Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * shake * 4.0
	return o.round()

func _glow_circle(c: Vector2, r: float, col: Color, core := true) -> void:
	draw_circle(c, r * 2.6, Color(col, 0.08 * col.a))
	draw_circle(c, r * 1.7, Color(col, 0.18 * col.a))
	draw_circle(c, r, col)
	if core: draw_circle(c, r * 0.45, Color(1, 1, 1, 0.9 * col.a))

func _draw() -> void:
	var o := origin()
	var pulse := pow(1.0 - fmod(beat, 1.0), 3.0)
	# the arena: faint behind the menus, so text never fights the grid
	var fade := 0.35 if demo else 1.0
	var gc := Color(0.35, 0.15, 0.6, (0.16 + 0.07 * pulse) * fade)
	for x in range(int(ARENA.position.x), int(ARENA.end.x) + 1, 12):
		draw_line(o + Vector2(x, ARENA.position.y), o + Vector2(x, ARENA.end.y), gc, 1.0)
	for y in range(int(ARENA.position.y), int(ARENA.end.y) + 1, 12):
		draw_line(o + Vector2(ARENA.position.x, y), o + Vector2(ARENA.end.x, y), gc, 1.0)
	var wc := Color(1.0, 0.3, 0.85)
	var r := Rect2(ARENA.position + o, ARENA.size)
	draw_rect(r.grow(2), Color(wc, 0.12 * fade), false, 3.0)
	draw_rect(r, Color(wc, (0.9 + 0.1 * pulse) * fade), false, 1.0)
	var me_pos: Vector2 = me().get("pos", Vector2(9999, 9999))
	# echoes: hollow rings in their own colour, so they never read as you (solid white) or a shard (gold)
	for i in runs.size():
		var col := echo_col(i)
		var live := ghost_live(i, lt)
		var g := echo_at(i)
		var gr := g_r()
		var hunter := is_hunter(i)
		if live:
			for k in range(1, 4):
				draw_rect(Rect2((o + echo_at(i, maxf(lt - k * 0.07, 0.0))).round(), Vector2(1, 1)), Color(col, 0.6 - k * 0.15))
		if state == "ready" and not demo:
			# where each echo will go first, and the newest one's whole path
			var pts: PackedVector2Array = runs[i]["pts"]
			var newest: bool = int(runs[i]["lv"]) == level - 1
			var lim := pts.size() if newest else mini(pts.size(), 60)
			var stp := 5 if newest else 4
			for k in range(0, lim, stp):
				var f2 := 1.0 - float(k) / float(maxi(lim, 1))
				draw_rect(Rect2((o + pts[k]).round(), Vector2(1, 1)), Color(col, (0.6 if newest else 0.45) * (0.35 + 0.65 * f2)))
		var ca := 1.0 if live else 0.3
		if not live and not demo and state in ["ready", "play"]:
			# a ring that runs out: how long until this echo moves again
			var wt := ghost_wait(i, lt)
			var frac := clampf(wt / 1.0, 0.0, 1.0)
			var rc := Color(col, 0.85) if wt > 0.35 or int(beat * 4.0) % 2 == 0 else Color(1, 1, 1, 0.95)
			draw_arc(o + g, gr + 3.5, -PI / 2, -PI / 2 + TAU * frac, 18, rc, 1.0)
		draw_circle(o + g, gr * 2.4, Color(col, 0.07 * ca))
		draw_circle(o + g, gr * 1.5, Color(col, 0.16 * ca))
		draw_circle(o + g, gr, Color(col, ca))
		draw_circle(o + g, maxf(gr - 1.6, 0.8), Color(0.02, 0.0, 0.05, 0.92))
		if hunter:
			# the hunter: thick turning spikes, a triangle and a red pulse, so it reads by shape, not only colour
			var spin := beat * 0.8
			draw_circle(o + g, gr * 3.2, Color(1, 0.2, 0.25, (0.08 + 0.12 * pulse) * ca))
			for k in 6:
				var dv := Vector2.from_angle(spin + k * TAU / 6.0)
				draw_line(o + g + dv * (gr + 0.5), o + g + dv * (gr + 5.0 + pulse * 1.5), Color(1, 0.3, 0.3, ca), 2.0)
			var tri := PackedVector2Array()
			for k in 4: tri.append(o + g + Vector2.from_angle(-spin * 1.5 + k * TAU / 3.0) * (gr + 8.0))
			draw_polyline(tri, Color(1, 0.35, 0.35, 0.7 * ca), 1.0)
		# level numbers only where they matter: the hunter, the newest, and echoes near you
		var near: bool = g.distance_to(me_pos) < 40.0
		if live and state == "play" and not demo and (hunter or near or int(runs[i]["lv"]) == level - 1):
			Art.text(self, str(runs[i]["lv"]), o + g + Vector2(0, -12), Color(col, 0.75), false, 1, Color(0, 0, 0, 0))
		if state == "ready" and runs[i]["lv"] == level - 1 and not demo:
			Art.text(self, "HUNTER" if hunter else "NEW", o + g + Vector2(0, -14), Color(Color(1, 0.3, 0.35) if hunter else col, 0.6 + 0.4 * sin(state_t * 12.0)), false, 1)
	# level clear: every echo rewinds along its path, back to where it waits
	if state == "clear" and not demo:
		var f3 := clampf(1.0 - state_t / 0.9, 0.0, 1.0)
		for i in runs.size():
			var rp: PackedVector2Array = runs[i]["pts"]
			var upto := int(rp.size() * f3)
			if upto < 2: continue
			var col3 := echo_col(i)
			for k in range(0, upto - 3, 3):
				draw_line(o + rp[k], o + rp[k + 3], Color(col3, 0.35 * f3), 1.0)
			draw_arc(o + rp[upto - 1], g_r(), 0, TAU, 12, Color(col3, f3), 1.5)
	# death replay: the echo that got you, and the path it was following
	if state == "dead" and killer >= 0 and killer < runs.size():
		var kc := echo_col(killer)
		var kp: PackedVector2Array = runs[killer]["pts"]
		var a2 := 0.55 + 0.35 * sin(state_t * 8.0)
		for k in range(0, kp.size() - 3, 3):
			draw_line(o + kp[k], o + kp[k + 3], Color(kc, a2 * 0.8), 1.0)
		var kg := echo_at(killer)
		draw_arc(o + kg, g_r() + 6.0 + 2.0 * sin(state_t * 10.0), 0, TAU, 24, Color(1, 1, 1, 0.9), 1.0)
		Art.text(self, "YOUR LEVEL %d SELF" % int(runs[killer]["lv"]), o + kg + Vector2(0, -18), Color(kc, 1.0), false, 1)
	# the shard: gold, with the glow that counts as touching it
	if state == "play" or state == "ready":
		var a := beat * PI * 0.5
		var sp := o + shard
		draw_circle(sp, PICK_R - P_R, Color(GOLD, 0.1))
		if mode == "extreme" and state == "play" and shard_t > SHARD_STILL - 1.0 and shard_t < SHARD_STILL:
			# a red ring that runs out: the shard is about to move
			draw_arc(sp, PICK_R + 2.0, -PI / 2, -PI / 2 + TAU * (SHARD_STILL - shard_t), 20, Color(1, 0.3, 0.35, 0.8), 1.0)
		draw_arc(sp, PICK_R - P_R, 0, TAU, 28, Color(GOLD, 0.3 + 0.2 * pulse), 1.0)
		var pts := PackedVector2Array()
		for k in 4: pts.append(sp + Vector2.from_angle(a + k * PI / 2) * (5.0 + pulse * 1.5))
		draw_colored_polygon(pts, Color(GOLD, 0.95))
		draw_polyline(pts + PackedVector2Array([pts[0]]), Color(1, 1, 0.85), 1.0)
	# trails and players: a white-hot core in a coloured ring, with a tick for where you're heading
	for t in trail:
		if trail_style == "spark" and not multi(): draw_rect(Rect2((o + t[0]).round(), Vector2(1, 1)), Color(t[2], t[1] / 0.35))
		else: draw_circle(o + t[0], (P_R + 0.8) * t[1] / 0.35, Color(t[2], 0.26 * t[1] / 0.35))
	for id in order:
		var p: Dictionary = players[id]
		if p.get("zombie", false):
			var zp: Vector2 = o + p["pos"]
			var zc: Color = Color(p["col"]).lerp(ZCOL, 0.5)
			var ready_z: bool = float(p["grace"]) <= 0.0
			var za := 1.0 if ready_z or int(beat * 8.0) % 2 == 0 else 0.35
			# a zombie is square: no other thing in the game is
			draw_circle(zp, P_R * 2.8, Color(ZCOL, 0.1 * za))
			var sq := Rect2(zp - Vector2(5, 5), Vector2(10, 10))
			draw_rect(sq, Color(zc, za))
			draw_rect(sq.grow(-1.5), Color(0.02, 0.0, 0.05, 0.95))
			for k in 3: draw_rect(Rect2(zp + Vector2(-3 + k * 2.5, -0.5), Vector2(1, 2)), Color(ZCOL, za))   # teeth
			if lunge_t > 0.0 and id == local_id: draw_rect(sq.grow(2), Color(ZCOL, 0.8), false, 1.0)
			if _show_label(id):
				var zl: String = ("YOU" if id == local_id else String(p["name"])) + " (ZOMBIE)"
				Art.text(self, zl, zp + Vector2(0, -15), Color(ZCOL, 0.9), false, 1)
			continue
		if not p["alive"]: continue
		var pc: Color = p["col"]
		var pp: Vector2 = o + p["pos"]
		draw_circle(pp, P_R * 2.8, Color(pc, 0.1))
		draw_circle(pp, P_R * 1.8, Color(pc, 0.24))
		draw_circle(pp, P_R + 1.6, Color(1, 1, 1))
		draw_circle(pp, P_R + 0.6, pc)
		draw_circle(pp, P_R - 1.2, Color(1, 1, 1))
		var v: Vector2 = p["vel"]
		if v.length() > 15.0:
			var dv := v.normalized()
			draw_line(pp + dv * (P_R + 1.5), pp + dv * (P_R + 4.5), Color(1, 1, 1, 0.9), 1.0)
		if multi() and _show_label(id):
			var label: String = "YOU" if id == local_id else p["name"]
			Art.text(self, label, o + p["pos"] + Vector2(0, -14), Color(pc, 0.85), false, 1)
	var fx := 0.35 if demo else 1.0          # behind the menus, effects stay faint
	for q in rings:
		var k: float = 1.0 - q[1] / 0.5
		draw_arc(o + q[0], 4.0 + q[3] * k, 0, TAU, 24, Color(q[2], clampf(q[1] * 2.2, 0.0, 1.0) * fx), 1.0)
	for q in parts:
		var pa := clampf(q["life"] * 2.0, 0.0, 1.0) * fx
		draw_rect(Rect2((o + q["p"]).round() - Vector2(1, 1), Vector2(2, 2)), Color(q["col"], pa))
		draw_rect(Rect2((o + q["p"]).round() - Vector2(2, 2), Vector2(4, 4)), Color(q["col"], pa * 0.25))
	if not demo:                             # no "TIME BONUS" text under the title-screen buttons
		for q in popups:
			Art.text(self, q["s"], o + q["p"], Color(q["col"], clampf(q["life"] * 2.0, 0.0, 1.0)), false, 1)
