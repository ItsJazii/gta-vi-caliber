#pragma once

// Pure, runtime-free streaming math for the M3 world tile streamer. Header-only
// and free of any godot-cpp Variant types so it unit-tests in the plain-C++
// harness (engine/tests/test_worldcore.cpp) without a running engine — same
// pattern as native_bench/bench_kernels.h. The GDExtension TileStreamer class
// wraps these and exposes them to GDScript.
//
// The job: given the camera position and velocity, decide which world tiles
// should be resident (prioritized by travel direction so you stream what you're
// driving toward first) and which resident tiles to unload — with load/unload
// hysteresis so tiles near the boundary don't thrash in and out every frame.

#include <algorithm>
#include <cmath>
#include <vector>

namespace worldcore_streaming {

struct TileCoord {
    int x;
    int z;
    bool operator==(const TileCoord &o) const { return x == o.x && z == o.z; }
};

// World position -> the integer coordinate of the tile that owns it.
inline TileCoord world_to_tile(double wx, double wz, double tile_size) {
    return TileCoord{
        static_cast<int>(std::floor(wx / tile_size)),
        static_cast<int>(std::floor(wz / tile_size)),
    };
}

// World-space center of a tile.
inline void tile_center(const TileCoord &t, double tile_size, double &cx, double &cz) {
    cx = (static_cast<double>(t.x) + 0.5) * tile_size;
    cz = (static_cast<double>(t.z) + 0.5) * tile_size;
}

// Tiles whose center is within `load_radius` of the camera, returned in load
// priority order (load_first = front). Priority = distance, minus a velocity
// term so tiles ahead along the travel vector are pulled earlier; `bias` in
// [0,1] scales how strongly direction reorders distance. With zero speed it is
// pure nearest-first.
inline std::vector<TileCoord> desired_tiles(
        double cam_x, double cam_z, double vel_x, double vel_z,
        double tile_size, double load_radius, double bias = 0.5) {
    struct Scored {
        TileCoord coord;
        double score;
    };
    std::vector<Scored> scored;

    const TileCoord c = world_to_tile(cam_x, cam_z, tile_size);
    const int reach = static_cast<int>(std::ceil(load_radius / tile_size)) + 1;
    const double speed = std::sqrt(vel_x * vel_x + vel_z * vel_z);
    const bool moving = speed > 1e-6;
    const double dir_x = moving ? vel_x / speed : 0.0;
    const double dir_z = moving ? vel_z / speed : 0.0;
    // Clamp the direction weight below 1 so the velocity term only *discounts* a
    // tile's distance (factor in [1-b, 1+b], always > 0). This guarantees the one
    // invariant that matters: the tile under the camera (distance 0, score 0)
    // always sorts first. It deliberately does NOT keep the rest nearest-first —
    // among non-home tiles a farther tile ahead can outrank a nearer tile behind,
    // which is the whole point of travel-direction streaming.
    const double b = bias < 0.0 ? 0.0 : (bias > 0.95 ? 0.95 : bias);

    for (int dz = -reach; dz <= reach; ++dz) {
        for (int dx = -reach; dx <= reach; ++dx) {
            const TileCoord t{c.x + dx, c.z + dz};
            double tx, tz;
            tile_center(t, tile_size, tx, tz);
            const double ox = tx - cam_x;
            const double oz = tz - cam_z;
            const double dist = std::sqrt(ox * ox + oz * oz);
            if (dist > load_radius) {
                continue;
            }
            // fdot = +1 directly ahead, -1 directly behind. Scales distance by
            // (1 - b·fdot) so ahead-tiles sort earlier; a far-ahead tile may beat
            // a nearer-behind one (intended), but no tile beats the dist-0 home.
            const double fdot = (dist > 1e-6) ? (ox * dir_x + oz * dir_z) / dist : 0.0;
            const double score = moving ? dist * (1.0 - b * fdot) : dist;
            scored.push_back(Scored{t, score});
        }
    }

    std::sort(scored.begin(), scored.end(),
            [](const Scored &a, const Scored &b) { return a.score < b.score; });

    std::vector<TileCoord> out;
    out.reserve(scored.size());
    for (const Scored &s : scored) {
        out.push_back(s.coord);
    }
    return out;
}

// Of the currently-resident tiles, which to unload: those whose center is now
// beyond `unload_radius`. Keep unload_radius > load_radius (hysteresis) so a
// tile sitting on the load boundary isn't loaded and unloaded on alternate
// frames as the camera jitters.
inline std::vector<TileCoord> tiles_to_unload(
        const std::vector<TileCoord> &resident, double cam_x, double cam_z,
        double tile_size, double unload_radius) {
    std::vector<TileCoord> out;
    for (const TileCoord &t : resident) {
        double tx, tz;
        tile_center(t, tile_size, tx, tz);
        const double ox = tx - cam_x;
        const double oz = tz - cam_z;
        if (std::sqrt(ox * ox + oz * oz) > unload_radius) {
            out.push_back(t);
        }
    }
    return out;
}

} // namespace worldcore_streaming
