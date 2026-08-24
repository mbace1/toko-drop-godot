## globbo.gd
##
## GLOBBO — the base chaser blob, and a pouncer rather than a plain follower.
##
## Stats from enemy.js's CFG table (line 486):
##   color 0x00ccaa, radius 0.55, speed 2.8, hp 1
##
## Two behaviours stack, both from enemy.js's GLOBBO case (line 1397):
##
##  1. The lunging-slime speed pulse (TOKO_DROP_PORT_BRIEF.md Part 2):
##       speed × (max(0, sin(t·globboLungeHz + φ))² · globboLungeGain + globboLungeFloor)
##     = speed × (max(0, sin(t·3.0 + φ))² · 2.6 + 0.4)   — tuning.js line 43.
##     It surges and settles as it stalks, so it never reads as a constant
##     crawl toward you.
##
##  2. A stalk → crouch → leap state machine on top of that. The crouch is a
##     0.32s squash that telegraphs the leap; the leap commits to the
##     direction captured at crouch time and travels at 3.2× speed. That
##     commitment is what makes GLOBBO dodgeable — it cannot correct mid-leap.
class_name Globbo
extends Enemy

const LUNGE_HZ := 3.0          # TUNING.blob.globboLungeHz
const LUNGE_GAIN := 2.6        # TUNING.blob.globboLungeGain
const LUNGE_FLOOR := 0.4       # TUNING.blob.globboLungeFloor

const CROUCH_TIME := 0.32
const LEAP_TIME := 0.30
const LEAP_SPEED_MULT := 3.2
const POUNCE_RANGE := 12.0     # won't commit to a leap from further than this
const STOP_DIST := 1.2         # already on top of the player; stop closing

enum Pounce { STALK, CROUCH, LEAP }

var _phase := 0.0
var _state := Pounce.STALK
var _pounce_t := 0.0
var _leap_dir := Vector2.ZERO

func init() -> void:
	setup(Color(0.0, 0.8, 0.667), 0.55, 2.8, 1, false)
	_phase = rng.randf() * TAU
	_pounce_t = 1.6 + rng.randf() * 1.4

func update(delta: float) -> void:
	_update_common(delta)
	if not alive or target == null:
		return

	var dx := target.position.x - position.x
	var dz := target.position.z - position.z
	var dist := Vector2(dx, dz).length()
	if dist < 0.001:
		return
	var nx := dx / dist
	var nz := dz / dist

	_pounce_t -= delta

	match _state:
		Pounce.STALK:
			if dist > STOP_DIST:
				var s := maxf(0.0, sin(_t * LUNGE_HZ + _phase))
				var lunge := s * s * LUNGE_GAIN + LUNGE_FLOOR
				position.x += nx * speed * lunge * delta
				position.z += nz * speed * lunge * delta
			if _pounce_t <= 0.0 and dist < POUNCE_RANGE:
				_state = Pounce.CROUCH
				_pounce_t = CROUCH_TIME
				_sqv -= 0.85                  # crouch squash — the tell
				_leap_dir = Vector2(nx, nz)   # committed here, not at launch
		Pounce.CROUCH:
			if _pounce_t <= 0.0:
				_state = Pounce.LEAP
				_pounce_t = LEAP_TIME
				_sqv += 0.7                   # stretch on launch
		Pounce.LEAP:
			position.x += _leap_dir.x * speed * LEAP_SPEED_MULT * delta
			position.z += _leap_dir.y * speed * LEAP_SPEED_MULT * delta
			if _pounce_t <= 0.0:
				_state = Pounce.STALK
				_pounce_t = 1.6 + rng.randf() * 1.4

	_clamp_to_arena()
