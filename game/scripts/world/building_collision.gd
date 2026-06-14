class_name BuildingCollision
extends RefCounted
## Solid per-building collision for a district. Each footprint is projected and
## extruded to its height as a convex prism, gathered under one StaticBody3D on
## the world layer. This replaces a single welded trimesh, whose concave shell
## has no interior, so a fast sprint-jump could carry the capsule centre through
## a wall and then fall out the bottom; a convex volume has an inside the solver
## ejects an overlapping capsule from. The rendered buildings mesh is untouched.

## Collision layer the skyline sits on. Must match the layer the crowd nav-bake
## raycasts (ground_mask) so building footprints stay blocked for NPC spawns,
## and the layer gameplay raycasts expect.
const WORLD_LAYER := 1


## Build the collider from the same building dictionaries and projection the
## visual mesh used, so the solid volumes register with the rendered skyline.
## Returns null when no building yields a valid prism.
static func build(buildings: Array, proj: GeoProjection) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Buildings_col"
	body.collision_layer = WORLD_LAYER
	var made := 0
	for b in buildings:
		var height := float(b.get("height_m", 0.0))
		if height <= 0.0:
			continue
		var ring := PackedVector2Array()
		for pair in b.get("footprint", []):
			ring.append(proj.to_local_2d(pair[0], pair[1]))
		# Same cleanup the visual extrude runs, so a building gets a collider iff
		# it got geometry, and no degenerate ring reaches the hull builder.
		ring = CityBuilder.clean_ring(ring)
		if ring.size() < 3:
			continue
		var pts := PackedVector3Array()
		for p in ring:
			pts.append(Vector3(p.x, 0.0, p.y))
			pts.append(Vector3(p.x, height, p.y))
		var hull := ConvexPolygonShape3D.new()
		hull.points = pts
		var cs := CollisionShape3D.new()
		cs.shape = hull
		body.add_child(cs)
		made += 1
	if made == 0:
		body.free()
		return null
	return body
