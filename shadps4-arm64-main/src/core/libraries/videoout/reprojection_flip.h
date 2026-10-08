// SPDX-FileCopyrightText: Copyright 2026 shadPS4 Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

namespace Libraries::VideoOut {

// Used by the present thread. Queuing a frame does not count as presenting it.
class ReprojectionFlip {
public:
    void Presented(bool is_hmd) {
        last_flip_is_hmd = is_hmd;
        flipped_since_refresh = true;
    }

    bool Refresh() {
        const bool repeat = last_flip_is_hmd && !flipped_since_refresh;
        flipped_since_refresh = false;
        return repeat;
    }

    void Reset() {
        last_flip_is_hmd = false;
        flipped_since_refresh = false;
    }

private:
    bool last_flip_is_hmd = false;
    bool flipped_since_refresh = false;
};

} // namespace Libraries::VideoOut
