#include <omp.h>

// Include Cuda Kernel headers
#include "cuda/typedef.cuh"
#include "kernel/kernel_compute.cuh"
#include "kernel/kernel_summation.cuh"
#include "kernel/kernel_halo.cuh"
#include "system/system_parameters.hpp"
#include "cuda/cuda_matrix.cuh"
#include "solver/gpu_solver.hpp"
#include "misc/commandline_io.hpp"


void PHOENIX::Solver::iterateFixedTimestepExplicitMidpoint() {
    SOLVER_SEQUENCE( true /*Capture CUDA Graph*/,

                     CALCULATE_K( 1, wavefunction, reservoir );

                     INTERMEDIATE_SUM_K( 1, Type::real(0.5f) );

                     CALCULATE_K( 2, buffer_wavefunction, buffer_reservoir );

                     FINAL_SUM_K( 2, Type::real(0.0f), Type::real(1.0f) );

    );
}
