#include <cstdlib>
#include <iostream>

#include "core/libraries/vr_tracker/calibration_state.h"

using namespace Libraries::VrTracker;

void Check(bool condition, const char *what) {
  if (!condition) {
    std::cerr << "FAIL: " << what << '\n';
    std::exit(1);
  }
}

int main() {
  const CalibrationState requested{42, true, false};
  const auto first = AdvanceCalibration(requested, 43, true);
  Check(first.active && first.reported,
        "pending is reported even if a new pose already arrived");
  const auto stale = AdvanceCalibration(first, 42, true);
  Check(stale.active, "the pre-request sample cannot complete calibration");
  Check(AdvanceCalibration(first, 41, true).active,
        "an older sample cannot complete calibration");
  const auto lost = AdvanceCalibration(first, 44, false);
  Check(lost.active, "untracked poses cannot complete calibration");
  const auto complete = AdvanceCalibration(lost, 45, true);
  Check(!complete.active, "a new tracked pose completes calibration");
  Check(!AdvanceCalibration(complete, 45, true).active,
        "completed calibration stays completed");
  const CalibrationState again{45, true, false};
  Check(AdvanceCalibration(again, 46, true).active,
        "a repeated request reports pending again");
  std::cout << "PASS: calibration lifecycle, stale samples and tracking loss\n";
}
