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

// Q-037 LEVEL SHAPES — upstream v238's FLOOR_FRAG term, the same math: the
// playable region as a signed distance in WORLD units from a fixed array of
// shape slots (x = kind: 0 unused, 1 rect, 2 circle; rect y=hx z=hz; circle
// y=cx z=cz w=r), union as min, intersect as max, an unused slot as the
// combine's neutral element — mix/step throughout, no branch. Inside is the
// floor as before; outside dims; the boundary glows the rail's colour.
// Four named uniforms rather than an array: the Compatibility tier is the
// one that ships, and four vec4s need no array-uniform support anywhere.
// The pass is OFF (u_shape_mode.x = 0) unless main.gd is running a level,
// so classic play's floor is the same expression it always was.
uniform vec4 u_shape0 = vec4(0.0);
uniform vec4 u_shape1 = vec4(0.0);
uniform vec4 u_shape2 = vec4(0.0);
uniform vec4 u_shape3 = vec4(0.0);
uniform vec2 u_shape_mode = vec2(0.0, 0.0);              // on, combine (0 union / 1 intersect)
uniform vec3 u_shape_look = vec3(0.45, 0.22, 0.55);      // edge band (world), outside dim, edge glow
uniform vec3 shape_edge_color : source_color = vec3(0.333, 0.333, 0.80);   // the rails' colour

// World xz of the fragment — the plane sits at the origin, so this is the
// same frame the level file and js/arena.js speak. No UV-orientation
// guesswork (PlaneMesh's v runs the other way from three.js's).
varying vec2 world_xz;

float shape_d(vec4 s, vec2 wp, float neutral) {
	float d_rect = max(abs(wp.x) - s.y, abs(wp.y) - s.z);
	float d_circ = length(wp - s.yz) - s.w;
	float d = mix(d_rect, d_circ, step(1.5, s.x));
	return mix(neutral, d, step(0.5, s.x));
}

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	float gx = abs(fract(UV.x * u_grid_x) - 0.5);
	float gz = abs(fract(UV.y * u_grid_z) - 0.5);
	float grid = max(0.0, 1.0 - min(gx, gz) * 50.0);
	float pulse = sin(u_time * 1.2) * 0.3 + 0.7;

	vec3 grid_color = mix(grid_lo, grid_hi, grid);
	float k = grid * pulse * 0.7;

	// Q-037: the region (see the uniform block).
	float neutral = mix(1e5, -1e5, u_shape_mode.y);
	float sd = neutral;
	float d0 = shape_d(u_shape0, world_xz, neutral);
	float d1 = shape_d(u_shape1, world_xz, neutral);
	float d2 = shape_d(u_shape2, world_xz, neutral);
	float d3 = shape_d(u_shape3, world_xz, neutral);
	sd = mix(min(sd, d0), max(sd, d0), u_shape_mode.y);
	sd = mix(min(sd, d1), max(sd, d1), u_shape_mode.y);
	sd = mix(min(sd, d2), max(sd, d2), u_shape_mode.y);
	sd = mix(min(sd, d3), max(sd, d3), u_shape_mode.y);
	float inside = 1.0 - smoothstep(0.0, u_shape_look.x, sd);
	float edge_glow = 1.0 - smoothstep(0.0, u_shape_look.x, abs(sd));
	float keep = mix(1.0, mix(u_shape_look.y, 1.0, inside), u_shape_mode.x);

	ALBEDO = base_color * keep;
	ROUGHNESS = 0.95;
	// The lines carry themselves; the plane stays dark so shadows still read.
	EMISSION = grid_color * k * keep + shape_edge_color * edge_glow * u_shape_look.z * u_shape_mode.x;
}
