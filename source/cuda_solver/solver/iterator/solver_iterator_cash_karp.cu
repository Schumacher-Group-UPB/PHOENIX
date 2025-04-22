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

void PHOENIX::Solver::iterateFixedTimestepCashKarp() {
    SOLVER_SEQUENCE( true /*Capture CUDA Graph*/,

                     CALCULATE_K( 1, Type::real( 0.0 ), wavefunction, reservoir );

                     INTERMEDIATE_SUM_K( 1, Type::real( 1.0 / 5.0 ) );

                     CALCULATE_K( 2, Type::real( 1.0 / 5.0 ), buffer_wavefunction, buffer_reservoir );

                     INTERMEDIATE_SUM_K( 2, Type::real( 3.0 / 40.0 ), Type::real( 9.0 / 40.0 ) );

                     CALCULATE_K( 3, Type::real( 3.0 / 10.0 ), buffer_wavefunction, buffer_reservoir );

                     INTERMEDIATE_SUM_K( 3, Type::real( 3.0 / 1.0 ), Type::real( -9.0 / 10.0 ), Type::real( 6.0 / 5.0 ) );

                     CALCULATE_K( 4, Type::real( 3.0 / 5.0 ), buffer_wavefunction, buffer_reservoir );

                     INTERMEDIATE_SUM_K( 4, Type::real( -11.0 / 54.0 ), Type::real( 5.0 / 2.0 ), Type::real( -70.0 / 27.0 ), Type::real( 35.0 / 27.0 ) );

                     CALCULATE_K( 5, Type::real( 1.0 ), buffer_wavefunction, buffer_reservoir );

                     INTERMEDIATE_SUM_K( 5, Type::real( 1631.0 / 55296.0 ), Type::real( 175.0 / 512.0 ), Type::real( 575.0 / 13824.0 ), Type::real( 44275.0 / 110592.0 ), Type::real( 253.0 / 4096.0 ) );

                     CALCULATE_K( 6, Type::real( 7.0 / 8.0 ), buffer_wavefunction, buffer_reservoir );

                     FINAL_SUM_K( 6, Type::real( 37.0 / 378.0 ), Type::real( 0.0 ), Type::real( 250.0 / 621.0 ), Type::real( 125.0 / 594.0 ), Type::real( 0.0 ), Type::real( 512.0 / 1771.0 ) );

    );
}
