// gel.gdshader — shared "living jelly" material for every enemy + the player.
//
// One shader drives every body via per-instance uniforms (set through
// MeshInstance3D.set_instance_shader_parameter), mirroring the browser's
// single satin-gel MeshPhysicalMaterial family (toko-drop/js/enemy.js
// `makeSatinMat`) and the parameter table in PORT_BRIEF.md §0/§1.
//
// Status (see PORT_STATUS.md): vertex ripple + hit shockwave, Fresnel rim
// glow and CPU-driven squash/breathe (set from GDScript, not in here) are
// ported. True subsurface scattering, screen-space refraction and thin-film
// iridescence are staged follow-ups (PORT_BRIEF.md §2a is the next step —
// swap ALBEDO/ALPHA here for StandardMaterial3D's subsurf_scatter_* once a
// thickness texture exists).

shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Base look — mirrors PORT_BRIEF.md §0 blob/cube MeshPhysicalMaterial params.
uniform vec4  gel_color : source_color = vec4(0.0, 0.8, 0.67, 1.0);
uniform float emission_intensity : hint_range(0.0, 1.0) = 0.10;
uniform float roughness_amt : hint_range(0.0, 1.0) = 0.06;
uniform float alpha_amt : hint_range(0.0, 1.0) = 0.92;   // stand-in for `transmission` until refraction lands
uniform float specular_amt : hint_range(0.0, 1.0) = 0.65;

// Fresnel rim — PORT_BRIEF.md §0 "Fresnel rim" fragment injection.
uniform vec4  rim_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float rim_power : hint_range(1.0, 8.0) = 4.0;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.7;

// Vertex ripple + hit shockwave — PORT_BRIEF.md §0 "Vertex ripple" injection.
// wobble_time is a free-running clock (u_wt); hit_wobble decays after each
// hit (u_hw). Both are driven per-instance from the owning enemy/player each
// frame — see scripts/enemy.gd `_update_shader_uniforms`.
uniform float wobble_time : hint_range(0.0, 1000.0) = 0.0;
uniform float wobble_amp : hint_range(0.0, 1.0) = 1.0;   // 0 disables ripple (flat-faced cubes)
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

	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	EMISSION = gel_color.rgb * emission_intensity + rim_color.rgb * fres * rim_strength;
}
