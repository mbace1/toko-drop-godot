## spittor.gd
##
## SPITTOR — the first ranged type: a big slow blob that holds you at arm's
## length and spits a ring of 8.
##
## Stats from enemy.js's CFG table (line 487):
##   color 0xff5533, radius 0.9, speed 1.6, hp 3,
##   bulletColor 0xff7755, fireInterval 2.2
##
## Movement is the HOLDER archetype (TUNING.movement.byType: SPITTOR: 'HOLDER')
## — enemy.js's SPITTOR case holds `want = 10` with a ±1 hysteresis band.
##
## The tell is TOKO_DROP_PORT_BRIEF.md Part 2: "Inflates up to +22% scale over
## the 0.45s before firing… Recoils 0.18 units backward on fire with hitWobble
## 0.3." Those three numbers are TUNING.blob.spittorInflate / spittorInflateTime
## / spittorRecoil (tuning.js line 40). The ring is aimed so one bullet leads
## straight at the player (enemy.js line 2586).
class_name Spittor
extends Enemy

const HOLD_RANGE := 10.0
const HOLD_BAND := 1.0
const INFLATE := 0.22          # TUNING.blob.spittorInflate
const INFLATE_TIME := 0.45     # TUNING.blob.spittorInflateTime
const RECOIL := 0.18           # TUNING.blob.spittorRecoil
const RING_COUNT := 8

func init() -> void:
	setup(Color(1.0, 0.333, 0.2), 0.9, 1.6, 3, false)
	bullet_color = Color(1.0, 0.467, 0.333)
	fire_interval = 2.2
	revenge_dialect = Revenge.AIMED   # TUNING.revenge.byType: SPITTOR -> AIMED

func update(delta: float) -> void:
	_update_common(delta)
	if not alive:
		return

	_hold_at_range(delta, HOLD_RANGE, HOLD_BAND)

	# Swell through the wind-up so the shot is readable before it happens.
	if _is_telegraphing:
		var k := 1.0 - clampf(_telegraph_t / INFLATE_TIME, 0.0, 1.0)
		_inflate = INFLATE * k

	if _tick_fire(delta, INFLATE_TIME):
		var base := _angle_to_target()
		_sqv -= 1.0                      # squash on fire
		_hit_wobble = maxf(_hit_wobble, 0.3)
		# Kick backward off the shot, then fire from where it stood.
		var fx := position.x
		var fz := position.z
		position.x -= cos(base) * RECOIL
		position.z -= sin(base) * RECOIL
		_clamp_to_arena()
		_ring(fx, fz, RING_COUNT, base)
