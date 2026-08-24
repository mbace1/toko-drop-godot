## audio_kit.gd — the game's whole sound, synthesised at load.
##
## The browser's js/audio.js is an all-synth WebAudio kit with no sample files,
## and the house rule across this codebase is that sound is generated, never
## sampled (Suds-Jack's eeri gate fails outright on a binary under
## assets/audio/). So every voice here is built into an AudioStreamWAV at
## startup from an oscillator plus an envelope: nothing to license, nothing to
## vendor, and the repo stays free of binary blobs that do not diff.
##
## Voices are deliberately short and quiet. A twin-stick game fires ~11 shots a
## second, so the gun has to sit under everything else or it becomes the mix.
class_name AudioKit
extends Node

const RATE := 22050          # plenty for blips; keeps the generated data small
const VOICES := 12           # simultaneous players; beyond this, drop the sound

enum Wave { SINE, SQUARE, SAW, NOISE }

## False under `--headless`, where there is no output device: play() would emit
## an engine error per call and drown the gates it is being run inside. The
## clips are still BUILT so the tests can inspect them.
var enabled := true

var _clips: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _built := false

func _ready() -> void:
	build()

## Idempotent, for the same reason Player/BulletPool are — see their build().
func build() -> void:
	if _built:
		return
	_built = true

	enabled = DisplayServer.get_name() != "headless"

	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)

	# name           wave         f0     f1    dur   vol  where it lands
	_make("fire",    Wave.SQUARE, 620.0, 400.0, 0.055, 0.10)   # under everything
	_make("hit",     Wave.SQUARE, 300.0, 180.0, 0.070, 0.20)   # bullet meets gel
	_make("kill",    Wave.SAW,    420.0,  70.0, 0.240, 0.30)   # the pop
	_make("enemy",   Wave.SINE,   240.0, 160.0, 0.090, 0.13)   # something shot at you
	_make("player",  Wave.SAW,    180.0,  60.0, 0.320, 0.36)   # you took one
	_make("dash",    Wave.NOISE,  900.0, 260.0, 0.160, 0.16)
	_make("wave",    Wave.SINE,   440.0, 880.0, 0.320, 0.26)   # a wave cleared
	_make("dead",    Wave.SAW,    300.0,  40.0, 0.900, 0.40)

## Builds one voice: a sweep from f0 to f1 over `dur` with an exponential decay.
func _make(name: String, wave: int, f0: float, f1: float, dur: float, vol: float) -> void:
	var n := int(RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)                      # 16-bit mono
	var phase := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name)                   # a voice is the same every run
	for i in n:
		var t := float(i) / float(n)
		var freq := lerpf(f0, f1, t)
		phase += TAU * freq / float(RATE)
		var s := 0.0
		match wave:
			Wave.SINE:   s = sin(phase)
			Wave.SQUARE: s = 1.0 if sin(phase) > 0.0 else -1.0
			Wave.SAW:    s = fposmod(phase, TAU) / PI - 1.0
			Wave.NOISE:  s = rng.randf_range(-1.0, 1.0)
		# Quick attack, exponential tail — a click at either end reads as a
		# glitch, so the first 4ms ramps in.
		var env := exp(-4.5 * t) * minf(1.0, t * float(n) / (0.004 * float(RATE)))
		var v := int(clampf(s * env * vol, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, v)

	var clip := AudioStreamWAV.new()
	clip.format = AudioStreamWAV.FORMAT_16_BITS
	clip.mix_rate = RATE
	clip.stereo = false
	clip.data = data
	_clips[name] = clip

## Fire and forget. `pitch` varies a repeated voice so a stream of shots does
## not turn into one flat buzz.
func play(name: String, pitch := 1.0) -> void:
	if not enabled or not _clips.has(name):
		return
	var p := _players[_next]
	_next = (_next + 1) % VOICES
	p.stream = _clips[name]
	p.pitch_scale = pitch
	p.play()

func play_varied(name: String, spread := 0.08) -> void:
	play(name, 1.0 + randf_range(-spread, spread))
