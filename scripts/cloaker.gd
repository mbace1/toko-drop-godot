## cloaker.gd
##
## CLOAKER — "visible → cloak-and-flank → decloak tell → burst" (enemy.js
## v143, the comment above its state block). It is not a stealth enemy in
## the sense of being safe to ignore: it is STILL HITTABLE the whole time it
## is cloaked (enemy.js: "Still hittable — tracking pays"), so this port
## needs no special-cased collision skip — a lower `alpha_amt` on the shared
## gel shader is the entire mechanic, and the existing radius-overlap
## collision does the rest for free.
##
## Stats — CFG (enemy.js line 507):
##   color 0x66ddee, radius 0.7, speed 2.4, hp 3, bulletColor 0x88eeff,
##   fireInterval null (it never fires on a clock — only on decloak).
##
## Cycle (enemy.js line 1528, the EnemyType.CLOAKER switch case):
##   VISIBLE  0.8-1.4s  — holds position, full opacity, no shimmer.
##   CLOAK    1.8-2.4s  — opacity 0.14 (+shimmer), shimmer-runs to a flank
##                        point ~90°±0.6rad around the player at range 6.5-8.
##   DECLOAK  0.6s      — fades 0.14→1.0 opacity, rim strobes as the tell,
##                        then fires a 3-shot ±0.18rad spread AT the player
##                        and returns to VISIBLE.
class_name Cloaker
extends Enemy

enum CkState { VISIBLE, CLOAK, DECLOAK }

const KEEP_RANGE_MIN := 6.5
const KEEP_RANGE_SPAN := 1.5
const DECLOAK_DUR := 0.6
const CLOAK_ALPHA := 0.14
const SHIMMER_HZ := 9.0
const STROBE_HZ := 24.0

var _state := CkState.VISIBLE
var _ck_t := 0.0
var _ck_target := Vector2.ZERO
var _rim_default: Color

func init() -> void:
	setup(Color(0.4, 0.867, 0.933), 0.7, 2.4, 3, false)
	bullet_color = Color(0.533, 0.933, 1.0)
	fire_interval = 0.0   # no clock-driven fire — only the decloak burst
	revenge_dialect = Revenge.AIMED
	_rim_default = color.lightened(0.55)
	_ck_t = 0.8 + rng.randf() * 0.6

func update(delta: float) -> void:
	_update_common(delta)
	if not alive:
		return
	_ck_t -= delta
	match _state:
		CkState.VISIBLE:
			if _ck_t <= 0.0:
				_state = CkState.CLOAK
				_ck_t = 1.8 + rng.randf() * 0.6
				var side := 1.0 if rng.randf() < 0.5 else -1.0
				var a0 := atan2(position.z - target.position.z, position.x - target.position.x) \
					+ side * (PI / 2.0 + rng.randf() * 0.6)
				var r0 := KEEP_RANGE_MIN + rng.randf() * KEEP_RANGE_SPAN
				_ck_target = Vector2(target.position.x + cos(a0) * r0,
					target.position.z + sin(a0) * r0)
		CkState.CLOAK:
			mat.set_shader_parameter("alpha_amt", CLOAK_ALPHA + 0.05 * sin(_t * SHIMMER_HZ))
			var mx := _ck_target.x - position.x
			var mz := _ck_target.y - position.z
			var ml := sqrt(mx * mx + mz * mz)
			if ml > 0.3:
				position.x += (mx / ml) * speed * delta
				position.z += (mz / ml) * speed * delta
				_clamp_to_arena()
			if _ck_t <= 0.0 or ml <= 0.3:
				_state = CkState.DECLOAK
				_ck_t = DECLOAK_DUR
		CkState.DECLOAK:
			var k := 1.0 - clampf(_ck_t, 0.0, DECLOAK_DUR) / DECLOAK_DUR
			mat.set_shader_parameter("alpha_amt", CLOAK_ALPHA + (1.0 - CLOAK_ALPHA) * k)
			mat.set_shader_parameter("rim_color",
				Color(0.133, 0.4, 0.467) if sin(_t * STROBE_HZ) > 0.0 else Color.BLACK)
			if _ck_t <= 0.0:
				mat.set_shader_parameter("alpha_amt", _base_alpha)
				mat.set_shader_parameter("rim_color", _rim_default)
				var base_a := _angle_to_target()
				for off in [-0.18, 0.0, 0.18]:
					bullets.spawn_dir(position.x, position.z,
						cos(base_a + off), sin(base_a + off), false, bullet_color)
				_state = CkState.VISIBLE
				_ck_t = 0.9 + rng.randf() * 0.5
