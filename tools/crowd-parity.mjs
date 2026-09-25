#!/usr/bin/env node
// crowd-parity.mjs — THE CROWD, BOTH BUILDS. Q-043.
//
// Runs upstream's own js/crowd.js (read from the sibling clone's DEPLOYED
// ref, like tools/sync-levels.sh) and this build's scripts/crowd.gd (through
// tests/crowd_check.gd) on the same scenes, and compares every body:
//
//   resolve  fourteen bodies, one call of the hard RESOLVE alone. The scene is
//            built FROM the port's printed start (upstream's LCG multiplies in
//            doubles and drops bits past 2^53, so regenerating it would be a
//            different scene). One call: the builds must agree to float32.
//   fan      nine bodies from one door pursuing a point for 360 frames with
//   pile     the v245 terms on (fan) and off (pile) — crowd-check.mjs's scene.
//            Checked twice. EXACTLY, with upstream's positions stored as
//            float32 the way a Node3D stores them here: every body within
//            1e-6 (measured: 5e-16). And at upstream's own float64, where six
//            seconds of a pile is chaotic enough that one fan body ends 0.85
//            away (measured) — so there the SHAPE is compared: nearest-neighbour
//            spacing, pack radius and coverage within 5% / 5% / 10°.
//
//   GODOT=… UPSTREAM=/path/to/Suds-Jack node tools/crowd-parity.mjs
import { spawnSync } from 'node:child_process';
import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

const GODOT = process.env.GODOT;
if (!GODOT) { console.error('set GODOT to the Godot console binary'); process.exit(2); }
const UPSTREAM = process.env.UPSTREAM || `${process.env.HOME}/src/Suds-Jack`;
const REF = process.env.REF || 'origin/gh-pages';

const src = spawnSync('git', ['-C', UPSTREAM, 'show', `${REF}:toko-drop/js/crowd.js`], { encoding: 'utf8' });
if (src.status !== 0) { console.error(`✘ could not read toko-drop/js/crowd.js at ${REF} in ${UPSTREAM}`); process.exit(2); }
const dir = mkdtempSync(join(tmpdir(), 'crowd-parity-'));
writeFileSync(join(dir, 'crowd.mjs'), src.stdout);
const { resolveCrowd, CROWD_DEFAULTS } = await import(pathToFileURL(join(dir, 'crowd.mjs')).href);

const r = spawnSync(GODOT, ['--headless', '--path', '.', '--script', 'tests/crowd_check.gd'], { encoding: 'utf8', maxBuffer: 16 << 20 });
const out = (r.stdout || '') + (r.stderr || '');
if (!/CROWD: PASS/.test(out)) { console.error('✘ the port\'s own crowd check did not pass:\n' + out.split('\n').filter(l => /✘|CROWD:/.test(l)).join('\n')); process.exit(1); }
const godot = {}, init = [];
for (const line of out.split(/\r?\n/)) {
  let m = line.match(/^CROWD (\w+) (\d+) ([-\d.]+) ([-\d.]+)$/);
  if (m) (godot[m[1]] ??= [])[+m[2]] = { x: +m[3], z: +m[4] };
  m = line.match(/^CROWDINIT resolve (\d+) ([-\d.]+) ([-\d.]+) ([-\d.]+) ([01]) (\S+)$/);
  if (m) init[+m[1]] = { position: { x: +m[2], z: +m[3] }, radius: +m[4], alive: m[5] === '1', _affix: m[6] === '-' ? null : m[6] };
}

// crowd-check.mjs's scene, verbatim
const HX = 11, HZ = 18, DT = 1 / 60;
// a position that stores float32, as Godot's Vector3 does
const f32pos = (x, z) => { let _x = Math.fround(x), _z = Math.fround(z);
  return { get x() { return _x; }, set x(v) { _x = Math.fround(v); }, get z() { return _z; }, set z(v) { _z = Math.fround(v); } }; };
