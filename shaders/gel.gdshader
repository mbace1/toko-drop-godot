// gel.gdshader — shared "living jelly" material for every enemy + the player.
//
// One shader drives every body via per-instance uniforms, mirroring the
// browser's single satin-gel MeshPhysicalMaterial family (toko-drop/js/enemy.js
// `makeSatinMat`) and the parameter table in PORT_BRIEF.md §0/§1.
//
// ── Why this is OPAQUE, and why ALPHA still works ───────────────────────────
// Godot's subsurface scattering is a screen-space pass over OPAQUE geometry:
// an alpha-blended body writes no depth and gets no SSS, so the moment this
// material went `blend_mix` the whole point of §2a was lost. Instead it stays
// in the opaque pass and uses ALPHA_HASH_SCALE — hashed (dithered) alpha —
// so the death pop and the i-frame flicker can still fade a body out without
// giving up the scattering. A 0.28s pop and a 12Hz blink are exactly the
// places where a little dither costs nothing.
//
// PORT_BRIEF.md §2a is explicit that the browser's `emissiveIntensity` glow is
// "a fake stand-in; replace it entirely with real SSS here" — hence the low
// emission and the work being done by SSS_TRANSMITTANCE + BACKLIGHT.

shader_type spatial;
render_mode depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Base look — PORT_BRIEF.md §0 blob/cube MeshPhysicalMaterial params.
uniform vec4  gel_color : source_color = vec4(0.0, 0.8, 0.67, 1.0);
uniform float emission_intensity : hint_range(0.0, 1.0) = 0.06;
uniform float roughness_amt : hint_range(0.0, 1.0) = 0.07;
uniform float specular_amt : hint_range(0.0, 1.0) = 0.85;
uniform float alpha_amt : hint_range(0.0, 1.0) = 1.0;

// Wet candy shell — `clearcoat` / `clearcoatRoughness` in the source table.
uniform float clearcoat_amt : hint_range(0.0, 1.0) = 0.9;
uniform float clearcoat_rough : hint_range(0.0, 1.0) = 0.04;

// ── The gummy-bear read (PORT_BRIEF.md §2a) ─────────────────────────────────
// `thickness` in the browser is radius-derived and constant per body; here the
// silhouette does the job analytically. |N·V| is ~1 looking through the middle
// of a body and ~0 at its rim, so `thin` rises toward the edge — which is
// where a real gel is thinnest and therefore glows brightest. That is the
// "center thick -> edges thin radial gradient" the brief asks for as a texture,
// without shipping a texture for something a sphere already knows.
uniform float sss_strength : hint_range(0.0, 1.0) = 0.75;
uniform float sss_depth : hint_range(0.01, 8.0) = 0.55;
uniform float sss_boost : hint_range(0.0, 4.0) = 1.6;
uniform float backlight_amt : hint_range(0.0, 1.0) = 0.45;

// Fresnel rim — PORT_BRIEF.md §0 "Fresnel rim" fragment injection.
uniform vec4  rim_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float rim_power : hint_range(1.0, 8.0) = 2.6;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.70;

// Vertex ripple + hit shockwave — PORT_BRIEF.md §0 "Vertex ripple" injection.
// wobble_time is a free-running clock (u_wt); hit_wobble decays after each hit
// (u_hw). Both are driven per-instance from the owning enemy/player each frame.
uniform float wobble_time : hint_range(0.0, 1000.0) = 0.0;
uniform float wobble_amp : hint_range(0.0, 1.0) = 1.0;
uniform float hit_wobble : hint_range(0.0, 1.0) = 0.0;

void vertex() {
	vec3 p = VERTEX;
	float b = (sin(p.y * 3.8 + wobble_time * 5.2) * 0.22
	         + cos(p.x * 3.2 + wobble_time * 4.7) * 0.16
	         + cos(p.z * 3.5 + wobble_time * 5.8) * 0.12) * wobble_amp * 0.12;
	float h = sin(length(p) * 8.0 - wobble_time * 18.0) * hit_wobble * 0.55 * 0.12;
	VERTEX += NORMAL * (b + h);
}

void fragment() {
	ALBEDO = gel_color.rgb;
	METALLIC = 0.0;
	ROUGHNESS = roughness_amt;
	SPECULAR = specular_amt;

	ALPHA = alpha_amt;
	ALPHA_HASH_SCALE = 1.0;   // keeps the body in the opaque pass — see header

	CLEARCOAT = clearcoat_amt;
	CLEARCOAT_ROUGHNESS = clearcoat_rough;

	// 0 through the middle of the body, 1 at the silhouette.
	float thin = 1.0 - abs(dot(normalize(NORMAL), normalize(VIEW)));

	// Real scattering. TRANSMITTANCE is what lets a light behind the body bleed
	// through it in the body's own colour — the gummy-bear read, and the reason
	// main.gd now puts a light behind the arena as well as above it.
	SSS_STRENGTH = sss_strength;
	SSS_TRANSMITTANCE_COLOR = vec4(gel_color.rgb, 1.0);
	SSS_TRANSMITTANCE_DEPTH = sss_depth;
	SSS_TRANSMITTANCE_BOOST = sss_boost * thin;

	// Cheap always-on wrap so the body reads translucent even facing the key
	// light, where transmittance has nothing behind it to carry.
	BACKLIGHT = gel_color.rgb * backlight_amt * (0.35 + 0.65 * thin);

	EMISSION = gel_color.rgb * emission_intensity
	         + rim_color.rgb * pow(thin, rim_power) * rim_strength;
}
