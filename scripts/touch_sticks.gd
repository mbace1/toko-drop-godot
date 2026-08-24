## touch_sticks.gd — draws the two virtual sticks over the game.
##
## The browser build paints its sticks on a full-res `#canvas-ui` overlay each
## frame (js/main.js); this is the same idea as a Control that redraws itself.
##
## Only appears once a touch has actually been seen — a mouse-and-keyboard
## player never gets thumb rings drawn over their arena, which is how the
## source behaves too (its sticks are drawn from live touch state).
class_name TouchSticks
extends Control

const RING := Color(1.0, 1.0, 1.0, 0.13)
const KNOB := Color(1.0, 1.0, 1.0, 0.22)
const HINT := Color(1.0, 1.0, 1.0, 0.30)

var input_mgr: InputManager
## Idle hints sit where a thumb naturally lands, so a first-time player can see
## there is something to press before they press it.
var show_hints := true

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

func _process(_delta: float) -> void:
	if input_mgr != null and input_mgr.using_touch:
		queue_redraw()

func _draw() -> void:
	if input_mgr == null or not input_mgr.using_touch:
		return
	var r := size
	for pair in [[input_mgr.left, 0.22], [input_mgr.right, 0.78]]:
		var s: InputManager.Stick = pair[0]
		var frac: float = pair[1]
		if s.active:
			# The stick lives where the thumb put it, not where the art is.
			draw_arc(s.origin, InputManager.STICK_RADIUS, 0.0, TAU, 48, RING, 2.0, true)
			var knob := s.origin + s.delta.limit_length(InputManager.STICK_RADIUS)
			draw_circle(knob, 26.0, KNOB)
		elif show_hints:
			var at := Vector2(r.x * frac, r.y * 0.78)
			draw_arc(at, InputManager.STICK_RADIUS, 0.0, TAU, 48, RING, 2.0, true)
			draw_circle(at, 22.0, Color(1, 1, 1, 0.08))

	if show_hints and not input_mgr.left.active and not input_mgr.right.active:
		var f := get_theme_default_font()
		var fs := 18
		_label(f, fs, Vector2(r.x * 0.22, r.y * 0.78 + 118.0), "MOVE")
		_label(f, fs, Vector2(r.x * 0.78, r.y * 0.78 + 118.0), "AIM · RELEASE = DASH")

func _label(f: Font, fs: int, at: Vector2, text: String) -> void:
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(f, at - Vector2(w * 0.5, 0.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, HINT)
