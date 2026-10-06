// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <functional>
#include <mutex>
#include <utility>

#include "pad_state.h"
// From the emulator (src/input): the right stick as a finger on the touchpad.
#include "stick_finger.h"

/// PS4 pad button bits (ORBIS_PAD_BUTTON_*).
namespace PadButton {
inline constexpr uint32_t L3 = 0x2, R3 = 0x4, Options = 0x8;
inline constexpr uint32_t Up = 0x10, Right = 0x20, Down = 0x40, Left = 0x80;
inline constexpr uint32_t L2 = 0x100, R2 = 0x200, L1 = 0x400, R1 = 0x800;
inline constexpr uint32_t Triangle = 0x1000, Circle = 0x2000, Cross = 0x4000, Square = 0x8000;
inline constexpr uint32_t TouchPad = 0x100000;
} // namespace PadButton

/// What a gamepad says, as the system reports it. Buttons use the PS4 pad bit layout; sticks
/// go from -1 to 1, to the right and towards the player; triggers from 0 to 1.
struct GamepadState {
    uint32_t buttons{};
    float left_x{}, left_y{}, right_x{}, right_y{};
    float left_trigger{}, right_trigger{};
    /// A finger on the gamepad's own touchpad, 0 to 1 from its left and from its far edge.
    bool touch_down{};
    float touch_x{0.5f}, touch_y{0.5f};
};

/// What the headset's own two controllers say, as its runtime reports them: sticks from -1 to
/// 1, to the right and away from the player (the other way up than a gamepad's).
struct TouchState {
    /// They are in the player's hands, and the game is what the player has in front of them.
    bool present{};
    bool a{}, b{}, x{}, y{}, menu{};
    bool left_stick_in{}, right_stick_in{};
    float left_grip{}, right_grip{};
    float left_trigger{}, right_trigger{};
    float left_x{}, left_y{}, right_x{}, right_y{};
};

/// Makes the one DualShock 4 the game is played with out of what the player has: a gamepad
/// paired with the headset, the headset's own two controllers, or both.
///
/// The headset's controllers are played like this: the left stick is the left stick; the
/// right one is a finger on the touchpad (as it is for gamepads without one) and pressing it
/// in presses the touchpad; A and B, under the right thumb, are cross and square, X and Y
/// circle and triangle, and X and Y together blow into the microphone; the triggers are L2
/// and R2, the grips L1 and R1, the left controller's menu button is OPTIONS. Both sticks
/// pressed in reset the view.
///
/// With both a gamepad and the headset's controllers at hand, the game is played with the
/// one that was used last: a button on the other takes over. A gamepad is taken over from
/// only by what a hand cannot do without holding a controller (a button under a thumb, a
/// stick), since it is hands the headset sees while a gamepad is held.
class PadRouter {
public:
    enum class Source { None, Gamepad, Touch };

    /// Bits of what TakeRecenter returns (those of XrRecenter).
    static constexpr uint32_t RecenterPad = 1;
    static constexpr uint32_t RecenterSeat = 2;
    /// Bits of what TouchMenu returns.
    static constexpr uint32_t MenuLeft = 1;
    static constexpr uint32_t MenuRight = 2;
    static constexpr uint32_t MenuConfirm = 4;

    /// How long OPTIONS is held for the view to be reset, in seconds: as on a PlayStation VR.
    static constexpr double OptionsHold = 1.0;

    struct Output {
        PadState pad;
        /// The player blows with buttons: the game is to hear it.
        bool blowing{};

        bool operator==(const Output&) const = default;
    };

    /// What the rest of the host needs to know to place the controller and to answer it.
    struct View {
        Source source{Source::None};
        bool playing{};
        bool gamepad_connected{};
        /// The gamepad's own motion sensors say how it is held.
        bool gamepad_motion{};
        float gamepad_accel[3]{};
        bool touch_present{};
    };

    /// The time everything here is told, in seconds: the same clock for every caller.
    static double Now() {
        return std::chrono::duration<double>(
                   std::chrono::steady_clock::now().time_since_epoch())
            .count();
    }

    /// Both are called with the router's lock held: they must not call back into it.
    void SetSink(std::function<void(const Output&)> sink_) {
        std::scoped_lock lock{mutex};
        sink = std::move(sink_);
    }
    void SetNotice(std::function<void(const char*)> notice_) {
        std::scoped_lock lock{mutex};
        notice = std::move(notice_);
    }

    /// Whether the right stick moves a finger over the touchpad.
    void SetStickTouchpad(bool enabled) {
        std::scoped_lock lock{mutex};
        stick_touchpad = enabled;
    }

