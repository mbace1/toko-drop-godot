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

var camera: Camera3D
var left := Stick.new()
var right := Stick.new()
var using_touch := false

var _dash_queued := false
var _pause_queued := false

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
