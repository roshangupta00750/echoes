class_name Sound extends Node
## Chiptune music (looped) and a pool of short sound effects.

var music: AudioStreamPlayer
var pool: Array = []
var cache := {}
var music_name := ""
var on := true
var last_at := {}          # name -> ms, so a sound played 40 times a second is played a few times

func _ready() -> void:
	music = AudioStreamPlayer.new(); music.volume_db = -6.0; add_child(music)
	for i in 12:
		var a := AudioStreamPlayer.new(); add_child(a); pool.append(a)

func _stream(n: String) -> AudioStreamWAV:
	if cache.has(n): return cache[n]
	var path := "res://assets/audio/%s.wav" % n
	var s: AudioStreamWAV = load(path) if ResourceLoader.exists(path) else null
	cache[n] = s
	return s

func play_music(n: String, vol := -6.0) -> void:
	if n == music_name and music.playing: return
	music_name = n
	var s := _stream(n)
	if s == null: music.stop(); return
	if n.begins_with("music"):
		var frames := int(floor(s.get_length() * float(s.mix_rate)))
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD; s.loop_begin = 0; s.loop_end = maxi(frames - 4, 1)
	music.stream = s; music.volume_db = vol if on else -80.0; music.play()

func stop_music() -> void:
	music.stop(); music_name = ""

func sfx(n: String, vol := 0.0, pitch := 1.0, min_gap_ms := 30) -> void:
	if not on: return
	var now := Time.get_ticks_msec()
	if now - int(last_at.get(n, -9999)) < min_gap_ms: return
	last_at[n] = now
	var s := _stream(n)
	if s == null: return
	for a in pool:
		if not a.playing:
			a.stream = s; a.volume_db = vol; a.pitch_scale = pitch * randf_range(0.97, 1.03); a.play(); return

func set_on(v: bool) -> void:
	on = v
	music.volume_db = -6.0 if on else -80.0
