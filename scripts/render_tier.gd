## render_tier.gd — which renderer this build is actually running on, and
## therefore which of the gel's two looks it gets. Q-030.
##
## Owner decision 2026-09-04: "both, two quality tiers". The cabinet ships to
## the web on `gl_compatibility` (WebGL2 — project.godot, [rendering]), and
## Godot's own GLES3 compiler says what that costs, verbatim, on every launch:
##
##   WARNING: Subsurface scattering is only available when using the Forward+ renderer.
##   WARNING: Transmittance is only available when using the Forward+ renderer.
##   WARNING: Screen-space reflections (SSR) are only available when using the Forward+ renderer.
##
## (SSAO is dropped too, silently.) So the "gummy-bear read" PORT_BRIEF.md §2a
## builds on SSS_TRANSMITTANCE did not exist in the only build you can play on
## a phone, and nothing announced it. This class is the one place that fact is
## detected, so every consumer — the gel shader, the WorldEnvironment — reads
## the same answer rather than each guessing.
##
## Detection is `RenderingServer.get_rendering_device() == null`: Forward+ and
## Mobile run on a RenderingDevice, Compatibility does not. Headless counts as
## COMPAT, which is the conservative answer (nothing screen-space runs there
## either). `override` exists for the gate and for looking at the other tier
## on a desktop without re-exporting.
class_name RenderTier

const FORWARD_PLUS := "forward_plus"
const COMPAT := "compat"

## Global shader parameter names — declared in project.godot [shader_globals].
const G_COMPAT := "gel_compat"
const G_BACK_DIR := "gel_back_dir"

## "" = detect. Set to FORWARD_PLUS or COMPAT to force.
static var override := ""

## What apply() last pushed. The headless RenderingServer returns Nil from
## global_shader_parameter_get(), so the gate reads these instead; the picture
## is what proves the shader itself received them.
static var applied_compat := -1.0
static var applied_back_dir := Vector3.ZERO

static func detect() -> String:
	if override != "":
		return override
	# TOKO_TIER=compat|forward_plus in the environment forces a tier — how the
	# picture harness photographs the compat look on a desktop, and how the
	# "before" of any compat change is taken without re-exporting.
	var env := OS.get_environment("TOKO_TIER")
	if env == COMPAT or env == FORWARD_PLUS:
		return env
	return FORWARD_PLUS if RenderingServer.get_rendering_device() != null else COMPAT

static func is_compat() -> bool:
	return detect() == COMPAT

## Push the tier into the shader globals. `back_dir` is the direction the
## transmittance back light TRAVELS (world space, unit), which the compat
## tier's analytic transmittance needs and the Forward+ tier ignores.
static func apply(back_dir: Vector3) -> void:
	applied_compat = 1.0 if is_compat() else 0.0
	applied_back_dir = back_dir.normalized()
	RenderingServer.global_shader_parameter_set(G_COMPAT, applied_compat)
	RenderingServer.global_shader_parameter_set(G_BACK_DIR, applied_back_dir)
