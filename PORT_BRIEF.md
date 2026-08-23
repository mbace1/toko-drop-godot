# Toko Drop — Godot 4 Visual Port Brief

**Audience:** a dispatch agent porting the gel/VFX look of `toko-drop` (Three.js r167) into **Godot 4.3+ (Forward+ / Vulkan)**.
**Goal:** cross the line from "nice gel material" to **alive jelly creatures** — moist jelly trails, glistening dew on Jell-O bodies, and protruding tentacles of jelly that drag on the floor.

This doc maps each existing browser system to its Godot equivalent and lists the features that are **only possible in Godot** (true SSS, screen-space refraction, GPU particle collision, verlet tentacles, SDFGI/SSR).

---

## 0. Source of truth — current Three.js implementation

The browser build is the visual reference. Match these parameters when authoring Godot materials. Source files: `toko-drop/js/enemy.js` (materials, vertex/fragment shader injection), `toko-drop/js/main.js` (post-processing, trails, IBL).

### Blob material (GLOBBO / SPITTOR / FANNER / WEEVA / SPLITTA)
`MeshPhysicalMaterial`:
```
color               = cfg.color
emissive            = cfg.color
emissiveIntensity   = 0.10
roughness           = 0.02
metalness           = 0.0
transmission        = 0.78
thickness           = radius * 2.4
ior                 = 1.42
clearcoat           = 0.90
clearcoatRoughness  = 0.04
attenuationColor    = cfg.color          // colour absorbed through body
attenuationDistance = radius * 1.4
iridescence         = 0.45               // soap-bubble thin film
iridescenceIOR      = 1.30
```

### Cube material (YELA / ORANGE / SLUDGE / REDD / PURP + minis)
`MeshPhysicalMaterial`:
```
emissiveIntensity   = 0.06
roughness           = 0.04
transmission        = 0.62
thickness           = radius * 2.8
ior                 = 1.55
clearcoat           = 0.70
attenuationColor    = cfg.color
attenuationDistance = radius * 1.8
sheen               = 0.4                 // wet velvet micro-gloss
sheenColor          = cfg.color
sheenRoughness      = 0.3
anisotropy          = 0.6                 // brushed-glass streaks
iridescence         = 0.25
iridescenceIOR      = 1.25
```

### Vertex ripple (blobs only) — injected in vertex shader
```glsl
// u_wt = elapsed time, u_hw = hit-wobble strength (decays after each hit)
float _b = sin(pos.y*3.8 + u_wt*5.2)*0.22
         + cos(pos.x*3.2 + u_wt*4.7)*0.16
         + cos(pos.z*3.5 + u_wt*5.8)*0.12;     // breathing surface ripple
float _h = sin(length(pos)*8.0 - u_wt*18.0) * u_hw * 0.55;   // radial hit shockwave
position += normal * (_b + _h);
```
Geometry: sphere with **48×32 segments** (dense, so the ripple stays smooth, not faceted). Collision shape stays a fixed sphere — the ripple is visual only.

### Fresnel rim (blobs + cubes) — injected in fragment shader
```glsl
float fres = pow(1.0 - abs(dot(normalize(normal), normalize(viewDir))), 4.0); // 5.0 for cubes
albedo.rgb += rimColor * fres * 0.7;    // 0.5 for cubes; rimColor = lerp(cfg.color, white, 0.55)
```

### Scale animation (CPU, per frame)
```
breathe = amp * sin(t * freq)      // amp: 0.13 blob / 0.10 cube / 0.18 SPLITTA
sy  = 1 + breathe - hitWobble*0.4  // squash on Y
sxz = 1 - breathe*0.5 + hitWobble*0.6   // expand on XZ
hitWobble starts at 0.65 on hit, decays at 1.1/s
```

### Post-processing
```
UnrealBloomPass: strength 0.55, radius 0.5, threshold 0.9  (only hot highlights bloom)
ChromaticAberration: 0.0016 base, scales toward screen corners (R/B channel split)
OutputPass: ACESFilmic tonemap + sRGB (applied AFTER linear-space bloom)
```

