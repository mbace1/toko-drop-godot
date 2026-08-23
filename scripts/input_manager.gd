## input_manager.gd
##
## Godot equivalent of toko-drop/js/input.js. The browser class polls touch
## sticks / gamepad / keyboard+mouse and exposes getMoveDir()/getAimDir(); this
## does the same job through Godot's Input singleton, so main.gd's game loop
## reads it exactly the same way each frame. Touch sticks are not ported yet
## (see PORT_STATUS.md) — desktop keyboard+mouse and gamepad are.
class_name InputManager
extends Node

const GP_DEADZONE := 0.20     # matches input.js GP_DEADZONE
const AIM_DEADZONE := 0.15    # world-space equivalent of input.js's pixel AIM_DEADZONE

var camera: Camera3D

## Returns a world-space XZ move vector (x = right, y = world Z / "forward").
## Gamepad left stick takes priority over keyboard, same order as input.js
## (gamepad > touch > keyboard).
func get_move_dir() -> Vector2:
	var gx := Input.get_joy_axis(0, JOY_AXIS_LEFT_X)
	var gy := Input.get_joy_axis(0, JOY_AXIS_LEFT_Y)
	if Vector2(gx, gy).length() > GP_DEADZONE:
		return Vector2(gx, gy).limit_length(1.0)
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")

## Returns {"x": float, "z": float, "valid": bool} — a world-space aim
## direction, or valid=false when nothing is aiming this frame (matches
## input.js getAimDir()'s {x,z,valid} shape). Gamepad right stick wins over
## mouse; mouse only aims while "fire" (LMB) is held, mirroring the browser's
## desktop fallback ("hold LMB + mouse to aim and fire").
func get_aim_dir(player_world_pos: Vector3) -> Dictionary:
	var gax := Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var gay := Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	if Vector2(gax, gay).length() > GP_DEADZONE:
		var gd := Vector2(gax, gay).normalized()
		return {"x": gd.x, "z": gd.y, "valid": true}

	if Input.is_action_pressed("fire") and camera != null:
		var mouse_pos := get_viewport().get_mouse_position()
		var from := camera.project_ray_origin(mouse_pos)
		var dir := camera.project_ray_normal(mouse_pos)
		var plane := Plane(Vector3.UP, player_world_pos.y)
		var hit = plane.intersects_ray(from, dir)
		if hit != null:
			var d := Vector2(hit.x - player_world_pos.x, hit.z - player_world_pos.z)
			if d.length() > AIM_DEADZONE:
				d = d.normalized()
				return {"x": d.x, "z": d.y, "valid": true}

	return {"x": 0.0, "z": 0.0, "valid": false}

func dash_pressed() -> bool:
	return Input.is_action_just_pressed("dash")

func pause_pressed() -> bool:
	return Input.is_action_just_pressed("pause")
