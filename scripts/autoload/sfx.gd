extends Node
## Autoload « Sfx » : sons de bruitage.
## - Enregistrements CC0 (Kenney « Impact Sounds », assets/sounds/) : pas, impacts, blessures,
##   cliquetis métalliques ; chaque nom regroupe plusieurs variantes tirées au hasard.
## - Synthèse au démarrage pour le reste (détonations, explosions, signaux d'interface) :
##   aucun pack CC0 de détonations n'était accessible ; remplaçable via _streams.

const RATE := 22050
const SOUND_DIR := "res://assets/sounds/"
## nom du son -> préfixe des fichiers Kenney (suffixes _000 à _004)
const RECORDED := {
	"step_grass": "footstep_grass", "step_stone": "footstep_concrete",
	"impact": "impact_generic_light", "impact_wood": "impact_wood_medium",
	"body_hit": "impact_soft_medium", "hurt": "impact_punch_heavy",
	"click": "impact_metal_light", "reload": "impact_plate_light", "bounce": "impact_metal_heavy",
}

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 16:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_streams["rifle"] = _shot(0.6, 8.0, 2400.0, 65.0, 0.9)
	_streams["smg"] = _shot(0.25, 16.0, 3000.0, 85.0, 0.6)
	_streams["pistol"] = _shot(0.3, 13.0, 3600.0, 110.0, 0.5)
	_streams["enemy_rifle"] = _shot(0.55, 7.0, 1300.0, 60.0, 0.6)
	_streams["enemy_smg"] = _shot(0.22, 15.0, 1600.0, 80.0, 0.5)
	_streams["enemy_mg"] = _shot(0.2, 17.0, 1500.0, 75.0, 0.6)
	_streams["explosion"] = _explosion()
	_streams["hitmarker"] = _tone(0.05, 1800.0, 70.0, 0.0)
	_streams["kill"] = _tone(0.12, 1200.0, 25.0, -400.0)
	_streams["ping"] = _tone(0.35, 2600.0, 9.0, 0.0)
	_streams["click"] = _click(0.035, 4000.0)
	_streams["reload"] = _reload()
	_streams["step"] = _noise(0.08, 500.0, 40.0)
	_streams["hurt"] = _shot(0.25, 14.0, 250.0, 55.0, 1.0)
	_streams["ui"] = _tone(0.08, 880.0, 30.0, 220.0)
	_streams["bounce"] = _click(0.05, 1500.0)
	_streams["whiz"] = _whiz()
	_streams["pickup"] = _tone(0.12, 660.0, 20.0, 660.0)
	_load_recorded()


## Charge les variantes enregistrées ; garde la version synthétique si un fichier manque.
func _load_recorded() -> void:
	for sound: String in RECORDED:
		var variants: Array[AudioStream] = []
		for i in 5:
			var path := "%s%s_%03d.ogg" % [SOUND_DIR, RECORDED[sound], i]
			if ResourceLoader.exists(path):
				variants.append(load(path) as AudioStream)
		if not variants.is_empty():
			_streams[sound] = variants


## Un nom peut désigner un son unique ou une liste de variantes.
func _pick(sound: String) -> AudioStream:
	var v: Variant = _streams[sound]
	if v is Array:
		var arr := v as Array
		return arr[randi() % arr.size()]
	return v as AudioStream


func has_sound(sound: String) -> bool:
	return _streams.has(sound)


## Son non spatialisé (armes du joueur, interface).
func play(sound: String, volume_db := 0.0, pitch_var := 0.06) -> void:
	if not _streams.has(sound):
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _pick(sound)
	p.volume_db = volume_db
	p.pitch_scale = randf_range(1.0 - pitch_var, 1.0 + pitch_var)
	p.play()


