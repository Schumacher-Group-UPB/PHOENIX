#include <omp.h>

// Include Cuda Kernel headers
#include "cuda/typedef.cuh"
#include "kernel/kernel_compute.cuh"
#include "system/system_parameters.hpp"
#include "cuda/cuda_matrix.cuh"
#include "solver/solver.hpp"
#include "misc/commandline_io.hpp"

void PHOENIX::Solver::updateKernelTime() {
    // Update the time struct. This is required for variable time steps, and when the kernels need t or dt.
    Type::host_vector<Type::real> new_time = { system.p.t, system.p.dt };
    time = new_time;
    // And update the solver struct accordingly
    system.pulse.updateTemporal( system.p.t );
    system.potential.updateTemporal( system.p.t );
    system.pump.updateTemporal( system.p.t );
    dev_pulse_oscillation.amp = system.pulse.temporal_envelope;
    dev_potential_oscillation.amp = system.potential.temporal_envelope;
    dev_pump_oscillation.amp = system.pump.temporal_envelope;
    system.pulse.updateTemporal( system.p.t + system.p.dt );
    system.potential.updateTemporal( system.p.t + system.p.dt );
    system.pump.updateTemporal( system.p.t + system.p.dt );
    dev_pulse_oscillation.amp_next = system.pulse.temporal_envelope;
    dev_potential_oscillation.amp_next = system.potential.temporal_envelope;
    dev_pump_oscillation.amp_next = system.pump.temporal_envelope;
}