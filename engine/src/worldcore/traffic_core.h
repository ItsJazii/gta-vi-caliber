#pragma once

// Pure, runtime-free car-following model for M4 traffic — the longitudinal brain
// of a vehicle: given the car's speed, the gap to the car ahead, and that
// leader's speed, return the acceleration that cruises toward a desired speed on
// a clear road while keeping a safe time-headway gap (and braking hard if the
// gap collapses). This is the Intelligent Driver Model (IDM). Header-only and
// free of godot-cpp types so it unit-tests headless, like the other cores.

#include <algorithm>
#include <cmath>

namespace worldcore_traffic {

// IDM acceleration.
//   speed         current speed (m/s)
//   gap           bumper-to-bumper distance to the leader (m)
//   leader_speed  leader's speed (m/s)
//   desired_speed v0 — free-road cruising speed
//   max_accel     a  — comfortable acceleration
//   comfort_decel b  — comfortable braking (positive)
//   min_gap       s0 — standstill distance
//   time_headway  T  — desired time gap to the leader
inline double car_following_accel(double speed, double gap, double leader_speed,
        double desired_speed, double max_accel, double comfort_decel, double min_gap,
        double time_headway) {
    const double v0 = desired_speed > 1e-6 ? desired_speed : 1e-6;
    // Free-road term: ease toward desired speed (quartic → soft approach).
    const double free_term = 1.0 - std::pow(speed / v0, 4.0);

    // Interaction term: desired dynamic gap s* versus the actual gap.
    double interaction = 0.0;
    if (gap > 1e-6) {
        // Guard the product before sqrt: a negative param (reachable only via a
        // raw core call — the class setters reject negatives) would otherwise be
        // sqrt(negative) = NaN (Codex review).
        const double brake_product = max_accel * comfort_decel;
        const double brake_denom = brake_product > 1e-12 ? 2.0 * std::sqrt(brake_product) : 0.0;
        const double approach = brake_denom > 1e-9 ? speed * (speed - leader_speed) / brake_denom : 0.0;
        const double s_star = min_gap + std::max(0.0, speed * time_headway + approach);
        const double ratio = s_star / gap;
        interaction = ratio * ratio;
    } else {
        interaction = 1.0e6; // touching/overlapping the leader → brake hard
    }

    return max_accel * (free_term - interaction);
}

} // namespace worldcore_traffic
