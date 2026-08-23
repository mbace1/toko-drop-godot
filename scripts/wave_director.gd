## wave_director.gd
##
## Minimal wave loop, in the shape of main.js's spawnWave(): when every enemy
## from the current wave is dead, spawn a bigger one. Enemies land at
## 0.6 × half-arena-size in a cross pattern, matching the source comment
## ("spawns fresh enemies at 0.6 × HALF radius in a cross pattern"). Only two
## of the roster's ~40 types are ported so far (GLOBBO, YELA_CUBE) — see
## PORT_STATUS.md for the rest.
class_name WaveDirector
extends Node3D

signal wave_started(n: int)
signal wave_cleared(n: int)

var wave := 0
var half_x := 9.0
var half_z := 9.0
var target: Node3D
var enemies_root: Node3D
var enemies: Array[Enemy] = []

const CROSS := [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]

func start_wave() -> void:
	wave += 1
	var count := 3 + wave
	var r := 0.6 * minf(half_x, half_z)
	for i in count:
		var dir: Vector2 = CROSS[i % CROSS.size()].rotated(randf() * 0.6 - 0.3)
		var pos := dir * r

		var e: Enemy = YelaCube.new() if i % 3 == 2 else Globbo.new()
		enemies_root.add_child(e)
		e.position = Vector3(pos.x, 0.0, pos.y)
		e.half_x = half_x
		e.half_z = half_z
		e.target = target
		e.init()
		enemies.append(e)
	wave_started.emit(wave)

func update(delta: float) -> void:
	for i in range(enemies.size() - 1, -1, -1):
		var e := enemies[i]
		if not is_instance_valid(e) or not e.alive:
			enemies.remove_at(i)
			continue
		e.update(delta)
	if enemies.is_empty() and wave > 0:
		wave_cleared.emit(wave)

func clear() -> void:
	for e in enemies:
		if is_instance_valid(e):
			e.queue_free()
	enemies.clear()
	wave = 0
