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

void PHOENIX::Solver::iterateFixedTimestepBogacki() {
    SOLVER_SEQUENCE( true /*Capture CUDA Graph*/,

                     CALCULATE_K( 1, Type::real( 0.0 ), wavefunction, reservoir );

                     INTERMEDIATE_SUM_K( 1, Type::real( 1.0 / 2.0 ) );

                     CALCULATE_K( 2, Type::real( 1.0 / 2.0 ), buffer_wavefunction, buffer_reservoir );

                     INTERMEDIATE_SUM_K( 2, Type::real( 0.0 ), Type::real( 3.0 / 9.0 ) );

                     CALCULATE_K( 3, Type::real( 3.0 / 4.0 ), buffer_wavefunction, buffer_reservoir );

                     FINAL_SUM_K( 3, Type::real( 2.0 / 9.0 ), Type::real( 1.0 / 3.0 ), Type::real( 4.0 / 9.0 ) );

    );
}

void PHOENIX::Solver::iterateVariableTimestepBogacki() {
    bool accept = false;
    do {
        SOLVER_SEQUENCE( false /*Capture CUDA Graph*/,

                         CALCULATE_K( 1, Type::real( 0.0 ), wavefunction, reservoir );

                         INTERMEDIATE_SUM_K( 1, Type::real( 1.0 / 2.0 ) );

                         CALCULATE_K( 2, Type::real( 1.0 / 2.0 ), buffer_wavefunction, buffer_reservoir );

                         INTERMEDIATE_SUM_K( 2, Type::real( 0.0 ), Type::real( 3.0 / 9.0 ) );

                         CALCULATE_K( 3, Type::real( 3.0 / 4.0 ), buffer_wavefunction, buffer_reservoir );

                         INTERMEDIATE_SUM_K( 3, Type::real( 2.0 / 9.0 ), Type::real( 1.0 / 3.0 ), Type::real( 4.0 / 9.0 ) );

                         // We need the 4th K for the error estimate
                         CALCULATE_K( 4, Type::real( 1.0 ), buffer_wavefunction, buffer_reservoir );

                         ERROR_K( 4, Type::real( 2.0 / 9.0 - 7.0 / 24.0 ), Type::real( 1.0 / 3.0 - 1.0 / 4.0 ), Type::real( 4.0 / 9.0 - 1.0 / 3.0 ), Type::real( 0.0 - 1.0 / 8.0 ) );

                         // Redo this sum so we get the correct solution in buffer_...
                         INTERMEDIATE_SUM_K( 3, Type::real( 2.0 / 9.0 ), Type::real( 1.0 / 3.0 ), Type::real( 4.0 / 9.0 ) ); );

        auto msum = matrix.buffer_wavefunction_plus.transformReduce( Type::complex( 0.0 ), CUDAMatrix<Type::complex>::transform_abs2(), CUDAMatrix<Type::complex>::transform_sum() );
        Type::real normalization_factor = CUDA::real( msum );
        Type::real integrated_error = matrix.rk_error.sum();

        Type::real final_error = std::abs( integrated_error / normalization_factor );
        Type::real dh_arg = system.tolerance / 2.0 / CUDA::max( std::numeric_limits<Type::real>::min(), final_error );
        Type::real dh = std::pow<Type::real>( dh_arg, Type::real( 1.0 / 4.0 ) );

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