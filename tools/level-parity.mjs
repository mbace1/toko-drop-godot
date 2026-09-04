#!/usr/bin/env node
// level-parity.mjs — THE CROSS-BUILD GATE. One authored level, played by
// both builds, must produce the same spawns: the same bodies, in the same
// order, at the same second, in the same place. Q-032.
//
// Both sides log first-sighting lines in one format:
//   SPAWN <i> <TYPE> t=<s> x=<x> z=<z>
// - this build: tools/trace.gd with `level:<id>` (headless, fixed timestep)
// - the browser: scripts/level-smoke.sh writes $LEVEL_DIR/seen-<id>.txt
//
//   node tools/level-parity.mjs <id> <browser-seen-file>
//   GODOT=... node tools/level-parity.mjs first-light /c/tmp/toko-level/seen-first-light.txt
//
// Tolerances are the ones each side's own gate already uses against the
// authored file: 0.15 s (a body is first seen up to two frames into its
// life) and 1.0 world unit (two frames of pounce). Tighter than that and
// the gate would be measuring frame phase, not the level.

import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';

const [id, seenFile] = process.argv.slice(2);
if (!id || !seenFile) { console.error('usage: level-parity.mjs <level-id> <browser-seen-file>'); process.exit(2); }
const GODOT = process.env.GODOT;
if (!GODOT) { console.error('set GODOT to the Godot console binary'); process.exit(2); }

const parse = (text, label) => {
  const out = [];
  for (const line of text.split(/\r?\n/)) {
    const m = line.match(/SPAWN (\d+) ([A-Z_]+) t=([-\d.]+) x=([-\d.]+) z=([-\d.]+)/);
    if (m) out.push({ i: +m[1], type: m[2], t: +m[3], x: +m[4], z: +m[5] });
  }
  if (!out.length) { console.error(`✘ no SPAWN lines from ${label}`); process.exit(1); }
  return out;
};

const browser = parse(readFileSync(seenFile, 'utf8'), 'the browser seen file');
// Enough frames to spend the whole timeline plus the clear beat: the level's
// duration is in the synced file, so read it rather than guess a number
// (a first cut used 900 frames — 15 s — and saw 7 of 15 bodies, all correct).
const level = JSON.parse(readFileSync(new URL(`../levels/${id}.json`, import.meta.url), 'utf8'));
const frames = Math.ceil((level.duration + 8) * 60);
const r = spawnSync(GODOT, ['--headless', '--fixed-fps', '60', '--script', 'tools/trace.gd', '--', `level:${id}`, String(frames)],
  { encoding: 'utf8', maxBuffer: 64 << 20 });
const godot = parse((r.stdout || '') + (r.stderr || ''), 'the Godot trace');

let checks = 0, fails = 0;
const ok = (name, cond) => { checks++; if (!cond) { fails++; console.error(`✘ ${name}`); } };

ok(`same spawn count (browser ${browser.length}, godot ${godot.length})`, browser.length === godot.length);
const n = Math.min(browser.length, godot.length);
for (let k = 0; k < n; k++) {
  const b = browser[k], g = godot[k];
  ok(`#${k} same type (${b.type} vs ${g.type})`, b.type === g.type);
  ok(`#${k} ${b.type} same second (${b.t.toFixed(2)} vs ${g.t.toFixed(2)})`, Math.abs(b.t - g.t) <= 0.15);
  ok(`#${k} ${b.type} same place ((${b.x.toFixed(2)},${b.z.toFixed(2)}) vs (${g.x.toFixed(2)},${g.z.toFixed(2)}))`,
     Math.abs(b.x - g.x) <= 1.0 && Math.abs(b.z - g.z) <= 1.0);
}
console.log(`${checks - fails}/${checks} parity checks passed for '${id}'`);
if (fails) { console.error(`✘ ${fails} FAILED — the two builds do not play this level the same way`); process.exit(1); }
console.log('✔ both builds play the level identically');