function bodies(n, f32 = false, spread = 0.6, z0 = 7, r = 0.45) {
  const o = [];
  for (let i = 0; i < n; i++) { const x = ((i % 3) - 1) * spread, z = z0 + Math.floor(i / 3) * 0.9; o.push({ position: f32 ? f32pos(x, z) : { x, z }, radius: r, alive: true }); }
  return o;
}
function pursue(bs, target, speed, stop = 0.05, dt = DT) {
  for (const b of bs) {
    const dx = target.x - b.position.x, dz = target.z - b.position.z, d = Math.sqrt(dx * dx + dz * dz);
    if (d > stop) { b.position.x += dx / d * speed * dt; b.position.z += dz / d * speed * dt; b._velX = dx / d * speed; b._velZ = dz / d * speed; } else { b._velX = 0; b._velZ = 0; }
    b.position.x = Math.max(-HX + b.radius, Math.min(HX - b.radius, b.position.x)); b.position.z = Math.max(-HZ + b.radius, Math.min(HZ - b.radius, b.position.z));
    let cx = 0, cz = 0, n = 0;
    for (const o of bs) { if (o === b) continue; const ox = o.position.x - b.position.x, oz = o.position.z - b.position.z; if (ox * ox + oz * oz > 16) continue; cx += ox; cz += oz; n++; }
    if (n) { const gl = Math.sqrt(cx * cx + cz * cz) || 1; b.position.x += (cx / gl) * 0.5 * dt; b.position.z += (cz / gl) * 0.5 * dt; }
  }
}
const run = (cfg, f32 = false) => { const bs = bodies(9, f32); for (let f = 0; f < 360; f++) { pursue(bs, { x: 0, z: 0 }, 3.0); resolveCrowd(bs, DT, HX, HZ, { x: 0, z: 0 }, cfg); } return bs.map(b => ({ x: b.position.x, z: b.position.z })); };
const nn = ps => ps.reduce((s, a) => s + Math.min(...ps.filter(b => b !== a).map(b => Math.hypot(a.x - b.x, a.z - b.z))), 0) / ps.length;
const pile = ps => Math.max(...ps.map(p => Math.hypot(p.x, p.z)));
const cov = ps => { const a = ps.map(p => Math.atan2(p.z, p.x)).sort((p, q) => p - q); let g = 0; for (let i = 0; i < a.length; i++) g = Math.max(g, (i + 1 < a.length ? a[i + 1] : a[0] + Math.PI * 2) - a[i]); return (Math.PI * 2 - g) * 180 / Math.PI; };

let checks = 0, fails = 0;
const ok = (name, cond, info = '') => { checks++; if (!cond) { fails++; console.error(`✘ ${name} ${info}`); } else console.log(`  ok   ${name} ${info}`); };

// resolve — one call, built from the port's own start
ok('the resolve scene came across (14 bodies)', init.filter(Boolean).length === 14 && (godot.resolve?.length === 14));
resolveCrowd(init, DT, HX, HZ, null, { pad: 0.25, comfort: 1, push: 0, slide: 0, passes: 2 });
const worst = Math.max(...init.map((b, i) => Math.hypot(b.position.x - godot.resolve[i].x, b.position.z - godot.resolve[i].z)));
ok('the hard RESOLVE: every body where upstream puts it (to float32)', worst < 2e-5, `(worst ${worst.toExponential(1)})`);

for (const [scene, cfg] of [['fan', CROWD_DEFAULTS], ['pile', { pad: 0.25, comfort: 1, push: 0, slide: 0, passes: 2 }]]) {
  const up = run(cfg), gd = godot[scene];
  ok(`${scene}: nine bodies`, gd?.length === 9);
  const u32 = run(cfg, true);
  const far = Math.max(...u32.map((p, i) => Math.hypot(p.x - gd[i].x, p.z - gd[i].z)));
  ok(`${scene}: every body where upstream's crowd puts it, in float32, after six seconds`, far <= 1e-6, `(worst ${far.toExponential(1)})`);
  ok(`${scene}: the same spacing (nn ${nn(up).toFixed(2)} vs ${nn(gd).toFixed(2)})`, Math.abs(nn(up) - nn(gd)) <= 0.05 * nn(up));
  ok(`${scene}: the same pack radius (${pile(up).toFixed(2)} vs ${pile(gd).toFixed(2)})`, Math.abs(pile(up) - pile(gd)) <= 0.05 * pile(up));
  ok(`${scene}: the same coverage (${cov(up).toFixed(0)}° vs ${cov(gd).toFixed(0)}°)`, Math.abs(cov(up) - cov(gd)) <= 10);
}
console.log(`${checks - fails}/${checks} crowd parity checks`);
if (fails) { console.error(`✘ ${fails} FAILED — the two crowds do not behave the same`); process.exit(1); }
console.log('✔ both builds space the swarm the same way');