    /// The game runs, and what the player presses is meant for it. Until then the controls
    /// belong to the host's own menu, and nothing of them reaches the game: neither does
    /// what is still held down from there, until it is let go.
    void SetPlaying(bool playing_, double now) {
        std::scoped_lock lock{mutex};
        if (playing_ && !playing) {
            playing = true;
            held_back = 0;
            held_back = Compose(now, false).pad.buttons;
        }
        playing = playing_;
        Publish(now);
    }

    /// A gamepad is there (again, or another one than before), or the last one is gone.
    void SetGamepadConnected(bool connected, double now) {
        std::scoped_lock lock{mutex};
        gamepad_connected = connected;
        // Its motion sensors, if it has any, speak up within milliseconds.
        gamepad_motion = false;
        if (!connected) {
            gamepad = {};
        }
        Arbitrate(false, false);
        Publish(now);
    }

    void SetGamepad(const GamepadState& state, double now) {
        std::scoped_lock lock{mutex};
        const bool used = (state.buttons & ~gamepad.buttons) != 0 ||
                          (state.touch_down && !gamepad.touch_down) ||
                          Pushed(state.left_x, state.left_y, gamepad.left_x, gamepad.left_y) ||
                          Pushed(state.right_x, state.right_y, gamepad.right_x, gamepad.right_y) ||
                          Pulled(state.left_trigger, gamepad.left_trigger) ||
                          Pulled(state.right_trigger, gamepad.right_trigger);
        gamepad = state;
        Arbitrate(used, false);
        Publish(now);
    }

    /// Gyroscope in rad/s and accelerometer in m/s², in the gamepad's own frame.
    void SetGamepadMotion(const float gyro[3], const float accel[3], double now) {
        std::scoped_lock lock{mutex};
        gamepad_motion = true;
        std::copy(gyro, gyro + 3, gamepad_gyro);
        std::copy(accel, accel + 3, gamepad_accel);
        Publish(now);
    }

    /// To be called for every picture the headset shows: it is also what keeps time for
    /// buttons that are held and for the stick's finger.
    void SetTouch(const TouchState& state, double now) {
        std::scoped_lock lock{mutex};
        const TouchState next = state.present ? state : TouchState{};
        // (Triggers and grips are left out: a pinch of the fingers must never count.)
        const bool used =
            (next.a && !touch.a) || (next.b && !touch.b) || (next.x && !touch.x) ||
            (next.y && !touch.y) || (next.left_stick_in && !touch.left_stick_in) ||
            (next.right_stick_in && !touch.right_stick_in) ||
            Pushed(next.left_x, next.left_y, touch.left_x, touch.left_y) ||
            Pushed(next.right_x, next.right_y, touch.right_x, touch.right_y);
        touch = next;
        Arbitrate(false, used);
        Publish(now);
    }

    /// Without the headset's controllers: time has passed.
    void Tick(double now) {
        std::scoped_lock lock{mutex};
        Publish(now);
    }

    /// The player chose with this one in the host's menu: it is what they hold.
    void Use(Source wanted, double now) {
        std::scoped_lock lock{mutex};
        Arbitrate(wanted == Source::Gamepad, wanted == Source::Touch);
        Publish(now);
    }

    View Look() {
        std::scoped_lock lock{mutex};
        View view;
        view.source = source;
        view.playing = playing;
        view.gamepad_connected = gamepad_connected;
        view.gamepad_motion = gamepad_motion;
        std::copy(gamepad_accel, gamepad_accel + 3, view.gamepad_accel);
        view.touch_present = touch.present;
        return view;
    }

    /// The resets of the view the player has asked for with buttons since the last call.
    uint32_t TakeRecenter() {
        std::scoped_lock lock{mutex};
        return std::exchange(recenter, 0u);
    }

    /// What the headset's controllers say to the host's own menu: a stick held to a side, or
    /// what confirms (A, or a trigger as everywhere else in the headset).
    uint32_t TouchMenu() {
        std::scoped_lock lock{mutex};
        if (!touch.present) {
            return 0;
        }
        const float x = std::abs(touch.left_x) >= std::abs(touch.right_x) ? touch.left_x
                                                                           : touch.right_x;
        return (x < -0.55f ? MenuLeft : 0) | (x > 0.55f ? MenuRight : 0) |
               (touch.a || touch.left_trigger > 0.6f || touch.right_trigger > 0.6f ? MenuConfirm
                                                                                    : 0);
    }

private:
    /// A stick that was near its centre and is well away from it now.
    static bool Pushed(float x, float y, float before_x, float before_y) {
        return std::hypot(x, y) > 0.6f && std::hypot(before_x, before_y) <= 0.6f;
    }

