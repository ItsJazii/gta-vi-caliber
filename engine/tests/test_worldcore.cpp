// Plain-C++ unit tests for engine logic that doesn't need a Godot runtime.
// Build & run: scons tests (see engine/SConstruct), or let CI do it.
// Keep this dependency-free (no test framework) until the suite outgrows it.
#include <cmath>
#include <cstdio>
#include <cstring>

#include "../src/native_bench/bench_kernels.h"
#include "../src/worldcore/crowd_steering_core.h"
#include "../src/worldcore/impostor_core.h"
#include "../src/worldcore/spatial_hash_core.h"
#include "../src/worldcore/tile_streamer_core.h"
#include "../src/worldcore/traffic_core.h"
#include "../src/worldcore/worldcore_version.h"

using worldcore_streaming::TileCoord;

static int failures = 0;

#define CHECK(cond)                                                          \
    do {                                                                     \
        if (!(cond)) {                                                       \
            ++failures;                                                      \
            std::fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
        }                                                                    \
    } while (0)

static void test_version_is_consistent() {
    char expected[32];
    std::snprintf(expected, sizeof(expected), "%d.%d.%d", WORLDCORE_VERSION_MAJOR,
            WORLDCORE_VERSION_MINOR, WORLDCORE_VERSION_PATCH);
    CHECK(std::strcmp(expected, WORLDCORE_VERSION_STRING) == 0);
    CHECK(std::strlen(WORLDCORE_VERSION_STRING) > 0);
}

static void test_sum_of_squares() {
    CHECK(worldcore_kernels::sum_of_squares(0) == 0);
    CHECK(worldcore_kernels::sum_of_squares(1) == 0); // sums i in [0, n)
    CHECK(worldcore_kernels::sum_of_squares(4) == 0 + 1 + 4 + 9);
    CHECK(worldcore_kernels::sum_of_squares(100) == 328350);
}

static void test_world_to_tile() {
    using worldcore_streaming::world_to_tile;
    CHECK(world_to_tile(0.0, 0.0, 256.0) == (TileCoord{0, 0}));
    CHECK(world_to_tile(257.0, 0.0, 256.0) == (TileCoord{1, 0}));
    CHECK(world_to_tile(-1.0, 0.0, 256.0) == (TileCoord{-1, 0}));
    CHECK(world_to_tile(0.0, 600.0, 256.0) == (TileCoord{0, 2}));
}

static void test_desired_tiles_within_radius_nearest_first() {
    using worldcore_streaming::desired_tiles;
    using worldcore_streaming::tile_center;
    // Stationary camera at the center of tile (0,0) — so that tile is uniquely
    // nearest (dist 0). (A camera on a tile corner would 4-way tie.)
    const double cam_x = 128.0, cam_z = 128.0;
    auto tiles = desired_tiles(cam_x, cam_z, 0.0, 0.0, 256.0, 300.0, 0.5);
    CHECK(!tiles.empty());
    CHECK(tiles.front() == (TileCoord{0, 0})); // closest
    for (const TileCoord &t : tiles) {
        double cx, cz;
        tile_center(t, 256.0, cx, cz);
        const double dx = cx - cam_x, dz = cz - cam_z;
        CHECK(std::sqrt(dx * dx + dz * dz) <= 300.0 + 1e-9);
    }
}

static void test_velocity_prioritizes_tiles_ahead() {
    using worldcore_streaming::desired_tiles;
    // Camera in tile (0,0) moving +x: the tile ahead (1,0) must load before the
    // symmetric tile behind (-1,0).
    auto tiles = desired_tiles(128.0, 128.0, 10.0, 0.0, 256.0, 800.0, 0.8);
    int ahead = -1, behind = -1;
    for (int i = 0; i < static_cast<int>(tiles.size()); ++i) {
        if (tiles[i] == (TileCoord{1, 0})) {
            ahead = i;
        }
        if (tiles[i] == (TileCoord{-1, 0})) {
            behind = i;
        }
    }
    CHECK(ahead >= 0 && behind >= 0);
    CHECK(ahead < behind);
}

static void test_unload_uses_hysteresis() {
    using worldcore_streaming::tiles_to_unload;
    std::vector<TileCoord> resident = {{0, 0}, {5, 0}};
    auto drop = tiles_to_unload(resident, 0.0, 0.0, 256.0, 1000.0);
    // (0,0) center ~181 m away stays; (5,0) center ~1414 m away unloads.
    CHECK(drop.size() == 1);
    CHECK(drop.front() == (TileCoord{5, 0}));
}

