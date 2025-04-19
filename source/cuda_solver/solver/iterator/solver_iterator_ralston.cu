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

void PHOENIX::Solver::iterateFixedTimestepRalston() {
    SOLVER_SEQUENCE( true /*Capture CUDA Graph*/,

                     CALCULATE_K( 1, wavefunction, reservoir );

                     INTERMEDIATE_SUM_K( 1, Type::real( 2.0 / 3.0 ) );

                     CALCULATE_K( 2, buffer_wavefunction, buffer_reservoir );

                     FINAL_SUM_K( 2, Type::real( 1.0 / 4.0 ), Type::real( 3.0 / 4.0 ) );

    );
}

void PHOENIX::Solver::iterateFixedTimestepRalston3() {
    SOLVER_SEQUENCE( true /*Capture CUDA Graph*/,

                     CALCULATE_K( 1, wavefunction, reservoir );

                     INTERMEDIATE_SUM_K( 1, Type::real( 1.0 / 2.0 ) );

                     CALCULATE_K( 2, buffer_wavefunction, buffer_reservoir );

                     INTERMEDIATE_SUM_K( 2, Type::real( 0.0 ), Type::real( 3.0 / 4.0 ) );

                     CALCULATE_K( 3, buffer_wavefunction, buffer_reservoir );

                     FINAL_SUM_K( 3, Type::real( 2.0 / 9.0 ), Type::real( 1.0 / 3.0 ), Type::real( 4.0 / 9.0 ) );

    );
}

void PHOENIX::Solver::iterateFixedTimestepRalston4() {
    SOLVER_SEQUENCE( true /*Capture CUDA Graph*/,

                     CALCULATE_K( 1, wavefunction, reservoir );

                     INTERMEDIATE_SUM_K( 1, Type::real( 0.4 ) );

                     CALCULATE_K( 2, buffer_wavefunction, buffer_reservoir );

                     INTERMEDIATE_SUM_K( 2, Type::real( 0.29697760924 ), Type::real( 0.15875964497 ) );

                     CALCULATE_K( 3, buffer_wavefunction, buffer_reservoir );

                     INTERMEDIATE_SUM_K( 3, Type::real( 0.21810038822 ), Type::real( -3.05096514869 ), Type::real( 3.83286476047 ) );

                     CALCULATE_K( 4, buffer_wavefunction, buffer_reservoir );

                     FINAL_SUM_K( 4, Type::real( 0.17476028226 ), Type::real( -0.55148066287 ), Type::real( 1.2055355994 ), Type::real( 0.17118478122 ) );

    );
}
