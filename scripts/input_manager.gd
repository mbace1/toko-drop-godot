## input_manager.gd
##
## Godot equivalent of toko-drop/js/input.js. The browser class polls touch
## sticks / gamepad / keyboard+mouse and exposes getMoveDir()/getAimDir(); this
## does the same job and main.gd reads it the same way each frame.
##
## Source order of precedence, kept exactly: gamepad > touch > keyboard/mouse.
##
## TOUCH IS FIRST-CLASS — TOKO_DROP_ROADMAP.md §Guiding constraints: "Mobile
## touch is first-class. Every feature ships with a touch answer." The scheme is
## the browser's: the screen splits down the middle, a finger down on the left
## half plants a move stick where it landed, a finger on the right half plants
## an aim stick (which auto-fires while held), and RELEASING the right stick is
## the dash. Nothing is a fixed on-screen button, so the sticks are always
## under the thumb that reached for them.
class_name InputManager
extends Node

const GP_DEADZONE := 0.20      # input.js GP_DEADZONE
## input.js works in CSS pixels (STICK_RADIUS 60, AIM_DEADZONE 15). The project
## stretches a 1280x720 design space (canvas_items / expand), so these are in
## that space and scale with the screen rather than with the device's DPI.
const STICK_RADIUS := 80.0
const AIM_DEADZONE := 20.0
const PAUSE_ZONE_W := 90.0     # top-centre strip, as in input.js _touchStart
const PAUSE_ZONE_H := 60.0
## A tap that never travels and never lingers is a dash rather than an aim —
## otherwise a quick tap on the right half fires one frame and dashes nowhere.
const TAP_MAX_TIME := 0.25
const TAP_MAX_DIST := 14.0

class Stick:
	var active := false
	var origin := Vector2.ZERO
	var delta := Vector2.ZERO
	var touch_id := -1
	var down_at := 0.0
	var travelled := 0.0

	func vector() -> Vector2:
		return (delta / STICK_RADIUS).limit_length(1.0)

## Rush Mode needs a HELD boost, which the classic touch scheme cannot
## express — its dash fires on RELEASE of the aim stick. Owner direction was to
## try BOTH answers and put a toggle in a corner, so both are implemented and
## `boost_scheme` picks between them live:
##
##   RIM  — push the move stick past BOOST_RIM_FRAC of its travel. No new
##          screen furniture, and it reads as "run harder", but it costs you
##          the ability to walk at full speed without boosting.
##   ZONE — a dedicated pad in the bottom-left corner held with a third
##          finger (or the left thumb sliding down onto it). Costs screen
##          space, but move and boost stay independent.
enum BoostScheme { RIM, ZONE }

const BOOST_RIM_FRAC := 0.86
const BOOST_ZONE_R := 78.0
const TOGGLE_R := 30.0

var boost_scheme := BoostScheme.RIM
var camera: Camera3D
var left := Stick.new()
var right := Stick.new()
var using_touch := false

var _dash_queued := false
var _pause_queued := false
var _ability_queued := false
var _boost_zone_touch := -1
var _rush_active := false      # main.gd raises this so the zone/toggle exist

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_on_touch(event)
	elif event is InputEventScreenDrag:
		_on_drag(event)

func _on_touch(e: InputEventScreenTouch) -> void:
	if e.pressed:
		using_touch = true
		# Pause strip along the top centre — the one place a touch is not a stick.
		if e.position.y < PAUSE_ZONE_H and absf(e.position.x - _screen_mid()) < PAUSE_ZONE_W * 0.5:
			_pause_queued = true
			return
		# The scheme toggle: a small corner target, live only in Rush Mode.
		if _rush_active and e.position.distance_to(toggle_pos()) < TOGGLE_R:
			boost_scheme = BoostScheme.ZONE if boost_scheme == BoostScheme.RIM \
				else BoostScheme.RIM
			return
		# The boost pad, when that scheme is selected.
		if _rush_active and boost_scheme == BoostScheme.ZONE \
				and e.position.distance_to(boost_zone_pos()) < BOOST_ZONE_R:
			_boost_zone_touch = e.index
			return
		# The ability pad, bottom-centre, always live in Rush.
		if _rush_active and e.position.distance_to(ability_pos()) < BOOST_ZONE_R:
			_ability_queued = true
			return

		var s := left if e.position.x < _screen_mid() else right
		if s.active:
			return                      # that half already has a finger on it
		s.active = true
		s.touch_id = e.index
		s.origin = e.position
		s.delta = Vector2.ZERO
		s.down_at = _now()
		s.travelled = 0.0
	else:
		if e.index == _boost_zone_touch:
			_boost_zone_touch = -1
			return
		for s in [left, right]:
			if s.touch_id != e.index:
				continue
			# Releasing the AIM stick is the dash (input.js _touchEnd), and a
			# quick stationary tap on either half is a dash too.
			var quick: bool = (_now() - s.down_at < TAP_MAX_TIME) and (s.travelled < TAP_MAX_DIST)
			if s == right or quick:
				_dash_queued = true
			s.active = false
			s.touch_id = -1
			s.delta = Vector2.ZERO