### Environment / lighting
- IBL via `RoomEnvironment` baked through `PMREMGenerator` (needed for transmission + clearcoat).
- 1 directional light (intensity 1.3) + ambient 0.45.
- Tonemap exposure 1.15.

### Trails
- **SludgeRibbon:** `CatmullRomCurve3` through the last 12 trail points → `TubeGeometry` (radius 0.16, arched up in the middle via `sin(f*PI)*0.18`), `MeshPhysicalMaterial` transmission 0.45. Rebuilt ~8×/s.
- **SlimeTrail / Puddle / PoisonZone:** flat `CircleGeometry` decals, additive, fade over life.

---

## 1. Material → Godot `StandardMaterial3D` / `ShaderMaterial`

| Three.js param | Godot equivalent | Notes |
|---|---|---|
| `color` / `emissive` | `albedo_color` / `emission` + `emission_energy` | |
| `transmission` + `ior` | `refraction_enabled` + `refraction_scale`, or `transparency = TRANSPARENCY_ALPHA` + `backlight` | Godot has **screen-space refraction** — distorts what's behind the mesh. Strictly better than Three's transmission render pass. |
| `thickness` + `attenuationColor/Distance` | `subsurf_scatter_*` + custom thickness map | Real SSS, see §2 |
| `clearcoat` / `clearcoatRoughness` | `clearcoat` / `clearcoat_roughness` | direct |
| `sheen` / `sheenColor` | no built-in sheen → emulate in custom shader (Fresnel × velvet term) | |
| `anisotropy` | `anisotropy` + `anisotropy_flowmap` | direct |
| `iridescence` / `iridescenceIOR` | custom shader thin-film term (Godot has no built-in iridescence) | thin-film interference in a `shader_type spatial` |
| Fresnel rim inject | `rim` / `rim_tint`, OR `FRESNEL` in custom shader | `rim` is built-in but weaker; custom Fresnel matches the browser look |

**Recommendation:** author one `shader_type spatial` gel shader (`gel.gdshader`) with uniforms mirroring the table in §0, so a single material drives all enemies via per-instance uniforms (set through `MeshInstance3D.set_instance_shader_parameter`). This mirrors the Lab's DEFAULTS/OVERRIDES schema — keep the same parameter names.

### `gel.gdshader` skeleton
```glsl
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4  gel_color : source_color;
uniform float emissive_intensity = 0.10;
uniform float transmission       = 0.78;
uniform float ior                = 1.42;
uniform float clearcoat_amt      = 0.90;
uniform float iridescence        = 0.45;
uniform float irid_ior           = 1.30;
uniform vec4  attenuation_color : source_color;
uniform float attenuation_dist   = 0.77;
uniform vec4  rim_color : source_color;
uniform float wobble_time = 0.0;     // u_wt
uniform float hit_wobble  = 0.0;     // u_hw

void vertex() {
    vec3 p = VERTEX;
    float b = sin(p.y*3.8 + wobble_time*5.2)*0.22
            + cos(p.x*3.2 + wobble_time*4.7)*0.16
            + cos(p.z*3.5 + wobble_time*5.8)*0.12;
    float h = sin(length(p)*8.0 - wobble_time*18.0) * hit_wobble * 0.55;
    VERTEX += NORMAL * (b + h);
}

void fragment() {
    ALBEDO   = gel_color.rgb;
    METALLIC = 0.0;
    ROUGHNESS = 0.02;
    CLEARCOAT = clearcoat_amt;
    CLEARCOAT_ROUGHNESS = 0.04;
    EMISSION = gel_color.rgb * emissive_intensity;
    // screen-space refraction (gel transmission)
    // ... sample SCREEN_TEXTURE with normal-based offset, mix by transmission
    // thin-film iridescence: shift hue by view-angle interference (Fabien Sanglard / Belcour model)
    float fres = pow(1.0 - abs(dot(NORMAL, VIEW)), 4.0);
    EMISSION += rim_color.rgb * fres * 0.7;     // wet rim glow
}
```

