## fanner.gd
##
## FANNER — a wide flat pancake that circles you at mid range and throws
## arcs of bullets across your escape route.
##
## Stats from enemy.js's CFG table (line 488):
##   color 0xff00aa, radius 0.75, speed 1.4, hp 3,
##   bulletColor 0xff66cc, fireInterval 1.5
##
## Movement: HOLDER (TUNING.movement.byType) — enemy.js's FANNER case holds
## `want = 8` with a ±1.5 band while strafing perpendicular, flipping the
## strafe direction every 2.5–3.5s.
##
## The volley is enemy.js line ~2600: "Every 3rd volley fans wider with more
## shots — a heavier beat." Normal = 6 shots across 0.6π; every third = 9
## shots across 0.95π. Telegraph is a flat 0.4s.
##
## Silhouette per TOKO_DROP_PORT_BRIEF.md Part 2: "FANNER: wide flat pancake;
## rocks rotation.z = sin(t·7)·0.10 while strafing" (TUNING.blob.shapes.FANNER
## is {x:1.30, y:0.66, z:1.08}).
class_name Fanner
extends Enemy

const HOLD_RANGE := 8.0
const HOLD_BAND := 1.5
const WINDUP := 0.4
const ROCK_HZ := 7.0
const ROCK_AMP := 0.10         # TUNING.blob.fannerSway

var _strafe_dir := 1.0
var _strafe_timer := 0.0
var _shot_index := 0

func init() -> void:
	setup(Color(1.0, 0.0, 0.667), 0.75, 1.4, 3, false)
	bullet_color = Color(1.0, 0.4, 0.8)
	fire_interval = 1.5
	revenge_dialect = Revenge.FAN     # TUNING.revenge.byType: FANNER -> FAN
	_strafe_dir = 1.0 if randf() < 0.5 else -1.0
	_strafe_timer = 2.5 + randf()
	# Wide flat pancake — TUNING.blob.shapes.FANNER.
	mesh.scale = Vector3(1.30, 0.66, 1.08)

func update(delta: float) -> void:
	_update_common(delta)
	if not alive:
		return

	_strafe_timer -= delta
	if _strafe_timer <= 0.0:
		_strafe_dir = -_strafe_dir
		_strafe_timer = 2.5 + randf()

	_hold_at_range(delta, HOLD_RANGE, HOLD_BAND, _strafe_dir)

	# Rocks as it circles. _update_common owns mesh.scale, so the rock goes on
	# the rotation and the pancake proportions are re-applied on top of the
	# spring squash rather than fighting it.
	mesh.rotation.z = sin(_t * ROCK_HZ) * ROCK_AMP
	mesh.scale *= Vector3(1.30, 0.66, 1.08)

	if _tick_fire(delta, WINDUP):
		_sqv -= 0.8                      # squash on fire
		_shot_index = (_shot_index + 1) % 3
		var wide := _shot_index == 0
		var count := 9 if wide else 6
		var span := PI * 0.95 if wide else PI * 0.6
		_fan(position.x, position.z, count, span, _angle_to_target())
