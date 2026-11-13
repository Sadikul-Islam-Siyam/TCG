extends Node
## Phase 13 (T13.1 - T13.4): Procedural AudioManager autoload.
## Synthesizes crisp AudioStreamWAV SFX, element hits, reaction stingers, and
## crossfading ambient music loops routed cleanly to Music / SFX / UI buses.

const SAMPLE_RATE: int = 22050
const SFX_POOL_SIZE: int = 10
const UI_POOL_SIZE: int = 4

var _streams: Dictionary = {}
var _sfx_pool: Array[AudioStreamPlayer] = []
var _ui_pool: Array[AudioStreamPlayer] = []
var _sfx_idx: int = 0
var _ui_idx: int = 0

var _music_calm: AudioStreamPlayer = null
var _music_tense: AudioStreamPlayer = null
var _music_started: bool = false
var _is_tense: bool = false
var _music_tween: Tween = null

var master_volume: float = 1.0
var music_volume: float = 0.72
var sfx_volume: float = 0.85
var ui_volume: float = 0.82
var muted: bool = false


func _ready() -> void:
	_build_pools()
	_prebuild_bank()
	apply_volumes()


func _exit_tree() -> void:
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	_streams.clear()


func _is_headless() -> bool:
	return DisplayServer.get_name() == "headless" or OS.has_feature("headless")


func _bus_name_or_master(preferred: StringName) -> StringName:
	if AudioServer.get_bus_index(preferred) >= 0:
		return preferred
	return &"Master"


func _build_pools() -> void:
	var sfx_bus := _bus_name_or_master(&"SFX")
	var ui_bus := _bus_name_or_master(&"UI")
	var mus_bus := _bus_name_or_master(&"Music")

	for _i in range(SFX_POOL_SIZE):
		var p := AudioStreamPlayer.new()
		p.bus = sfx_bus
		p.max_polyphony = 1
		add_child(p)
		_sfx_pool.append(p)

	for _j in range(UI_POOL_SIZE):
		var u := AudioStreamPlayer.new()
		u.bus = ui_bus
		u.max_polyphony = 1
		add_child(u)
		_ui_pool.append(u)

	_music_calm = AudioStreamPlayer.new()
	_music_calm.bus = mus_bus
	_music_calm.volume_db = -6.0
	add_child(_music_calm)

	_music_tense = AudioStreamPlayer.new()
	_music_tense.bus = mus_bus
	_music_tense.volume_db = -60.0
	add_child(_music_tense)


