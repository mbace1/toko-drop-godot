// floor_grid.gdshader — the arena floor.
//
// Direct port of the browser build's FLOOR_FRAG / makeFloorMat()
// (toko-drop/js/main.js line ~412). Same math, same constants:
//
//   gx    = abs(fract(uv.x * uGridX) - 0.5)
//   gz    = abs(fract(uv.y * uGridZ) - 0.5)
//   grid  = max(0, 1 - min(gx, gz) * 50)
//   pulse = sin(uTime * 1.2) * 0.3 + 0.7
//   col   = mix(#141428, mix(#221260 -> #008c80, grid), grid * pulse * 0.7)
//
// The source's own note on why this exists at all: a plain dark floor "made
// distances hard to judge", and the grid "gives the floor a sense of scale
// without becoming scenery".
//
// ONE DELIBERATE IMPROVEMENT over the source, which uses MeshBasicMaterial
// (unlit): here the grid is EMISSION over a dark ALBEDO on a lit material, so
// the lines still glow and bloom exactly as before, but the floor also keeps
// receiving the cast shadows the Godot port has. A body's contact shadow is
// most of how you read where it actually is on the plane, and an unlit floor
// throws that away.

shader_type spatial;
render_mode diffuse_burley, specular_disabled;

uniform float u_time = 0.0;
uniform float u_grid_x = 29.55;   // (HALF_X * 2) / GRID_CELL
uniform float u_grid_z = 17.11;   // (HALF_Z * 2) / GRID_CELL

uniform vec3 base_color : source_color = vec3(0.079, 0.079, 0.169);
uniform vec3 grid_lo : source_color = vec3(0.13, 0.07, 0.38);
uniform vec3 grid_hi : source_color = vec3(0.00, 0.55, 0.50);

void fragment() {
	float gx = abs(fract(UV.x * u_grid_x) - 0.5);
	float gz = abs(fract(UV.y * u_grid_z) - 0.5);
	float grid = max(0.0, 1.0 - min(gx, gz) * 50.0);
	float pulse = sin(u_time * 1.2) * 0.3 + 0.7;

	vec3 grid_color = mix(grid_lo, grid_hi, grid);
	float k = grid * pulse * 0.7;

	ALBEDO = base_color;
	ROUGHNESS = 0.95;
	// The lines carry themselves; the plane stays dark so shadows still read.
	EMISSION = grid_color * k;
}
