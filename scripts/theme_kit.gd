## theme_kit.gd — the one place the port's typography is decided.
##
## The browser build sets `font-family: monospace` on its whole overlay
## (index.html `#overlay`) and every screen of it — title, HUD, pause, death,
## the on-screen stick hints — is that one typeface. This port shipped with no
## font at all, so it rendered in Godot's default proportional sans and read as
## a different game entirely in a screenshot beside the original (found
## 2026-08-27 by capturing both builds at the same phone profile).
##
## The font is BUNDLED rather than asked for by name. `SystemFont` was tried
## first: it works on desktop and silently resolves to NOTHING in a Web export,
## because the browser sandbox gives Godot no OS font access — so the one
## platform this actually ships on was the one platform where it did nothing.
## That was caught by exporting and screenshotting rather than by reasoning
## about it, which is the only way this class of bug ever shows up.
##
## JetBrains Mono Regular, SIL OFL 1.1. The license is kept beside the file in
## `assets/fonts/OFL.txt` because that license requires it to travel with the
## font — do not delete it when trimming the tree.
class_name ThemeKit

const MONO_PATH := "res://assets/fonts/JetBrainsMono-Regular.ttf"

## main.js's overlay carries `text-shadow: 0 0 24px #ff4422, 0 0 60px #aa00ff`
## — an orange-into-violet neon bloom that is most of why its text reads as lit
## signage rather than as a caption. Godot has no multi-layer text shadow, so
## this approximates the inner (orange) half with a soft zero-offset shadow and
## leaves the violet outer half to the scene's own bloom. The alpha is
## deliberately low: at full strength the halo stops being a glow behind white
## text and starts tinting the letterforms themselves orange.
const GLOW_COLOR := Color(1.0, 0.27, 0.13, 0.33)
const GLOW_SIZE := 10

static var _mono: Font = null

static func mono() -> Font:
	if _mono != null:
		return _mono
	if ResourceLoader.exists(MONO_PATH):
		_mono = load(MONO_PATH)
	if _mono == null:
		# Never fail to a blank screen over a font. Fall back to whatever the
		# OS can offer, and past that to Godot's own default.
		var f := SystemFont.new()
		f.font_names = PackedStringArray([
			"monospace", "Consolas", "DejaVu Sans Mono", "Courier New", "Menlo",
		])
		_mono = f
	return _mono

## The OVERLAY look — title, pause, death, the level recap. Monospace, the
## size asked for, and the neon glow, because in the browser all of that text
## lives inside `#overlay` and inherits its `text-shadow`.
static func style_label(l: Label, font_size: int,
		color := Color(0.9, 0.95, 1.0)) -> void:
	l.add_theme_font_override("font", mono())
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", GLOW_COLOR)
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 0)
	l.add_theme_constant_override("shadow_outline_size", GLOW_SIZE)

## The IN-GAME HUD look — WAVE, SCORE, the HP pips. Deliberately NOT the same
## as the overlay: in the browser the HUD is painted on its own `#canvas-ui`
## 2D context (main.js ~line 4136), which never sees `#overlay`'s CSS
## `text-shadow`, and it is drawn in flat `rgba(255,255,255,0.55)`. Glowing the
## HUD the way the menu glows made it read as hot orange signage sitting on top
## of the arena instead of the quiet, recessive readout the source has — caught
## by screenshotting a real run, not by reading the CSS.
static func style_hud_label(l: Label, font_size: int) -> void:
	l.add_theme_font_override("font", mono())
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.55))
	l.add_theme_constant_override("shadow_outline_size", 0)