    static bool Pulled(float value, float before) {
        return value > 0.5f && before <= 0.5f;
    }

    void Note(const char* text) {
        if (notice) {
            notice(text);
        }
    }

    /// Decides which of the two the game is played with.
    void Arbitrate(bool gamepad_used, bool touch_used) {
        Source wanted = source;
        if (gamepad_used && gamepad_connected) {
            wanted = Source::Gamepad;
        }
        if (touch_used && touch.present) {
            wanted = Source::Touch;
        }
        if (wanted == Source::Gamepad && !gamepad_connected) {
            wanted = Source::None;
        }
        if (wanted == Source::None) {
            // Nothing was chosen: a gamepad if there is one, as before the headset's own
            // controllers could play; else those, as soon as they are picked up.
            wanted = gamepad_connected ? Source::Gamepad
                                       : touch.present ? Source::Touch : Source::None;
        }
        if (wanted == source) {
            return;
        }
        source = wanted;
        // What the other one's stick was doing on the touchpad is over.
        stick_finger.Reset();
        options_since = -1.0;
        options_fired = false;
        view_reset_held = false;
        Note(source == Source::Touch
                 ? "the game is played with the headset's own controllers now"
                 : source == Source::Gamepad ? "the game is played with the gamepad now"
                                             : "there is no controller to play the game with");
    }

    static uint8_t Stick(float value) {
        return static_cast<uint8_t>(
            std::clamp(static_cast<int>(std::lround(128.0f + value * 127.0f)), 0, 255));
    }

    static uint8_t Trigger(float value) {
        return static_cast<uint8_t>(
            std::lround(std::clamp(value, 0.0f, 1.0f) * 255.0f));
    }

