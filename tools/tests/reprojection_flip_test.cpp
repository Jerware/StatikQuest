#include <cassert>
#include <cstdio>
#include "core/libraries/videoout/reprojection_flip.h"

int main() {
    Libraries::VideoOut::ReprojectionFlip flip;
    assert(!flip.Refresh()); // No completed frame, including a queued-but-unfinished frame.
    assert(!flip.Refresh());
    flip.Presented(false);
    assert(!flip.Refresh());
    assert(!flip.Refresh()); // Ordinary TV flips must not be repeated.
    flip.Presented(true);
    assert(!flip.Refresh()); // The new frame has already sent its notification.
    assert(flip.Refresh());  // WipEout needs this second display event to draw again.
    assert(flip.Refresh());  // The display keeps refreshing even if the guest stalls.
    flip.Presented(true);
    assert(!flip.Refresh());
    assert(flip.Refresh());
    flip.Presented(true);
    flip.Presented(true);
    assert(!flip.Refresh()); // Multiple early deliveries still suppress the duplicate.
    assert(flip.Refresh());
    flip.Presented(false);
    assert(!flip.Refresh());
    assert(!flip.Refresh()); // Returning to TV output stops HMD repetitions.
    flip.Presented(true);
    flip.Reset();
    assert(!flip.Refresh());
    assert(!flip.Refresh()); // Closing and reopening cannot repeat a stale frame.
    std::puts("reprojection_flip: all checks passed");
}