static void test_octa_encode_cardinals() {
    using worldcore_impostor::octa_encode;
    double u, v;
    octa_encode(0.0, 1.0, 0.0, u, v); // straight up -> center
    CHECK(std::fabs(u - 0.5) < 1e-9 && std::fabs(v - 0.5) < 1e-9);
    octa_encode(1.0, 0.0, 0.0, u, v); // +x -> right edge, mid height
    CHECK(std::fabs(u - 1.0) < 1e-9 && std::fabs(v - 0.5) < 1e-9);
    octa_encode(0.0, 0.0, 1.0, u, v); // +z -> mid width, top edge
    CHECK(std::fabs(u - 0.5) < 1e-9 && std::fabs(v - 1.0) < 1e-9);
    octa_encode(-1.0, 0.0, 0.0, u, v); // -x -> left edge
    CHECK(std::fabs(u - 0.0) < 1e-9 && std::fabs(v - 0.5) < 1e-9);
}

static void test_atlas_cell_clamps() {
    using worldcore_impostor::atlas_cell;
    int col, row;
    atlas_cell(0.0, 0.0, 8, col, row);
    CHECK(col == 0 && row == 0);
    atlas_cell(0.99, 0.99, 8, col, row);
    CHECK(col == 7 && row == 7);
    atlas_cell(1.0, 1.0, 8, col, row); // edge u=1 must clamp, not index 8
    CHECK(col == 7 && row == 7);
    atlas_cell(0.5, 0.5, 8, col, row);
    CHECK(col == 4 && row == 4);
}

static void test_projected_radius_shrinks_with_distance() {
    using worldcore_impostor::projected_radius_px;
    const double fov = 60.0 * 3.14159265358979323846 / 180.0;
    const double near_px = projected_radius_px(10.0, 50.0, fov, 1080.0);
    const double far_px = projected_radius_px(10.0, 500.0, fov, 1080.0);
    CHECK(near_px > far_px);
    CHECK(far_px > 0.0);
}

static void test_should_impostor_threshold() {
    using worldcore_impostor::should_impostor;
    const double fov = 60.0 * 3.14159265358979323846 / 180.0;
    // 10 m bound, 32 px threshold: close stays a mesh, far becomes an impostor.
    CHECK(!should_impostor(10.0, 50.0, fov, 1080.0, 32.0));
    CHECK(should_impostor(10.0, 500.0, fov, 1080.0, 32.0));
}

static void test_degenerate_fov_keeps_mesh() {
    using worldcore_impostor::projected_radius_px;
    using worldcore_impostor::should_impostor;
    // Near-zero FOV (extreme zoom) => object huge on screen => keep the mesh,
    // never swap to the impostor. Guards the Codex-found edge case.
    CHECK(projected_radius_px(10.0, 500.0, 1e-12, 1080.0) >= 1080.0);
    CHECK(!should_impostor(10.0, 500.0, 1e-12, 1080.0, 32.0));
}

static void test_spatial_hash_radius_query() {
    worldcore_spatial::SpatialHash2D h(8.0);
    h.insert(1, 0.0, 0.0);
    h.insert(2, 3.0, 0.0); // within 5 of origin
    h.insert(3, 100.0, 100.0); // far away
    h.insert(4, 0.0, 4.9); // within 5
    auto near = h.query_radius(0.0, 0.0, 5.0);
    // ids 1,2,4 present, 3 absent. (Order not guaranteed.)
    bool has1 = false, has2 = false, has3 = false, has4 = false;
    for (int id : near) {
        if (id == 1) has1 = true;
        if (id == 2) has2 = true;
        if (id == 3) has3 = true;
        if (id == 4) has4 = true;
    }
    CHECK(has1 && has2 && has4 && !has3);
    CHECK(h.size() == 4);
}

static void test_spatial_hash_crosses_cell_boundary() {
    // Two points in different cells (cell_size 8) but close in space: the query
    // must find the neighbour across the cell boundary, not miss it.
    worldcore_spatial::SpatialHash2D h(8.0);
    h.insert(1, 7.5, 0.0); // cell (0,0)
    h.insert(2, 8.5, 0.0); // cell (1,0), only 1.0 away
    auto near = h.query_radius(7.5, 0.0, 2.0);
    bool has2 = false;
    for (int id : near) {
        if (id == 2) has2 = true;
    }
    CHECK(has2);
}

