class_name OceanMeshBuilder
extends RefCounted
## Tiered ocean grid geometry (pure, unit-tested): a fine vertex grid where
## Gerstner displacement is visible, and big flat far-field cells out to the
## horizon where it isn't. A 12 km uniform plane spent ~90% of its triangles
## on far water whose vertex displacement is sub-pixel (and aliased — every
## wavelength in the table is shorter than the old 62.5 m vertex spacing);
## per-pixel normals do all the visual work out there.
##
## Crack-free by construction: the fine square is snapped onto far-grid lines
## so coarse cells are either fully inside it (skipped) or fully outside (no
## overlap), and the shader (plus Ocean.wave_height_at) fades displacement to
## zero at the fine-square edge, so the T-junctions where one coarse cell
## meets several fine cells join coplanar, undisplaced vertices.


## Vertex/index arrays for the tiered grid, centred on the mesh-local origin.
## `size_m` is the full outer edge, `fine_half_m` the requested half-extent of
## the fine square (clamped to the plane, snapped up to the far grid),
## `fine_cells` the fine resolution per side, `far_cell_m` the approximate
## coarse cell edge. Returns {"vertices": PackedVector3Array, "normals":
## PackedVector3Array, "indices": PackedInt32Array, "fine_half": float} —
## `fine_half` is the snapped extent the displacement fade must end at.
static func build(
	size_m: float, fine_half_m: float, fine_cells: int, far_cell_m: float
) -> Dictionary:
	var half := maxf(size_m, 1.0) * 0.5
	var cells := maxi(fine_cells, 1)
	var fine_half := clampf(fine_half_m, 1.0, half)
	var far_n := 0
	var far_step := 0.0
	if fine_half < half:
		far_n = maxi(ceili(2.0 * half / maxf(far_cell_m, 1.0)), 2)
		far_step = 2.0 * half / float(far_n)
		# Snap the fine square up to the nearest far-grid line so coarse cells
		# never straddle (and z-fight with) the fine region.
		fine_half = minf(far_step * ceilf(fine_half / far_step - 0.000001), half)

	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	_append_fine_grid(verts, norms, idx, fine_half, cells)
	if fine_half < half:
		_append_far_field(verts, norms, idx, half, fine_half, far_n, far_step)
	return {"vertices": verts, "normals": norms, "indices": idx, "fine_half": fine_half}


## Chebyshev (square-ring) displacement falloff used by both the GPU vertex
## stage and CPU buoyancy: 1 inside fade_start, 0 at/beyond fade_end. Mirrors
## the falloff in ocean.gdshader — edit both together.
static func displacement_falloff(rel_xz: Vector2, fade_start: float, fade_end: float) -> float:
	var cheb := maxf(absf(rel_xz.x), absf(rel_xz.y))
	if fade_end <= fade_start:
		return 1.0 if cheb < fade_end else 0.0
	return 1.0 - smoothstep(fade_start, fade_end, cheb)


## Shared-vertex (cells+1)^2 grid over the fine square.
static func _append_fine_grid(
	verts: PackedVector3Array,
	norms: PackedVector3Array,
	idx: PackedInt32Array,
	fine_half: float,
	cells: int
) -> void:
	var step := fine_half * 2.0 / float(cells)
	for r in cells + 1:
		for c in cells + 1:
			verts.append(Vector3(-fine_half + c * step, 0.0, -fine_half + r * step))
			norms.append(Vector3.UP)
	var stride := cells + 1
	for r in cells:
		for c in cells:
			var a := r * stride + c
			idx.append_array([a, a + stride, a + 1, a + 1, a + stride, a + stride + 1])


## Coarse quads tiling the frame between the fine square and the plane edge.
## Vertices are per-quad (unshared); all of them sit at or beyond the
## displacement fade-out, so seams stay coplanar and watertight.
static func _append_far_field(
	verts: PackedVector3Array,
	norms: PackedVector3Array,
	idx: PackedInt32Array,
	half: float,
	fine_half: float,
	far_n: int,
	far_step: float
) -> void:
	for r in far_n:
		for c in far_n:
			var x0 := -half + c * far_step
			var z0 := -half + r * far_step
			var x1 := x0 + far_step
			var z1 := z0 + far_step
			# Skip cells inside the fine square (already meshed finely). The
			# snap guarantees cells are fully in or fully out; the epsilon
			# absorbs float error on the boundary.
			if (
				x0 >= -fine_half - 0.001
				and x1 <= fine_half + 0.001
				and z0 >= -fine_half - 0.001
				and z1 <= fine_half + 0.001
			):
				continue
			var base := verts.size()
			(
				verts
				. append_array(
					PackedVector3Array(
						[
							Vector3(x0, 0.0, z0),
							Vector3(x1, 0.0, z0),
							Vector3(x0, 0.0, z1),
							Vector3(x1, 0.0, z1),
						]
					)
				)
			)
			norms.append_array(PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP]))
			idx.append_array([base, base + 2, base + 1, base + 1, base + 2, base + 3])
