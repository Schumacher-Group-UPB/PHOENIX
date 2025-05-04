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

void PHOENIX::Solver::iterateVariableTimestepCashKarp() {
    bool accept = false;
    do {
        SOLVER_SEQUENCE( false /*Capture CUDA Graph*/,

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

                         INTERMEDIATE_SUM_K( 6, Type::real( 37.0 / 378.0 ), Type::real( 0.0 ), Type::real( 250.0 / 621.0 ), Type::real( 125.0 / 594.0 ), Type::real( 0.0 ), Type::real( 512.0 / 1771.0 ) );

                         ERROR_K( 6, Type::real( 37.0 / 378.0 - 2825.0 / 27648.0 ), Type::real( 0.0 ), Type::real( 250.0 / 621.0 - 18575.0 / 48384.0 ), Type::real( 125.0 / 594.0 - 13525.0 / 55296.0 ), Type::real( 0.0 - 2187.0 / 6784.0 ), Type::real( 512.0 / 1771.0 - 1.0 / 4.0 ) );

        );

        auto msum = matrix.buffer_wavefunction_plus.transformReduce( Type::complex( 0.0 ), CUDAMatrix<Type::complex>::transform_abs2(), CUDAMatrix<Type::complex>::transform_sum() );
        Type::real normalization_factor = CUDA::real( msum );
        Type::real integrated_error = matrix.rk_error.sum();

        Type::real final_error = std::abs( integrated_error / normalization_factor );
        Type::real dh_arg = system.tolerance / 2.0 / CUDA::max( std::numeric_limits<Type::real>::min(), final_error );
        Type::real dh = std::pow<Type::real>( dh_arg, Type::real( 0.25 ) );

        if ( std::isnan( dh ) ) {
            dh = 0.9;
            final_error = std::numeric_limits<Type::real>::max();
        }
        if ( std::isnan( final_error ) ) {
            dh = 0.9;
            final_error = std::numeric_limits<Type::real>::max();
        }

        //  Set new timestep
        Type::real new_dt = std::min( system.p.dt * dh, system.dt_max );
        if ( new_dt < system.dt_min ) {
            new_dt = system.dt_min;
            accept = true;
        }
        system.p.dt = new_dt;

        updateKernelTime();

        if ( final_error < system.tolerance ) {
            accept = true;
            matrix.wavefunction_plus.swap( matrix.buffer_wavefunction_plus );
            matrix.reservoir_plus.swap( matrix.buffer_reservoir_plus );
            if ( system.use_twin_mode ) {
                matrix.wavefunction_minus.swap( matrix.buffer_wavefunction_minus );
                matrix.reservoir_minus.swap( matrix.buffer_reservoir_minus );
            }
        }

    } while ( !accept );
}