    /// What the game is given now. With `act`, what the buttons mean besides (resets of the
    /// view) is acted on as well.
    Output Compose(double now, bool act) {
        Output out;
        if (!playing) {
            return out;
        }
        uint32_t buttons = 0;
        float left_x = 0.0f, left_y = 0.0f, right_x = 0.0f, right_y = 0.0f;
        float left_trigger = 0.0f, right_trigger = 0.0f;
        bool real_finger = false;
        float touch_x = 0.5f, touch_y = 0.5f;
        bool view_reset = false;
        bool blow = false;

        if (source == Source::Touch) {
            const TouchState& t = touch;
            const auto add = [&](bool down, uint32_t button) {
                if (down) {
                    buttons |= button;
                }
            };
            add(t.a, PadButton::Cross);
            add(t.b, PadButton::Square);
            // The left controller's two buttons together are not circle and triangle: they
            // blow into the microphone, for as long as they are held.
            blow = t.x && t.y;
            add(t.x && !blow, PadButton::Circle);
            add(t.y && !blow, PadButton::Triangle);
            add(t.menu, PadButton::Options);
            add(t.left_grip > 0.5f, PadButton::L1);
            add(t.right_grip > 0.5f, PadButton::R1);
            // Both sticks pressed in is not something a game is played with: it resets the
            // view, for which a gamepad has its PS button.
            view_reset = t.left_stick_in && t.right_stick_in;
            add(t.left_stick_in && !view_reset, PadButton::L3);
            add(t.right_stick_in && !view_reset, PadButton::TouchPad);
            // (A trigger that is not quite at rest is not pulled: any pull counts as the
            // button.)
            left_trigger = t.left_trigger < 0.12f ? 0.0f : t.left_trigger;
            right_trigger = t.right_trigger < 0.12f ? 0.0f : t.right_trigger;
            add(left_trigger > 0.0f, PadButton::L2);
            add(right_trigger > 0.0f, PadButton::R2);
            left_x = t.left_x;
            left_y = -t.left_y;
            right_x = t.right_x;
            right_y = -t.right_y;
        } else {
            const GamepadState& g = gamepad;
            buttons = g.buttons;
            left_x = g.left_x;
            left_y = g.left_y;
            right_x = g.right_x;
            right_y = g.right_y;
            left_trigger = g.left_trigger;
            right_trigger = g.right_trigger;
            real_finger = g.touch_down;
            touch_x = g.touch_x;
            touch_y = g.touch_y;
            if (gamepad_motion) {
                out.pad.has_motion = true;
                std::copy(gamepad_gyro, gamepad_gyro + 3, out.pad.gyro);
                std::copy(gamepad_accel, gamepad_accel + 3, out.pad.accel);
            }
        }

        // What was held down when the game got the controls is not the game's.
        held_back &= buttons;
        buttons &= ~held_back;
        if ((held_back & PadButton::L2) != 0) {
            left_trigger = 0.0f;
        }
        if ((held_back & PadButton::R2) != 0) {
            right_trigger = 0.0f;
        }

        // This title has no use for the right stick, while several of its gadgets want
        // swipes: the stick moves a finger over the touchpad (see Input::StickFinger: a
        // stick let go lifts the finger where it was, which is what lets a pull on the stick
        // shoot the game's catapults).
        bool touching = real_finger;
        if (real_finger) {
            // A real finger is on the pad: the stick's has nothing to say, and is not back
            // on the pad the moment the real one lifts either.
            stick_finger.Reset();
        } else if (stick_touchpad) {
            const Input::StickFinger::Touch dragged = stick_finger.Update(now, right_x, right_y);
            if (dragged.down) {
                touching = true;
                touch_x = dragged.x;
                touch_y = dragged.y;
            }
        }
        if (source == Source::Touch && stick_touchpad) {
            right_x = 0.0f;
            right_y = 0.0f;
        }
        if (!touching && (buttons & PadButton::TouchPad) != 0) {
            // A touchpad cannot be pressed without touching it: in its middle, where a
            // button or a stick pressed in stands in for the press.
            touching = true;
            touch_x = 0.5f;
            touch_y = 0.5f;
        }
        if (touching) {
            sent_touch_x = static_cast<uint16_t>(
                std::clamp(static_cast<int>(std::lround(touch_x * (TouchWidth - 1))), 0,
                           TouchWidth - 1));
            sent_touch_y = static_cast<uint16_t>(
                std::clamp(static_cast<int>(std::lround(touch_y * (TouchHeight - 1))), 0,
                           TouchHeight - 1));
        }

        out.pad.buttons = buttons;
        out.pad.left_x = Stick(left_x);
        out.pad.left_y = Stick(left_y);
        out.pad.right_x = Stick(right_x);
        out.pad.right_y = Stick(right_y);
        out.pad.left_trigger = Trigger(left_trigger);
        out.pad.right_trigger = Trigger(right_trigger);
        out.pad.touch_down = touching;
        // (A finger that lifts does so from where it was.)
        out.pad.touch_x = sent_touch_x;
        out.pad.touch_y = sent_touch_y;
        out.blowing = blow;

        if (!act) {
            return out;
        }
        if ((buttons & PadButton::Cross) != 0 && !seat_taken) {
            // The first press of X is the player settled in, controller in hand, looking at
            // the game: that, and not where they were when the app started, is their seat.
            seat_taken = true;
            recenter |= RecenterSeat;
            Note("first press of X: the player's seat is where they are now");
        }
        if ((buttons & PadButton::Options) == 0) {
            options_since = -1.0;
            options_fired = false;
        } else if (options_since < 0.0) {
            options_since = now;
        } else if (!options_fired && now - options_since >= OptionsHold) {
            // What a PlayStation VR does when OPTIONS is held, and what the game tells its
            // players to do when the view is off. The game still sees the button.
            options_fired = true;
            recenter |= RecenterPad | RecenterSeat;
            Note("OPTIONS held: view reset");
        }
        if (view_reset && !view_reset_held) {
            recenter |= RecenterPad | RecenterSeat;
            Note("both sticks pressed in: view reset");
        }
        view_reset_held = view_reset;
        return out;
    }

    void Publish(double now) {
        const Output out = Compose(now, true);
        if (published && out == last) {
            return;
        }
        published = true;
        last = out;
        if (sink) {
            sink(out);
        }
    }

    // The touchpad as the emulator takes it: the resolution of a DualSense's.
    static constexpr int TouchWidth = 1920;
    static constexpr int TouchHeight = 1080;

    std::mutex mutex;
    std::function<void(const Output&)> sink;
    std::function<void(const char*)> notice;
    bool stick_touchpad{true};

    bool playing{};
    Source source{Source::None};
    bool gamepad_connected{};
    GamepadState gamepad;
    bool gamepad_motion{};
    float gamepad_gyro[3]{};
    float gamepad_accel[3]{0.0f, 9.81f, 0.0f};
    TouchState touch;

    Input::StickFinger stick_finger;
    uint32_t held_back{};
    uint16_t sent_touch_x{TouchWidth / 2};
    uint16_t sent_touch_y{TouchHeight / 2};
    bool seat_taken{};
    double options_since{-1.0};
    bool options_fired{};
    bool view_reset_held{};
    uint32_t recenter{};

    bool published{};
    Output last;
};
