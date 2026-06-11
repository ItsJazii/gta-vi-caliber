class_name TerrainModel
extends RefCounted
## Pure, scene-free procedural terrain — the heightfield the open world stands on.
## Height is a deterministic global function of world (x, z), so any two chunks
## that meet share their edge vertices exactly and the surface is seamless with
## no stitching. A separate Terrain node turns chunk arrays into MeshInstance3D +
## collider tiles around the camera. All maths is static and headless, covered by
## tests/unit/test_terrain_model.gd.
##
## Octave layout (metres): broad rolling hills + mid ridges + fine detail, summed
## as value-noise FBM. Tune AMPLITUDE/BASE_FREQ for a flatter or more dramatic
## landscape; the world stays continuous regardless.

## Peak height contribution of the hills, in metres.
const AMPLITUDE: float = 46.0

## Spatial frequency of the largest octave (1 / metres). Smaller = broader hills.
## ~0.005 → a ridge roughly every 100–200 m, so hills read at human/driving scale.
const BASE_FREQ: float = 0.0052

## Octaves summed for the heightfield.
const OCTAVES: int = 5

## Per-octave frequency and amplitude falloff.
const LACUNARITY: float = 2.03
const GAIN: float = 0.5

## A gentle bowl so the origin/spawn area trends toward flatter, lower ground.
const VALLEY_RADIUS: float = 240.0
const VALLEY_DEPTH: float = 10.0


## Terrain height in metres at world (x, z) for a given seed.
static func height_at(x: float, z: float, terrain_seed: int = 1337) -> float:
	var h := _fbm(x * BASE_FREQ, z * BASE_FREQ, terrain_seed) * AMPLITUDE
	# Ridged emphasis on the mid band gives believable hill crests.
	var d := sqrt(x * x + z * z)
	var valley := -VALLEY_DEPTH * exp(-(d * d) / (VALLEY_RADIUS * VALLEY_RADIUS))
	return h + valley


## Surface normal at world (x, z), via central differences on the heightfield.
static func normal_at(x: float, z: float, terrain_seed: int = 1337) -> Vector3:
	var e := 1.0
	var hl := height_at(x - e, z, terrain_seed)
	var hr := height_at(x + e, z, terrain_seed)
	var hd := height_at(x, z - e, terrain_seed)
	var hu := height_at(x, z + e, terrain_seed)
	return Vector3(hl - hr, 2.0 * e, hd - hu).normalized()


## Mesh arrays for one square chunk whose corner is world (ox, oz), spanning
## `span` metres with `res` subdivisions per side. Returns
## {vertices, normals, indices, uvs} ready for ArrayMesh.add_surface_from_arrays.
## Because every vertex height comes from the global height_at, chunks tile
## seamlessly: a shared edge is sampled identically from both sides.
static func chunk_arrays(
	ox: float, oz: float, span: float, res: int, terrain_seed: int = 1337
) -> Dictionary:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var step := span / float(res)

	for j in range(res + 1):
		for i in range(res + 1):
			var wx := ox + float(i) * step
			var wz := oz + float(j) * step
			verts.append(Vector3(float(i) * step, height_at(wx, wz, terrain_seed), float(j) * step))
			norms.append(normal_at(wx, wz, terrain_seed))
			uvs.append(Vector2(float(i) / float(res), float(j) / float(res)))

	var stride := res + 1
	for j in range(res):
		for i in range(res):
			var a := j * stride + i
			var b := a + 1
			var c := a + stride
			var d := c + 1
			idx.append(a)
			idx.append(c)
			idx.append(b)
			idx.append(b)
			idx.append(c)
			idx.append(d)

	return {"vertices": verts, "normals": norms, "uvs": uvs, "indices": idx}


## Slope at (x, z) as 0 (flat) .. 1 (vertical), handy for blending rock onto
## steep faces or refusing to spawn props on cliffs.
static func slope_at(x: float, z: float, terrain_seed: int = 1337) -> float:
	return clampf(1.0 - normal_at(x, z, terrain_seed).y, 0.0, 1.0)


# --- value-noise FBM ---------------------------------------------------------


## Deterministic lattice hash → [0, 1).
static func _hash(ix: int, iz: int, terrain_seed: int) -> float:
	var h: int = (ix * 73856093) ^ (iz * 19349663) ^ (terrain_seed * 83492791)
	h = h & 0x7FFFFFFF
	h = h ^ (h >> 13)
	h = (h * 1274126177) & 0x7FFFFFFF
	return float(h) / float(0x7FFFFFFF)


## Bilinearly-interpolated value noise with a smoothstep fade.
static func _value_noise(x: float, z: float, terrain_seed: int) -> float:
	var ix := int(floor(x))
	var iz := int(floor(z))
	var fx := x - float(ix)
	var fz := z - float(iz)
	var ux := fx * fx * (3.0 - 2.0 * fx)
	var uz := fz * fz * (3.0 - 2.0 * fz)
	var a := _hash(ix, iz, terrain_seed)
	var b := _hash(ix + 1, iz, terrain_seed)
	var c := _hash(ix, iz + 1, terrain_seed)
	var d := _hash(ix + 1, iz + 1, terrain_seed)
	return lerpf(lerpf(a, b, ux), lerpf(c, d, ux), uz)


## Fractal sum of value-noise octaves, returned in roughly [-1, 1].
static func _fbm(x: float, z: float, terrain_seed: int) -> float:
	var total := 0.0
	var amp := 1.0
	var freq := 1.0
	var norm := 0.0
	for o in range(OCTAVES):
		total += (_value_noise(x * freq, z * freq, terrain_seed + o) * 2.0 - 1.0) * amp
		norm += amp
		amp *= GAIN
		freq *= LACUNARITY
	return total / norm
