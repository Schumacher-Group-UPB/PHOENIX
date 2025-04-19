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

void PHOENIX::Solver::iterateFixedTimestepNystroem() {
    SOLVER_SEQUENCE( true /*Capture CUDA Graph*/,

                     CALCULATE_K( 1, wavefunction, reservoir );

                     INTERMEDIATE_SUM_K( 1, Type::real( 1.0 / 3.0 ) );

                     CALCULATE_K( 2, buffer_wavefunction, buffer_reservoir );

                     INTERMEDIATE_SUM_K( 2, Type::real( 4.0 / 25.0 ), Type::real( 6.0 / 25.0 ) );

                     CALCULATE_K( 3, buffer_wavefunction, buffer_reservoir );

                     INTERMEDIATE_SUM_K( 3, Type::real( 1.0 / 4.0 ), Type::real( -3.0 ), Type::real( 15.0 / 4.0 ) );

                     CALCULATE_K( 4, buffer_wavefunction, buffer_reservoir );

                     INTERMEDIATE_SUM_K( 4, Type::real( 2.0 / 27.0 ), Type::real( 10.0 / 9.0 ), -Type::real( 50.0 / 81.0 ), Type::real( 8.0 / 81.0 ) );

                     CALCULATE_K( 5, buffer_wavefunction, buffer_reservoir );

                     INTERMEDIATE_SUM_K( 5, Type::real( 2.0 / 25.0 ), Type::real( 12.0 / 25.0 ), Type::real( 2.0 / 15.0 ), Type::real( 8.0 / 75.0 ) );

                     CALCULATE_K( 6, buffer_wavefunction, buffer_reservoir );

                     FINAL_SUM_K( 6, Type::real( 23.0 / 192.0 ), Type::real( 0.0 ), Type::real( 125.0 / 192.0 ), Type::real( 0.0 ), -Type::real( 27.0 / 64.0 ), Type::real( 125.0 / 192.0 ) );

    );
}
