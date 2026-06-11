#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector2i.hpp>

namespace godot {

// M3 world streaming tile selector. Given the camera position and velocity (on
// the XZ ground plane), returns the world tiles that should be resident —
// prioritized by travel direction — and which resident tiles to unload, with
// load/unload hysteresis to stop boundary tiles thrashing. The selection math
// is the pure, unit-tested worldcore_streaming core; this just bridges it to
// GDScript so the district streamer can drop its per-frame GDScript distance
// loops for native ones. Absent the native module, GDScript keeps its own path.
class TileStreamer : public RefCounted {
    GDCLASS(TileStreamer, RefCounted)

    double tile_size = 256.0;
    double load_radius = 768.0;
    double unload_radius = 1024.0;
    double direction_bias = 0.5;

protected:
    static void _bind_methods();

public:
    void set_tile_size(double p_v);
    double get_tile_size() const;
    void set_load_radius(double p_v);
    double get_load_radius() const;
    void set_unload_radius(double p_v);
    double get_unload_radius() const;
    void set_direction_bias(double p_v);
    double get_direction_bias() const;

    // World XZ -> integer tile coordinate.
    Vector2i world_to_tile(const Vector2 &p_world_xz) const;

    // Tiles that should be resident, in load-priority order (Array of Vector2i).
    Array desired_tiles(const Vector2 &p_cam_xz, const Vector2 &p_velocity_xz) const;

    // Subset of `p_resident` (Array of Vector2i) now beyond the unload radius.
    Array tiles_to_unload(const Array &p_resident, const Vector2 &p_cam_xz) const;
};

} // namespace godot
