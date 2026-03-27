#pragma once
#include <atomic>
#include <mutex>
#include <condition_variable>
#include <cstddef>

namespace PHOENIX {

struct SolverThreadState {
    // Control flags (GUI writes, solver reads)
    std::atomic<bool>   paused  { false };
    std::atomic<bool>   stop    { false };

    // Set by the solver thread when it is actually blocked in pause_cv.wait().
    // GUI can spin-wait on this before writing host matrices.
    std::atomic<bool>   solver_actually_paused { false };

    // Pause notification - solver blocks here when paused
    std::mutex              pause_mutex;
    std::condition_variable pause_cv;

    // Protects host matrix data: solver holds during syncDisplayMatrices/cacheValues/cacheMatrices,
    // GUI holds during updatePanel/blitPanel
    std::mutex              display_mutex;

    // Display scalars - solver writes, GUI reads
    std::atomic<double> display_t         { 0.0 };
    std::atomic<size_t> display_iteration { 0   };
    std::atomic<double> display_elapsed   { 0.0 };
};

} // namespace PHOENIX
