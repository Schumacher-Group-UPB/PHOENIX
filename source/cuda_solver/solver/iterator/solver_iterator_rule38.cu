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

void PHOENIX::Solver::iterateFixedTimestepRule38() {
    SOLVER_SEQUENCE( true /*Capture CUDA Graph*/,

                     CALCULATE_K( 1, wavefunction, reservoir );

                     INTERMEDIATE_SUM_K( 1, Type::real( 1.0 / 3.0 ) );

                     CALCULATE_K( 2, buffer_wavefunction, buffer_reservoir );

                     INTERMEDIATE_SUM_K( 2, Type::real( -1.0 / 3.0 ), Type::real( 1.0 ) );

                     CALCULATE_K( 3, buffer_wavefunction, buffer_reservoir );

                     INTERMEDIATE_SUM_K( 3, Type::real( 1.0 ), Type::real( -1.0 ), Type::real( 1.0 ) );

                     CALCULATE_K( 4, buffer_wavefunction, buffer_reservoir );

                     FINAL_SUM_K( 4, Type::real( 1.0 / 8.0 ), Type::real( 3.0 / 8.0 ), Type::real( 3.0 / 8.0 ), Type::real( 1.0 / 8.0 ) );

    );
}