func _prebuild_bank() -> void:
	# Card & UI SFX
	_streams["card_hover"] = _synth_tone(0.045, 760.0, 920.0, 0.14, "sine", 0.15)
	_streams["card_select"] = _synth_tone(0.065, 520.0, 740.0, 0.24, "triangle", 0.20)
	_streams["card_draw"] = _synth_noise_sweep(0.11, 1400.0, 600.0, 0.22)
	_streams["card_play"] = _synth_chord(0.14, [440.0, 659.25], 0.28, "triangle")
	_streams["card_invalid"] = _synth_chord(0.16, [185.0, 174.6], 0.30, "saw")
	_streams["ui_click"] = _synth_tone(0.055, 620.0, 820.0, 0.20, "sine", 0.08)
	_streams["ui_confirm"] = _synth_chord(0.16, [523.25, 659.25, 783.99], 0.26, "sine")
	_streams["ui_cancel"] = _synth_tone(0.10, 420.0, 260.0, 0.22, "triangle", 0.05)
	_streams["panel_open"] = _synth_tone(0.14, 340.0, 620.0, 0.18, "sine", 0.12)
	_streams["panel_close"] = _synth_tone(0.12, 540.0, 310.0, 0.16, "sine", 0.10)
	_streams["end_round"] = _synth_chord(0.28, [392.0, 587.33, 783.99], 0.32, "sine")
	_streams["turn_chime"] = _synth_chord(0.22, [587.33, 880.0], 0.24, "sine")

	# Dice SFX
	_streams["dice_roll"] = _synth_noise_sweep(0.22, 900.0, 2200.0, 0.30)
	_streams["dice_land"] = _synth_tone(0.075, 320.0, 140.0, 0.30, "triangle", 0.25)
	_streams["dice_select"] = _synth_tone(0.08, 880.0, 1174.6, 0.22, "sine", 0.05)
	_streams["dice_spend"] = _synth_chord(0.18, [659.25, 987.77, 1318.5], 0.24, "sine")
	_streams["dice_tune"] = _synth_tone(0.20, 440.0, 880.0, 0.26, "sine", 0.06)

	# Element & Damage SFX (also wire onto ElementDB resources)
	_streams["hit_cryo"] = _synth_chord(0.20, [1318.5, 1760.0, 2093.0], 0.28, "triangle")
	_streams["hit_hydro"] = _synth_tone(0.22, 620.0, 240.0, 0.30, "sine", 0.35)
	_streams["hit_pyro"] = _synth_tone(0.24, 210.0, 72.0, 0.36, "saw", 0.55)
	_streams["hit_electro"] = _synth_tone(0.18, 1280.0, 460.0, 0.28, "square", 0.30)
	_streams["hit_anemo"] = _synth_noise_sweep(0.22, 500.0, 1650.0, 0.26)
	_streams["hit_geo"] = _synth_tone(0.24, 150.0, 62.0, 0.40, "triangle", 0.32)
	_streams["hit_physical"] = _synth_tone(0.12, 340.0, 110.0, 0.34, "saw", 0.45)
	_streams["hit_piercing"] = _synth_tone(0.14, 1480.0, 920.0, 0.26, "sine", 0.20)
	_streams["heal"] = _synth_chord(0.28, [523.25, 659.25, 783.99, 1046.5], 0.24, "sine")
	_streams["shield_gain"] = _synth_chord(0.20, [330.0, 493.88, 659.25], 0.26, "triangle")
	_streams["shield_absorb"] = _synth_tone(0.11, 280.0, 160.0, 0.30, "triangle", 0.25)
	_streams["shield_break"] = _synth_tone(0.20, 740.0, 190.0, 0.34, "saw", 0.65)
	_streams["energy_gain"] = _synth_tone(0.16, 740.0, 1480.0, 0.24, "sine", 0.04)
	_streams["burst_ready"] = _synth_chord(0.32, [440.0, 554.37, 659.25, 880.0], 0.28, "sine")
	_streams["burst_cast"] = _synth_chord(0.38, [146.83, 293.66, 440.0, 880.0], 0.36, "triangle")
	_streams["freeze_apply"] = _synth_chord(0.24, [1567.98, 2093.0], 0.24, "sine")
	_streams["freeze_break"] = _synth_noise_sweep(0.18, 2200.0, 700.0, 0.32)
	_streams["defeat"] = _synth_chord(0.35, [196.0, 146.83, 98.0], 0.36, "triangle")
	_streams["victory"] = _synth_chord(0.45, [523.25, 659.25, 783.99, 1046.5], 0.32, "sine")
	_streams["defeat_match"] = _synth_chord(0.45, [293.66, 349.23, 440.0], 0.28, "triangle")
	_streams["ui_error"] = _streams["card_invalid"]
	_streams["burst"] = _streams["burst_cast"]

	# 8 Canonical Reactions
	_streams["react_vaporize"] = _synth_noise_sweep(0.26, 700.0, 2400.0, 0.30)
	_streams["react_melt"] = _synth_chord(0.28, [392.0, 587.33, 987.77], 0.30, "triangle")
	_streams["react_overloaded"] = _synth_tone(0.30, 165.0, 48.0, 0.42, "saw", 0.70)
	_streams["react_superconduct"] = _synth_chord(0.24, [1174.6, 1480.0, 1760.0], 0.28, "square")
	_streams["react_electro_charged"] = _synth_chord(0.26, [880.0, 1046.5, 1318.5], 0.26, "square")
	_streams["react_frozen"] = _synth_chord(0.30, [1318.5, 1975.5, 2637.0], 0.26, "sine")
	_streams["react_swirl"] = _synth_noise_sweep(0.28, 420.0, 1900.0, 0.32)
	_streams["react_crystallize"] = _synth_chord(0.26, [440.0, 659.25, 1174.6], 0.28, "triangle")

	# Bind hit sounds to ElementDB resources (T0.2 integration)
	for el_id in ElementDB.all_ids():
		var ed := ElementDB.get_element(el_id)
		var key := "hit_%s" % String(el_id).to_lower()
		if ed != null and _streams.has(key):
			ed.hit_sound = _streams[key]

	# Music stems (seamless 8s pentatonic loops)
	_music_calm.stream = _synth_music_loop(false)
	_music_tense.stream = _synth_music_loop(true)


func apply_volumes() -> void:
	_set_bus_linear(&"Master", 0.0 if muted else master_volume)
	_set_bus_linear(&"Music", 0.0 if muted else music_volume)
	_set_bus_linear(&"SFX", 0.0 if muted else sfx_volume)
	_set_bus_linear(&"UI", 0.0 if muted else ui_volume)