func _on_drag(e: InputEventScreenDrag) -> void:
	for s in [left, right]:
		if s.touch_id == e.index:
			s.delta = e.position - s.origin
			s.travelled = maxf(s.travelled, s.delta.length())

func _screen_mid() -> float:
	return get_viewport().get_visible_rect().size.x * 0.5

func _screen() -> Vector2:
	return get_viewport().get_visible_rect().size

func boost_zone_pos() -> Vector2:
	var r := _screen()
	return Vector2(r.x * 0.10, r.y * 0.50)

func ability_pos() -> Vector2:
	var r := _screen()
	return Vector2(r.x * 0.90, r.y * 0.50)

func toggle_pos() -> Vector2:
	return Vector2(_screen().x - 46.0, 46.0)

func set_rush(active: bool) -> void:
	_rush_active = active
	if not active:
		_boost_zone_touch = -1

## Held, unlike dash. Gamepad: left trigger or B. Keyboard: Shift (held).
func boost_held() -> bool:
	if Input.is_key_pressed(KEY_SHIFT):
		return true
	if Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT) > 0.4 \
			or Input.is_joy_button_pressed(0, JOY_BUTTON_B):
		return true
	if _boost_zone_touch != -1:
		return true
	if boost_scheme == BoostScheme.RIM and left.active:
		return left.delta.length() >= STICK_RADIUS * BOOST_RIM_FRAC
	return false

## The move vector, with the boost deadband removed under the RIM scheme so
## that pushing to the rim does not also mean "steer harder".
func get_move_dir_rush() -> Vector2:
	var v := get_move_dir()
	return v.limit_length(1.0)

func ability_pressed() -> bool:
	if _ability_queued:
		_ability_queued = false
		return true
	return Input.is_key_pressed(KEY_Q) and not _q_was_down \
		or Input.is_joy_button_pressed(0, JOY_BUTTON_X) and not _x_was_down

var _q_was_down := false
var _x_was_down := false

## Called once a frame by main.gd so the key/pad edges above are honest.
func poll_edges() -> void:
	_q_was_down = Input.is_key_pressed(KEY_Q)
	_x_was_down = Input.is_joy_button_pressed(0, JOY_BUTTON_X)

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

## Returns a world-space XZ move vector (x = right, y = world Z).
func get_move_dir() -> Vector2:
	var gx := Input.get_joy_axis(0, JOY_AXIS_LEFT_X)
	var gy := Input.get_joy_axis(0, JOY_AXIS_LEFT_Y)
	if Vector2(gx, gy).length() > GP_DEADZONE:
		return Vector2(gx, gy).limit_length(1.0)
	if left.active:
		return left.vector()
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")

## Returns {"x", "z", "valid"} — a world-space aim direction, or valid=false
## when nothing is aiming. Matches input.js getAimDir()'s shape.
func get_aim_dir(player_world_pos: Vector3) -> Dictionary:
	var gax := Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var gay := Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	if Vector2(gax, gay).length() > GP_DEADZONE:
		var gd := Vector2(gax, gay).normalized()
		return {"x": gd.x, "z": gd.y, "valid": true}

	# Touch: the aim stick auto-fires while held past the deadzone.
	if right.active:
		if right.delta.length() < AIM_DEADZONE:
			return {"x": 0.0, "z": 0.0, "valid": false}
		var td := right.delta.normalized()
		return {"x": td.x, "z": td.y, "valid": true}

	if Input.is_action_pressed("fire") and camera != null:
		var mouse_pos := get_viewport().get_mouse_position()
		var from := camera.project_ray_origin(mouse_pos)
		var dir := camera.project_ray_normal(mouse_pos)
		var plane := Plane(Vector3.UP, player_world_pos.y)
		var hit = plane.intersects_ray(from, dir)
		if hit != null:
			var d := Vector2(hit.x - player_world_pos.x, hit.z - player_world_pos.z)
			if d.length() > 0.15:
				d = d.normalized()
				return {"x": d.x, "z": d.y, "valid": true}

	return {"x": 0.0, "z": 0.0, "valid": false}

## Edge-triggered, and drained on read so one press cannot fire twice.
func dash_pressed() -> bool:
	if _dash_queued:
		_dash_queued = false
		return true
	return Input.is_action_just_pressed("dash")

func pause_pressed() -> bool:
	if _pause_queued:
		_pause_queued = false
		return true
	return Input.is_action_just_pressed("pause")

## Drops any held stick — call when a run ends, or a finger still down at the
## death screen keeps steering the next run.
func reset() -> void:
	for s in [left, right]:
		s.active = false
		s.touch_id = -1
		s.delta = Vector2.ZERO
	_dash_queued = false
	_ability_queued = false
	_boost_zone_touch = -1