static void test_spatial_hash_excludes_corner_square() {
    // A point in the bounding-box corner but outside the circle must be excluded
    // (true-distance refine, not just cell membership).
    worldcore_spatial::SpatialHash2D h(8.0);
    h.insert(1, 4.0, 4.0); // dist sqrt(32)=5.66 from origin
    auto near = h.query_radius(0.0, 0.0, 5.0);
    CHECK(near.empty());
}

static void test_spatial_hash_negative_coords() {
    // cell_key must handle negative cells (Codex: signed left-shift was UB).
    worldcore_spatial::SpatialHash2D h(8.0);
    h.insert(1, -20.0, -33.0);
    h.insert(2, -19.0, -33.0); // ~1 m away
    auto near = h.query_radius(-20.0, -33.0, 3.0);
    bool has1 = false, has2 = false;
    for (int id : near) {
        if (id == 1) has1 = true;
        if (id == 2) has2 = true;
    }
    CHECK(has1 && has2);
}

static void test_spatial_hash_reinsert_is_upsert() {
    // Re-inserting an id moves it; it must not appear twice or linger at the old
    // spot (Codex: duplicate-insert leaked stale bucket entries).
    worldcore_spatial::SpatialHash2D h(8.0);
    h.insert(1, 0.0, 0.0);
    h.insert(1, 50.0, 50.0); // move far
    CHECK(h.size() == 1);
    CHECK(h.query_radius(0.0, 0.0, 5.0).empty()); // gone from old cell
    auto at_new = h.query_radius(50.0, 50.0, 5.0);
    int count1 = 0;
    for (int id : at_new) {
        if (id == 1) ++count1;
    }
    CHECK(count1 == 1); // present exactly once, not duplicated
}

static void test_separation_pushes_away() {
    using namespace worldcore_crowd;
    std::vector<Vec2> neighbors = {{1.0, 0.0}}; // neighbour to the +x
    Vec2 f = separation(Vec2{0.0, 0.0}, neighbors, 4.0);
    CHECK(f.x < 0.0); // pushed in -x, away from the neighbour
    CHECK(std::fabs(f.z) < 1e-9);
}

static void test_separation_ignores_outside_radius() {
    using namespace worldcore_crowd;
    std::vector<Vec2> neighbors = {{100.0, 0.0}}; // far outside radius 4
    Vec2 f = separation(Vec2{0.0, 0.0}, neighbors, 4.0);
    CHECK(length(f) < 1e-9);
}

static void test_cohesion_pulls_toward_centroid() {
    using namespace worldcore_crowd;
    std::vector<Vec2> neighbors = {{10.0, 0.0}, {10.0, 0.0}};
    Vec2 f = cohesion(Vec2{0.0, 0.0}, neighbors);
    CHECK(f.x > 0.0); // toward the +x cluster
}

static void test_alignment_is_average_heading() {
    using namespace worldcore_crowd;
    std::vector<Vec2> vels = {{2.0, 0.0}, {0.0, 2.0}};
    Vec2 f = alignment(vels);
    CHECK(std::fabs(f.x - 1.0) < 1e-9 && std::fabs(f.z - 1.0) < 1e-9);
}

static void test_combine_clamps_to_max_force() {
    using namespace worldcore_crowd;
    Vec2 big{100.0, 0.0};
    Vec2 f = combine(big, big, big, 1.0, 1.0, 1.0, 8.0);
    CHECK(length(f) <= 8.0 + 1e-9);
}

static void test_empty_neighbors_zero_force() {
    using namespace worldcore_crowd;
    std::vector<Vec2> none;
    CHECK(length(separation(Vec2{0.0, 0.0}, none, 4.0)) < 1e-9);
    CHECK(length(cohesion(Vec2{0.0, 0.0}, none)) < 1e-9);
    CHECK(length(alignment(none)) < 1e-9);
}

static void test_clamp_len_negative_budget_is_zero() {
    using namespace worldcore_crowd;
    // Negative max_len must not flip direction (Codex): no budget -> zero force.
    Vec2 f = clamp_len(Vec2{5.0, 0.0}, -8.0);
    CHECK(length(f) < 1e-9);
}

static void test_arrive_seeks_then_slows() {
    using namespace worldcore_crowd;
    // Far from target (at rest): desired heads toward +x at ~max_speed.
    Vec2 far = arrive(Vec2{0.0, 0.0}, Vec2{0.0, 0.0}, Vec2{100.0, 0.0}, 5.0, 6.0);
    CHECK(far.x > 0.0);
    CHECK(std::fabs(length(far) - 6.0) < 1e-6);
    // Inside slow_radius the desired speed ramps down, so |force| is smaller.
    Vec2 near = arrive(Vec2{0.0, 0.0}, Vec2{0.0, 0.0}, Vec2{2.5, 0.0}, 5.0, 6.0);
    CHECK(length(near) < length(far));
}

