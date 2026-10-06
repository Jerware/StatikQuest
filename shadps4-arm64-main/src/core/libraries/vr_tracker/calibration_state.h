// SPDX-FileCopyrightText: Copyright 2026 shadPS4 Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include "common/types.h"

namespace Libraries::VrTracker {

struct CalibrationState {
    u64 sequence;
    bool active;
    bool reported;
};

inline CalibrationState AdvanceCalibration(const CalibrationState& current, u64 sequence,
                                           bool tracked) {
    return {current.sequence,
            current.active && (!current.reported || !tracked || sequence <= current.sequence),
            true};
}

} // namespace Libraries::VrTracker
