// SPDX-FileCopyrightText: Copyright 2026 shadPS4 Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <array>
#include <cmath>
#include <cstddef>

namespace Input {

/// A finger on a touchpad, moved by a stick: for controllers that have no touchpad, where a
/// title made for one has its players swipe and drag. Where the stick points is where the
/// finger is, with what a stick needs and a finger does not:
///  - The finger comes down in the middle of the pad and moves out from there, so that a push
///    of the stick is a swipe over all of the way it goes.
///  - A stick that is let go flies back to its centre; a finger that is lifted does not go
///    back to where it came from first. A title that goes by how far the finger was dragged
///    when it lifts (ASTRO BOT Rescue Mission pulls a catapult back that way at the end of
///    every level, and shoots when the finger lets go) would find nothing pulled at all. So
///    the finger stays where the stick was before it started back, and lifts from there once
///    the stick has come to rest.
///  - A stick may be moved through its centre, from one side to the other, without the finger
///    lifting on the way: a drag over the whole pad.
///  - A stick that never comes to rest near its centre (a worn one that drifts) moves no
///    finger: it would touch the pad for good, and a real finger on a real touchpad would
///    count for nothing beside it.
class StickFinger {
public:
    struct Touch {
        bool down;
        /// On the pad, 0 to 1: from its left to its right, from its far edge to its near one.
        float x;
        float y;
    };

    /// `time` in seconds, from any moment; `x` to the right and `y` towards the player of the
    /// stick's centre, -1 to 1 each. To be called at least some thirty times a second.
    Touch Update(double time, float x, float y) {
        const float r = std::hypot(x, y);
        const float previous_r = count != 0 ? At(0).r : r;
        Push({time, x, y, r});

        if (!down) {
            if (r <= Rest) {
                armed = true;
            }
            if (!armed || r <= Start) {
                return Lifted();
            }
            down = true;
            armed = false;
            held = false;
            finger_x = 0.0f;
            finger_y = 0.0f;
            return Touching();
        }

        // The furthest the stick has been out in the last moments, and whether it is on its
        // way back from there in a hurry.
        const Sample* peak = &At(0);
        for (size_t back = 1; back < count && time - At(back).time <= Window; ++back) {
            if (At(back).r > peak->r) {
                peak = &At(back);
            }
        }
        const bool flying_back = r < peak->r - Drop && r <= previous_r + 0.01f;
        const bool inside = r <= Start;
        if (!inside && !flying_back) {
            finger_x = x;
            finger_y = y;
            held = false;
        } else if (flying_back && !held) {
            finger_x = peak->x;
            finger_y = peak->y;
            held = true;
        }
        if (inside && IsStill(time)) {
            down = false;
            armed = r <= Rest;
            return Lifted();
        }
        return Touching();
    }

    /// The finger is lifted, and the stick has to come to rest before it touches again.
    void Reset() {
        down = false;
        armed = false;
        held = false;
        count = 0;
    }

    bool IsDown() const {
        return down;
    }

    /// The stick counts as at rest within this of its centre, and the finger comes down once
    /// it is further out than that.
    static constexpr float Rest = 0.15f;
    static constexpr float Start = 0.25f;
    /// How far from the pad's centre the stick pushed all the way puts the finger, of the
    /// pad's size.
    static constexpr float Reach = 0.45f;

private:
    struct Sample {
        double time;
        float x;
        float y;
        float r;
    };

    /// Flying back: nearer the centre by this much than the stick was within that long.
    static constexpr float Drop = 0.12f;
    static constexpr double Window = 0.045;
    /// Come to rest: near the centre and hardly moved for this long.
    static constexpr double Still = 0.025;
    static constexpr float StillMove = 0.05f;

    /// The sample taken `back` samples ago, 0 for the newest.
    const Sample& At(size_t back) const {
        return samples[(newest + samples.size() - back) % samples.size()];
    }

    void Push(const Sample& sample) {
        newest = (newest + 1) % samples.size();
        samples[newest] = sample;
        if (count < samples.size()) {
            ++count;
        }
    }

    bool IsStill(double time) const {
        const Sample& now = At(0);
        for (size_t back = 1; back < count; ++back) {
            const Sample& then = At(back);
            if (std::abs(then.x - now.x) > StillMove || std::abs(then.y - now.y) > StillMove) {
                return false;
            }
            if (time - then.time >= Still) {
                return true;
            }
        }
        return false;
    }

    Touch Touching() const {
        const auto on_pad = [](float value) {
            const float at = 0.5f + value * Reach;
            return at < 0.0f ? 0.0f : at > 1.0f ? 1.0f : at;
        };
        return {true, on_pad(finger_x), on_pad(finger_y)};
    }

    Touch Lifted() const {
        Touch touch = Touching();
        touch.down = false;
        return touch;
    }

    std::array<Sample, 32> samples{};
    size_t newest{};
    size_t count{};
    bool down{};
    bool armed{};
    bool held{};
    float finger_x{};
    float finger_y{};
};

} // namespace Input