func get_bus_volume_linear(bus_name: String) -> float:
	match bus_name.to_lower():
		"master":
			return master_volume
		"music":
			return music_volume
		"sfx":
			return sfx_volume
		"ui":
			return ui_volume
		_:
			return 0.85


func set_bus_volume_linear(bus_name: String, v: float) -> void:
	var clamped: float = clampf(v, 0.0, 1.0)
	match bus_name.to_lower():
		"master":
			master_volume = clamped
			apply_volumes()
		"music":
			set_music_linear(clamped)
		"sfx":
			set_sfx_linear(clamped)
		"ui":
			set_ui_linear(clamped)
		_:
			apply_volumes()


func set_music_linear(v: float) -> void:
	music_volume = clampf(v, 0.0, 1.0)
	apply_volumes()


func set_sfx_linear(v: float) -> void:
	sfx_volume = clampf(v, 0.0, 1.0)
	apply_volumes()


func set_ui_linear(v: float) -> void:
	ui_volume = clampf(v, 0.0, 1.0)
	apply_volumes()


func _set_bus_linear(bus_name: StringName, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	AudioServer.set_bus_mute(idx, linear <= 0.005)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(0.001, linear)))


func start_ambient_music() -> void:
	if _is_headless() or _music_started:
		return
	_music_started = true
	if _music_calm != null and _music_calm.stream != null:
		_music_calm.play()
	if _music_tense != null and _music_tense.stream != null:
		_music_tense.play()
	set_music_tense(_is_tense, true)


func stop_ambient_music() -> void:
	_music_started = false
	if _music_calm != null:
		_music_calm.stop()
	if _music_tense != null:
		_music_tense.stop()


func play_music(tense: bool = false) -> void:
	start_ambient_music()
	set_music_tense(tense)


func set_music_tense(tense: bool, immediate: bool = false) -> void:
	if _is_tense == tense and not immediate:
		return
	_is_tense = tense
	if _is_headless() or _music_calm == null or _music_tense == null:
		return
	var target_calm := -26.0 if tense else -6.0
	var target_tense := -6.0 if tense else -50.0
	if immediate:
		_music_calm.volume_db = target_calm
		_music_tense.volume_db = target_tense
		return
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = create_tween()
	_music_tween.set_parallel(true)
	_music_tween.tween_property(_music_calm, "volume_db", target_calm, 1.5)
	_music_tween.tween_property(_music_tense, "volume_db", target_tense, 1.5)


func play_ui(sfx_name: String, pitch_jitter: bool = true) -> void:
	if _is_headless() or not _streams.has(sfx_name) or _ui_pool.is_empty():
		return
	var p: AudioStreamPlayer = _ui_pool[_ui_idx % _ui_pool.size()]
	_ui_idx += 1
	p.stream = _streams[sfx_name]
	p.pitch_scale = randf_range(0.96, 1.04) if pitch_jitter else 1.0
	p.play()


func play_sfx(sfx_name: String, pitch_jitter: bool = true) -> void:
	if _is_headless() or not _streams.has(sfx_name) or _sfx_pool.is_empty():
		return
	var p: AudioStreamPlayer = _sfx_pool[_sfx_idx % _sfx_pool.size()]
	_sfx_idx += 1
	p.stream = _streams[sfx_name]
	p.pitch_scale = randf_range(0.95, 1.05) if pitch_jitter else 1.0
	p.play()


func play_element_hit(elem: String) -> void:
	var ed := ElementDB.get_element(elem)
	if ed != null and ed.hit_sound != null and not _is_headless() and not _sfx_pool.is_empty():
		var p: AudioStreamPlayer = _sfx_pool[_sfx_idx % _sfx_pool.size()]
		_sfx_idx += 1
		p.stream = ed.hit_sound
		p.pitch_scale = randf_range(0.95, 1.05)
		p.play()
		return
	var key := "hit_%s" % elem.to_lower()
	play_sfx(key if _streams.has(key) else "hit_physical", true)


func play_reaction(reaction_name: String) -> void:
	var key := "react_%s" % reaction_name.to_lower().replace("-", "_")
	play_sfx(key if _streams.has(key) else "hit_pyro", true)


func has_sound(sfx_name: String) -> bool:
	return _streams.has(sfx_name)