## Son 3D positionné dans le monde (tirs ennemis, explosions).
func play_at(sound: String, pos: Vector3, volume_db := 0.0, max_dist := 150.0) -> void:
	var scene := get_tree().current_scene
	if scene == null or not _streams.has(sound) or not scene is Node3D:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = _pick(sound)
	p.volume_db = volume_db
	p.max_distance = max_dist
	p.unit_size = 10.0
	p.pitch_scale = randf_range(0.94, 1.06)
	scene.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()


# --- Synthèse ------------------------------------------------------------------

func _to_wav(buf: PackedFloat32Array) -> AudioStreamWAV:
	var peak := 0.0001
	for v in buf:
		peak = maxf(peak, absf(v))
	var gain := 0.9 / peak
	var data := PackedByteArray()
	data.resize(buf.size() * 2)
	for i in buf.size():
		data.encode_s16(i * 2, int(clampf(buf[i] * gain, -1.0, 1.0) * 32767.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	return s


## Détonation : bruit filtré + claquement initial + « thump » grave.
func _shot(dur: float, decay: float, cutoff: float, thump_hz: float, thump_amp: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var a := 1.0 - exp(-TAU * cutoff / RATE)
	var lp := 0.0
	var lp2 := 0.0
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var nz := randf_range(-1.0, 1.0)
		lp += a * (nz - lp)
		lp2 += a * (lp - lp2)
		phase += TAU * thump_hz * (1.0 - t * 0.6) / RATE
		var crack := nz * exp(-t * 400.0) * 0.8
		var thump := sin(phase) * exp(-t * decay * 0.7) * thump_amp
		buf[i] = lp2 * exp(-t * decay) * 2.5 + crack + thump
	return _to_wav(buf)


func _explosion() -> AudioStreamWAV:
	var n := int(2.2 * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var cutoff := 900.0 * exp(-t * 1.2) + 120.0
		var a := 1.0 - exp(-TAU * cutoff / RATE)
		var nz := randf_range(-1.0, 1.0)
		lp += a * (nz - lp)
		lp2 += a * (lp - lp2)
		phase += TAU * (48.0 - t * 10.0) / RATE
		var env := minf(t / 0.004, 1.0) * exp(-t * 2.0)
		buf[i] = (lp2 * 3.0 + sin(phase) * 0.8) * env + nz * exp(-t * 60.0) * 0.6
	return _to_wav(buf)


func _tone(dur: float, freq: float, decay: float, sweep: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		phase += TAU * (freq + sweep * t) / RATE
		buf[i] = sin(phase) * exp(-t * decay) * minf(t / 0.003, 1.0)
	return _to_wav(buf)


func _click(dur: float, cutoff: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var a := 1.0 - exp(-TAU * cutoff / RATE)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += a * (randf_range(-1.0, 1.0) - lp)
		buf[i] = lp * exp(-t * 140.0) + sin(TAU * 3100.0 * t) * exp(-t * 200.0) * 0.4
	return _to_wav(buf)


func _noise(dur: float, cutoff: float, decay: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var a := 1.0 - exp(-TAU * cutoff / RATE)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += a * (randf_range(-1.0, 1.0) - lp)
		buf[i] = lp * minf(t / 0.01, 1.0) * exp(-t * decay)
	return _to_wav(buf)


## Rechargement : trois cliquetis métalliques.
func _reload() -> AudioStreamWAV:
	var n := int(0.55 * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for start: float in [0.0, 0.22, 0.4]:
		var s := int(start * RATE)
		for i in range(s, mini(n, s + int(0.06 * RATE))):
			var t := float(i - s) / RATE
			buf[i] += (randf_range(-1.0, 1.0) * 0.5 + sin(TAU * 2900.0 * t) * 0.6) * exp(-t * 90.0)
	return _to_wav(buf)


## Sifflement de balle qui passe près.
func _whiz() -> AudioStreamWAV:
	var dur := 0.22
	var n := int(dur * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		phase += TAU * lerpf(3200.0, 1200.0, t / dur) / RATE
		buf[i] = (sin(phase) * 0.6 + randf_range(-1.0, 1.0) * 0.3) * sin(PI * t / dur)
	return _to_wav(buf)