Drive `wobble_time` / `hit_wobble` per instance from the enemy script each frame.

---

## 2. The landmark features (only worth doing in Godot)

These are the two features that make it read as **biological gel**, not painted glass. Prioritise them.

### 2a. True Subsurface Scattering
`StandardMaterial3D`:
```
subsurf_scatter_enabled = true
subsurf_scatter_strength = 0.8
subsurf_scatter_transmittance_enabled = true
subsurf_scatter_transmittance_color = cfg.color       // light bleeds through in this colour
subsurf_scatter_transmittance_depth = 0.4
```
Add a **thickness texture** (center thick → edges thin, radial gradient) so thin edges glow brightest — exactly the gummy-bear read. The browser's `emissiveIntensity` glow is a fake stand-in; replace it entirely with real SSS here.

### 2b. Tentacles — verlet chain dragging on the floor
This is THE target behaviour and cannot be done well in the browser. Per blob: **4–6 tentacles, 8 segments each.**

```gdscript
# tentacle.gd — attach one per tentacle root bone on the enemy
class_name Tentacle extends Node3D

const SEGMENTS := 8
const REST_LEN := 0.35
const DAMPING  := 0.86
const GRAVITY  := 9.8
const ITER     := 3          # constraint relaxation passes

var pos  : PackedVector3Array   # current
var prev : PackedVector3Array   # previous (verlet)

func _ready():
    pos = PackedVector3Array(); prev = PackedVector3Array()
    for i in SEGMENTS:
        var p := global_position + Vector3(0, -i * REST_LEN, 0)
        pos.append(p); prev.append(p)

func _physics_process(delta):
    var root := global_position
    # integrate
    for i in range(1, SEGMENTS):              # i=0 pinned to root
        var v := (pos[i] - prev[i]) * DAMPING
        prev[i] = pos[i]
        pos[i]  += v
        pos[i].y -= GRAVITY * delta * delta
    pos[0] = root                              # pin
    # constrain
    for _it in ITER:
        for i in range(SEGMENTS - 1):
            var a := pos[i]; var b := pos[i+1]
            var d := b - a
            var err := d.length() - REST_LEN
            var dir := d.normalized()
            if i > 0: pos[i]   += dir * err * 0.5
            pos[i+1] -= dir * err * 0.5
        for i in SEGMENTS:                      # floor collision → drag
            if pos[i].y < 0.0: pos[i].y = 0.0
    # drive a skeleton / SoftBody / drawn tube from pos[]
```

**Rendering the tentacle body:** either
- skin a `MeshInstance3D` via `Skeleton3D` with one bone per segment and `BoneAttachment3D`, or
- generate a `TubeTrail3D` / `ImmediateMesh` tube along `pos[]` each frame with the gel shader applied.

When the blob stops, tentacles **pile and drag**; when it moves fast they **stretch and snap back** — gravity + verlet gives this for free. Tune `DAMPING`/`GRAVITY`/`REST_LEN` for "heavy treacle" feel.

**Performance:** verlet for hero/boss enemies. For swarms (many GLOBBOs from SPLITTA), bake the tentacle motion to a **Vertex Animation Texture (VAT)** and play it on a GPU shader instead — no per-segment CPU cost.

---

## 3. GPU particles — dripping gel (`GPUParticles3D`)

Replaces the browser's interval-placed flat decals with real dripping droplets.

Per blob/sludge enemy, attach a `GPUParticles3D`:
```
emission shape  = SphereSurface (the enemy radius)
direction       = down-biased
gravity         = (0, -9.8, 0)
process material: ParticleProcessMaterial
  - collision_mode = COLLISION_RIGID   # droplets hit the floor
  - sub_emitter on collision → radial micro-splash ring
draw pass       = small stretched sphere (gel shader, transmission)
amount          = 64, lifetime 1.2
```
Result: visible droplets slide down the body, fall, **splat on the floor** and spread as concentric puddle rings. This is the "moist / dew" read. Thousands of particles at 60fps on mobile via Vulkan.