func _pack_pcm16(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in range(samples.size()):
		var clamped := clampf(samples[i], -1.0, 1.0)
		var v := int(roundf(clamped * 32767.0))
		data.encode_s16(i * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD if loop else AudioStreamWAV.LOOP_DISABLED
	if loop:
		wav.loop_end = samples.size()
	wav.data = data
	return wav


func _wave_sample(phase: float, kind: String) -> float:
	match kind:
		"triangle":
			return 2.0 * absf(2.0 * (phase - floorf(phase + 0.5))) - 1.0
		"square":
			return 0.65 if fmod(phase, 1.0) < 0.5 else -0.65
		"saw":
			return 1.8 * (phase - floorf(phase + 0.5))
		_:
			return sin(phase * TAU)


func _synth_tone(dur: float, f0: float, f1: float, amp: float, wave: String, noise_mix: float) -> AudioStreamWAV:
	var n := maxi(64, int(roundf(dur * float(SAMPLE_RATE))))
	var out := PackedFloat32Array()
	out.resize(n)
	var phase: float = 0.0
	var seed_val: int = 1337
	for i in range(n):
		var t: float = float(i) / float(n)
		var freq: float = lerpf(f0, f1, t)
		phase += freq / float(SAMPLE_RATE)
		var env: float = minf(1.0, t * 24.0) * pow(maxf(0.0, 1.0 - t), 1.65)
		seed_val = (seed_val * 1103515245 + 12345) & 0x7fffffff
		var nz := (float(seed_val % 2000) / 1000.0 - 1.0) * noise_mix
		out[i] = (_wave_sample(phase, wave) * (1.0 - noise_mix * 0.5) + nz) * amp * env
	return _pack_pcm16(out)


func _synth_chord(dur: float, freqs: Array, amp: float, wave: String) -> AudioStreamWAV:
	var n := maxi(64, int(roundf(dur * float(SAMPLE_RATE))))
	var out := PackedFloat32Array()
	out.resize(n)
	var phases := PackedFloat32Array()
	phases.resize(freqs.size())
	var inv_cnt: float = 1.0 / maxf(1.0, float(freqs.size()))
	for i in range(n):
		var t: float = float(i) / float(n)
		var env: float = minf(1.0, t * 22.0) * pow(maxf(0.0, 1.0 - t), 1.5)
		var sum: float = 0.0
		for k in range(freqs.size()):
			phases[k] += float(freqs[k]) / float(SAMPLE_RATE)
			sum += _wave_sample(phases[k], wave)
		out[i] = sum * inv_cnt * amp * env
	return _pack_pcm16(out)


func _synth_noise_sweep(dur: float, _f0: float, _f1: float, amp: float) -> AudioStreamWAV:
	var n := maxi(64, int(roundf(dur * float(SAMPLE_RATE))))
	var out := PackedFloat32Array()
	out.resize(n)
	var seed_val: int = 7919
	var prev: float = 0.0
	for i in range(n):
		var t: float = float(i) / float(n)
		var env: float = sin(t * PI)
		seed_val = (seed_val * 1103515245 + 12345) & 0x7fffffff
		var raw: float = float(seed_val % 2000) / 1000.0 - 1.0
		var alpha: float = lerpf(0.18, 0.72, t)
		prev = lerpf(prev, raw, alpha)
		out[i] = prev * amp * env
	return _pack_pcm16(out)


func _synth_music_loop(tense: bool) -> AudioStreamWAV:
	# 4.0 second seamless pentatonic loop at gentle volume
	var dur: float = 4.0
	var n := int(roundf(dur * float(SAMPLE_RATE)))
	var out := PackedFloat32Array()
	out.resize(n)
	var notes: Array = (
		[220.0, 261.63, 329.63, 392.0, 440.0, 392.0, 329.63, 293.66]
		if tense else
		[261.63, 329.63, 392.0, 523.25, 440.0, 392.0, 329.63, 293.66]
	)
	var steps: int = notes.size() * (2 if tense else 1)
	var step_len: float = dur / float(steps)
	for i in range(n):
		var sec: float = float(i) / float(SAMPLE_RATE)
		var step_i: int = int(floorf(sec / step_len)) % steps
		var local_t: float = fmod(sec, step_len) / step_len
		var f: float = notes[step_i % notes.size()]
		var env: float = sin(local_t * PI)
		var pad: float = sin(sec * (130.81 if not tense else 110.0) * TAU) * 0.06
		var harp: float = sin(sec * f * TAU) * 0.09 * env
		var pulse: float = (sin(sec * 220.0 * TAU) * 0.04 * (1.0 - local_t)) if tense else 0.0
		out[i] = clampf(pad + harp + pulse, -0.5, 0.5)
	return _pack_pcm16(out, true)