static void test_avoid_pushes_off_obstacle() {
    using namespace worldcore_crowd;
    std::vector<Vec2> obstacles = {{2.0, 0.0}}; // obstacle to the +x
    std::vector<double> radii = {3.0};
    Vec2 f = avoid_obstacles(Vec2{0.0, 0.0}, obstacles, radii, 1.0); // within 4 of it
    CHECK(f.x < 0.0); // pushed -x, away
    // An obstacle far outside radius+margin exerts no force.
    std::vector<Vec2> faro = {{100.0, 0.0}};
    CHECK(length(avoid_obstacles(Vec2{0.0, 0.0}, faro, radii, 1.0)) < 1e-9);
    // Degenerate obstacle (zero radius + zero margin) exerts no force even when
    // the agent sits exactly on its centre (Codex: dead-centre branch needs the
    // same safe>0 guard as the penetration branch).
    std::vector<Vec2> here = {{0.0, 0.0}};
    std::vector<double> zero = {0.0};
    CHECK(length(avoid_obstacles(Vec2{0.0, 0.0}, here, zero, 0.0)) < 1e-9);
}

static void test_idm_accelerates_on_clear_road() {
    using worldcore_traffic::car_following_accel;
    // Slow car, leader far ahead and fast: should accelerate toward desired.
    double a = car_following_accel(5.0, 1000.0, 30.0, 30.0, 1.5, 2.0, 2.0, 1.5);
    CHECK(a > 0.0);
}

static void test_idm_cruises_at_desired_speed() {
    using worldcore_traffic::car_following_accel;
    // At desired speed on a clear road: acceleration ~0.
    double a = car_following_accel(30.0, 1000.0, 30.0, 30.0, 1.5, 2.0, 2.0, 1.5);
    CHECK(std::fabs(a) < 0.05);
}

static void test_idm_brakes_for_close_slow_leader() {
    using worldcore_traffic::car_following_accel;
    // Fast car, small gap to a stopped leader: must brake hard (negative).
    double a = car_following_accel(20.0, 5.0, 0.0, 30.0, 1.5, 2.0, 2.0, 1.5);
    CHECK(a < 0.0);
}

static void test_idm_brakes_hard_on_overlap() {
    using worldcore_traffic::car_following_accel;
    // Zero gap (touching the leader): strong braking.
    double a = car_following_accel(20.0, 0.0, 0.0, 30.0, 1.5, 2.0, 2.0, 1.5);
    CHECK(a < 0.0);
}

static void test_idm_negative_param_stays_finite() {
    using worldcore_traffic::car_following_accel;
    // A negative brake param must not sqrt(negative) into NaN (Codex review).
    double a = car_following_accel(20.0, 50.0, 0.0, 30.0, -1.5, 2.0, 2.0, 1.5);
    CHECK(std::isfinite(a));
}

int main() {
    test_version_is_consistent();
    test_sum_of_squares();
    test_world_to_tile();
    test_desired_tiles_within_radius_nearest_first();
    test_velocity_prioritizes_tiles_ahead();
    test_unload_uses_hysteresis();
    test_octa_encode_cardinals();
    test_atlas_cell_clamps();
    test_projected_radius_shrinks_with_distance();
    test_should_impostor_threshold();
    test_degenerate_fov_keeps_mesh();
    test_spatial_hash_radius_query();
    test_spatial_hash_crosses_cell_boundary();
    test_spatial_hash_excludes_corner_square();
    test_spatial_hash_negative_coords();
    test_spatial_hash_reinsert_is_upsert();
    test_separation_pushes_away();
    test_separation_ignores_outside_radius();
    test_cohesion_pulls_toward_centroid();
    test_alignment_is_average_heading();
    test_combine_clamps_to_max_force();
    test_empty_neighbors_zero_force();
    test_clamp_len_negative_budget_is_zero();
    test_arrive_seeks_then_slows();
    test_avoid_pushes_off_obstacle();
    test_idm_accelerates_on_clear_road();
    test_idm_cruises_at_desired_speed();
    test_idm_brakes_for_close_slow_leader();
    test_idm_brakes_hard_on_overlap();
    test_idm_negative_param_stays_finite();
    if (failures > 0) {
        std::fprintf(stderr, "engine tests: %d failure(s)\n", failures);
        return 1;
    }
    std::printf("engine tests: all passed\n");
    return 0;
}
