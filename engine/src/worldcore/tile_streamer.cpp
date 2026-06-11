#include "tile_streamer.h"

#include <godot_cpp/core/class_db.hpp>

#include "tile_streamer_core.h"

using namespace godot;
using worldcore_streaming::TileCoord;

void TileStreamer::_bind_methods() {
    ClassDB::bind_method(D_METHOD("set_tile_size", "v"), &TileStreamer::set_tile_size);
    ClassDB::bind_method(D_METHOD("get_tile_size"), &TileStreamer::get_tile_size);
    ClassDB::bind_method(D_METHOD("set_load_radius", "v"), &TileStreamer::set_load_radius);
    ClassDB::bind_method(D_METHOD("get_load_radius"), &TileStreamer::get_load_radius);
    ClassDB::bind_method(D_METHOD("set_unload_radius", "v"), &TileStreamer::set_unload_radius);
    ClassDB::bind_method(D_METHOD("get_unload_radius"), &TileStreamer::get_unload_radius);
    ClassDB::bind_method(D_METHOD("set_direction_bias", "v"), &TileStreamer::set_direction_bias);
    ClassDB::bind_method(D_METHOD("get_direction_bias"), &TileStreamer::get_direction_bias);

    ClassDB::bind_method(D_METHOD("world_to_tile", "world_xz"), &TileStreamer::world_to_tile);
    ClassDB::bind_method(
            D_METHOD("desired_tiles", "cam_xz", "velocity_xz"), &TileStreamer::desired_tiles);
    ClassDB::bind_method(
            D_METHOD("tiles_to_unload", "resident", "cam_xz"), &TileStreamer::tiles_to_unload);

    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "tile_size"), "set_tile_size", "get_tile_size");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "load_radius"), "set_load_radius", "get_load_radius");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "unload_radius"), "set_unload_radius",
            "get_unload_radius");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "direction_bias"), "set_direction_bias",
            "get_direction_bias");
}

void TileStreamer::set_tile_size(double p_v) {
    tile_size = p_v > 0.0 ? p_v : tile_size;
}

double TileStreamer::get_tile_size() const {
    return tile_size;
}

void TileStreamer::set_load_radius(double p_v) {
    load_radius = p_v;
}

double TileStreamer::get_load_radius() const {
    return load_radius;
}

void TileStreamer::set_unload_radius(double p_v) {
    unload_radius = p_v;
}

double TileStreamer::get_unload_radius() const {
    return unload_radius;
}

void TileStreamer::set_direction_bias(double p_v) {
    direction_bias = p_v;
}

double TileStreamer::get_direction_bias() const {
    return direction_bias;
}

Vector2i TileStreamer::world_to_tile(const Vector2 &p_world_xz) const {
    const TileCoord t = worldcore_streaming::world_to_tile(p_world_xz.x, p_world_xz.y, tile_size);
    return Vector2i(t.x, t.z);
}

Array TileStreamer::desired_tiles(const Vector2 &p_cam_xz, const Vector2 &p_velocity_xz) const {
    const std::vector<TileCoord> tiles = worldcore_streaming::desired_tiles(p_cam_xz.x, p_cam_xz.y,
            p_velocity_xz.x, p_velocity_xz.y, tile_size, load_radius, direction_bias);
    Array out;
    for (const TileCoord &t : tiles) {
        out.push_back(Vector2i(t.x, t.z));
    }
    return out;
}

Array TileStreamer::tiles_to_unload(const Array &p_resident, const Vector2 &p_cam_xz) const {
    std::vector<TileCoord> resident;
    for (int i = 0; i < p_resident.size(); ++i) {
        const Vector2i v = p_resident[i];
        resident.push_back(TileCoord{v.x, v.y});
    }
    const std::vector<TileCoord> drop = worldcore_streaming::tiles_to_unload(
            resident, p_cam_xz.x, p_cam_xz.y, tile_size, unload_radius);
    Array out;
    for (const TileCoord &t : drop) {
        out.push_back(Vector2i(t.x, t.z));
    }
    return out;
}
