class_name BuildingFacade
extends Node3D
## Shelf-stock building wrapper (docs/ASSET_PIPELINE.md §11, Tier C): maps a
## generated building's named/proxy material slots (WALL / TRIM / GLASS / ROOF /
## DETAIL / ACC*) onto the shared ambientCG facade sets, so every building in
## the library reuses the same textures (one copy in game/assets/materials/)
## and the GLBs stay geometry-only and tiny. Per-building variety comes from
## the exported wall set + tints here, not from duplicated textures.
##
## The window GLASS is tinted/reflective and self-lit at night: this node
## drives its own emission from the shared day/night clock
## (StreetlightSwitch.night_level), so it does NOT depend on a sibling
## NightWindowEmission or on _ready ordering (the facade is applied here, on
## the root, AFTER child _ready would have run).

const TRIM_SET := "res://assets/materials/concrete_sidewalk_01"
## Buildify proxy material name -> canonical slot.
const PROXY_TO_SLOT := {
	"proxy_mat_yellow": "WALL",
	"proxy_mat_stone": "TRIM",
	"proxy_mat_general_reflective": "GLASS",
	"proxy_mat_grey": "DETAIL",
	"proxy_mat_blue": "ACC1",
	"proxy_mat_orange": "ACC2",
	"proxy_mat_roof": "ROOF",
}
## Solid-colour slots: name -> [Color, roughness]. (Houses add ROOF2/DOOR.)
const SOLID_SLOTS := {
	"ROOF": [Color(0.16, 0.15, 0.14), 0.95],
	"ROOF2": [Color(0.42, 0.20, 0.15), 0.9],  # terracotta pitched roof
	"DOOR": [Color(0.32, 0.2, 0.12), 0.6],  # wood front door
	"DETAIL": [Color(0.4, 0.4, 0.38), 0.7],
	"ACC1": [Color(0.2, 0.4, 0.5), 0.6],
	"ACC2": [Color(0.7, 0.4, 0.3), 0.6],
}

## Facade material folder for the walls (a PbrMaterial.from_set dir).
@export_dir var wall_set: String = "res://assets/materials/facade_stucco_01"

## Albedo tint multiplied over the wall texture (per-building colour).
@export var wall_tint: Color = Color(1, 1, 1)

## Window glass base colour (kept dark; metallic + low roughness for reflection).
@export var glass_color: Color = Color(0.1, 0.13, 0.18)

## Peak window-glow energy at full night.
@export var window_energy: float = 1.6

var _glass_materials: Array[StandardMaterial3D] = []


func _ready() -> void:
	for mesh in find_children("*", "MeshInstance3D", true, false):
		var mi := mesh as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s)
			var slot := _slot_key(src.resource_name if src else "")
			mi.set_surface_override_material(s, _material_for(slot))


func _process(_delta: float) -> void:
	# Window glow rides the shared day/night clock: dark by day, lit at night.
	var energy := StreetlightSwitch.lamp_energy(StreetlightSwitch.night_level, window_energy)
	for g in _glass_materials:
		g.emission_energy_multiplier = energy


## Normalise a raw material name to a canonical slot, tolerating ".NNN"
## duplicate suffixes and mapping the Buildify proxy names the generator
## leaves through.
func _slot_key(raw: String) -> String:
	var base := raw.split(".")[0]
	return PROXY_TO_SLOT.get(base, base)


func _material_for(slot: String) -> Material:
	if slot == "WALL":
		var w := PbrMaterial.from_set(wall_set, true, 0.32)
		w.albedo_color = wall_tint
		return w
	if slot == "TRIM":
		return PbrMaterial.from_set(TRIM_SET, true, 0.3)
	if slot == "GLASS":
		var g := StandardMaterial3D.new()
		g.albedo_color = glass_color
		g.metallic = 0.4
		g.roughness = 0.12
		g.emission_enabled = true
		g.emission = Color(1.0, 0.82, 0.55)
		g.emission_energy_multiplier = 0.0  # driven in _process from night_level
		_glass_materials.append(g)
		return g
	if SOLID_SLOTS.has(slot):
		return _solid(SOLID_SLOTS[slot][0], SOLID_SLOTS[slot][1])
	return _solid(Color(0.85, 0.85, 0.82), 0.7)


func _solid(color: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	return m