**Dew on the surface:** a static normal map of droplet bumps (`fract`-tiled hemispheres) on the gel material gives the glistening dew without particles; combine with the drip particles for motion.

---

## 4. Trails → `GPUParticles3D` trail / `TubeTrail3D`

- **SludgeRibbon** (currently a rebuilt TubeGeometry) → `TubeTrail3D` node parented to the enemy, gel shader, transmission 0.45. Built-in, GPU-driven, no per-frame rebuild.
- **SlimeTrail / Puddle / PoisonZone** flat decals → `Decal` nodes projected onto the floor (proper projection + fade via `albedo_mix`/modulate alpha), or a `GPUParticles3D` ribbon for the wet ground sheen.

---

## 5. Death FX → `SoftBody3D` + particles

- **SPLITTA** scale-squash split → `SoftBody3D` that actually **deforms and tears**: apply `apply_central_impulse` on hit, detach vertex groups into two child blobs.
- Death chunks (currently `MeshBasicMaterial` spheres) → `RigidBody3D` gel chunks with the gel shader + SSS, so they refract and bloom as they fly. Add a caustic ring `Decal` where they land.

---

## 6. Environment & post-processing → `WorldEnvironment` + Compositor

`WorldEnvironment`:
```
glow_enabled = true, glow_bloom ≈ 0.2, glow_hdr_threshold ≈ 0.9   # mirrors UnrealBloom threshold 0.9
ssao_enabled = true                # contact shadows on floor (gel won't occlude, floor will darken)
ssil_enabled = true                # enemies tint each other's gel
ssr_enabled  = true                # gel reflects in the arena floor
sdfgi_enabled = true               # coloured enemies cast real GI onto the floor
tonemap_mode = TONE_MAPPER_ACES, exposure ≈ 1.15
```
Use an HDRI sky (or keep the dark `0x0d0d1a` ambient) in `Environment.background`.

**Custom Compositor passes (Godot 4.3 `CompositorEffect`):**
- Chromatic aberration on gel silhouettes (port the browser shader in §0).
- Heat shimmer over poison zones (`screen_uv + sin(uv*20 + time*4)*0.008`, masked by the poison decal depth).
- Anisotropic bloom (elongate the glow upward in view space) for the "rising gel light" look.

---

## 7. Recommended task order

1. **`gel.gdshader`** matching §0/§1 params; verify one GLOBBO + one cube look like the browser reference screenshots. ← do first, it gates everything.
2. **`WorldEnvironment`** glow/SSR/SSAO/SDFGI (§6) — biggest single jump, near-free.
3. **True SSS + thickness map** (§2a) — the gummy-bear read.
4. **Verlet tentacles** (§2b) on one hero enemy — the landmark "alive" feature.
5. **GPU drip particles + dew normal map** (§3) — the "moist" read.
6. **`TubeTrail3D` / `Decal` trails** (§4).
7. **`SoftBody3D` death/split + RigidBody gel chunks** (§5).
8. **Compositor** chromatic aberration + heat shimmer (§6).
9. VAT-bake the tentacles for swarm enemies once the hero version is proven.

---

## 8. Parity checklist (port is "done" when…)

- [ ] A GLOBBO reads as a translucent gel sphere with wet Fresnel rim and dewy surface — matches `toko-drop` browser screenshots.
- [ ] A cube reads as candy-glass with thin-film iridescent sheen.
- [ ] Thin edges of every body **glow from within** (true SSS, not uniform emissive).
- [ ] At least one enemy has tentacles that **drag on the floor and stretch when it moves**.
- [ ] Sludge/blob enemies **drip droplets that splat** into spreading puddle rings.
- [ ] Floor shows coloured reflections + GI bleed from nearby enemies.
- [ ] Only the hottest highlights bloom (threshold parity with browser `0.9`), bodies keep their detail.
