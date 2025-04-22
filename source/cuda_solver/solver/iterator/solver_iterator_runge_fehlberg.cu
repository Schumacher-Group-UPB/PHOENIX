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

void PHOENIX::Solver::iterateFixedTimestepFehlberg2() {
    SOLVER_SEQUENCE( true /*Capture CUDA Graph*/,

                     CALCULATE_K( 1, Type::real( 0.0 ), wavefunction, reservoir );

                     INTERMEDIATE_SUM_K( 1, Type::real( 1.0 / 2.0 ) );

                     CALCULATE_K( 2, Type::real( 1.0 / 2.0 ), buffer_wavefunction, buffer_reservoir );

                     INTERMEDIATE_SUM_K( 2, Type::real( 1.0 / 256.0 ), Type::real( 255.0 / 256.0 ) );

                     CALCULATE_K( 3, Type::real( 1.0 ), buffer_wavefunction, buffer_reservoir );

                     FINAL_SUM_K( 3, Type::real( 1.0 / 512.0 ), Type::real( 255.0 / 256.0 ), Type::real( 1.0 / 512.0 ) );

    );
}

void PHOENIX::Solver::iterateVariableTimestepFehlberg2() {
    bool accept = false;
    do {
        SOLVER_SEQUENCE( false /*Capture CUDA Graph*/,

                         CALCULATE_K( 1, Type::real( 0.0 ), wavefunction, reservoir );

                         INTERMEDIATE_SUM_K( 1, Type::real( 1.0 / 2.0 ) );

                         CALCULATE_K( 2, Type::real( 1.0 / 2.0 ), buffer_wavefunction, buffer_reservoir );

                         INTERMEDIATE_SUM_K( 2, Type::real( 1.0 / 256.0 ), Type::real( 255.0 / 256.0 ) );

                         CALCULATE_K( 3, Type::real( 1.0 ), buffer_wavefunction, buffer_reservoir );

                         INTERMEDIATE_SUM_K( 3, Type::real( 1.0 / 512.0 ), Type::real( 255.0 / 256.0 ), Type::real( 1.0 / 512.0 ) );

                         ERROR_K( 3, Type::real( 1.0 / 512.0 - 1.0 / 256.0 ), Type::real( 0.0 ), Type::real( 1.0 / 512.0 ) ); );

        auto msum = matrix.buffer_wavefunction_plus.transformReduce( Type::complex( 0.0 ), CUDAMatrix<Type::complex>::transform_abs2(), CUDAMatrix<Type::complex>::transform_sum() );
        Type::real normalization_factor = CUDA::sqrt( CUDA::real( msum ) );
        Type::real integrated_error = std::sqrt( matrix.rk_error.sum() );

        Type::real final_error = std::abs( integrated_error / normalization_factor );
        Type::real dh_arg = system.tolerance / 2.0 / CUDA::max( std::numeric_limits<Type::real>::min(), final_error );
        Type::real dh = std::pow<Type::real>( dh_arg, Type::real( 0.5 ) );

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

void PHOENIX::Solver::iterateFixedTimestepFehlberg5() {
    SOLVER_SEQUENCE( true /*Capture CUDA Graph*/,

                     CALCULATE_K( 1, Type::real( 0.0 ), wavefunction, reservoir );

                     INTERMEDIATE_SUM_K( 1, Type::real( 1.0 / 40.0 ) );

                     CALCULATE_K( 2, Type::real( 1.0 / 4.0 ), buffer_wavefunction, buffer_reservoir );

                     INTERMEDIATE_SUM_K( 2, Type::real( 3.0 / 32.0 ), Type::real( 9.0 / 32.0 ) );

                     CALCULATE_K( 3, Type::real( 3.0 / 8.0 ), buffer_wavefunction, buffer_reservoir );

                     INTERMEDIATE_SUM_K( 3, Type::real( 1932.0 / 2197.0 ), Type::real( -7200.0 / 2197.0 ), Type::real( 7296.0 / 2197.0 ) );

                     CALCULATE_K( 4, Type::real( 12.0 / 13.0 ), buffer_wavefunction, buffer_reservoir );

                     INTERMEDIATE_SUM_K( 4, Type::real( 439.0 / 216.0 ), Type::real( -8.0 ), Type::real( 3680.0 / 513.0 ), Type::real( -845.0 / 4104.0 ) );

                     CALCULATE_K( 5, Type::real( 1.0 ), buffer_wavefunction, buffer_reservoir );

                     INTERMEDIATE_SUM_K( 5, Type::real( -8.0 / 27.0 ), Type::real( 2.0 ), Type::real( -3544.0 / 2565.0 ), Type::real( 1859.0 / 4104.0 ), Type::real( -11.0 / 40.0 ) );

                     CALCULATE_K( 6, Type::real( 1.0 / 2.0 ), buffer_wavefunction, buffer_reservoir );

                     FINAL_SUM_K( 6, Type::real( 16.0 / 135.0 ), Type::real( 0.0 ), Type::real( 6656.0 / 12825.0 ), Type::real( 28561.0 / 56430.0 ), Type::real( -9.0 / 50.0 ), Type::real( 2.0 / 55.0 ) );

    );
}

void PHOENIX::Solver::iteratevariableTimestepFehlberg5() {
    bool accept = false;
    do {
        SOLVER_SEQUENCE( false /*Capture CUDA Graph*/,

                         CALCULATE_K( 1, Type::real( 0.0 ), wavefunction, reservoir );

                         INTERMEDIATE_SUM_K( 1, Type::real( 1.0 / 40.0 ) );

                         CALCULATE_K( 2, Type::real( 1.0 / 4.0 ), buffer_wavefunction, buffer_reservoir );

                         INTERMEDIATE_SUM_K( 2, Type::real( 3.0 / 32.0 ), Type::real( 9.0 / 32.0 ) );

                         CALCULATE_K( 3, Type::real( 3.0 / 8.0 ), buffer_wavefunction, buffer_reservoir );

                         INTERMEDIATE_SUM_K( 3, Type::real( 1932.0 / 2197.0 ), Type::real( -7200.0 / 2197.0 ), Type::real( 7296.0 / 2197.0 ) );

                         CALCULATE_K( 4, Type::real( 12.0 / 13.0 ), buffer_wavefunction, buffer_reservoir );

                         INTERMEDIATE_SUM_K( 4, Type::real( 439.0 / 216.0 ), Type::real( -8.0 ), Type::real( 3680.0 / 513.0 ), Type::real( -845.0 / 4104.0 ) );

                         CALCULATE_K( 5, Type::real( 1.0 ), buffer_wavefunction, buffer_reservoir );

                         INTERMEDIATE_SUM_K( 5, Type::real( -8.0 / 27.0 ), Type::real( 2.0 ), Type::real( -3544.0 / 2565.0 ), Type::real( 1859.0 / 4104.0 ), Type::real( -11.0 / 40.0 ) );

                         CALCULATE_K( 6, Type::real( 1.0 / 2.0 ), buffer_wavefunction, buffer_reservoir );

                         // Write result to buffer_ instead of wavefunction_
                         INTERMEDIATE_SUM_K( 6, Type::real( 16.0 / 135.0 ), Type::real( 0.0 ), Type::real( 6656.0 / 12825.0 ), Type::real( 28561.0 / 56430.0 ), Type::real( -9.0 / 50.0 ), Type::real( 2.0 / 55.0 ) );
                         //FINAL_SUM_K( 6, Type::real( 16.0 / 135.0 ), Type::real( 0.0 ), Type::real( 6656.0 / 12825.0 ), Type::real( 28561.0 / 56430.0 ), Type::real( -9.0 / 50.0 ), Type::real( 2.0 / 55.0 ) );

                         // Calculate the error. If the error is small enough, accept the step and move buffer_ into wavefunction_.
                         ERROR_K( 6, Type::real( 16.0 / 135.0 - 25.0 / 216.0 ), Type::real( 0.0 ), Type::real( 6656.0 / 12825.0 - 1408.0 / 2565.0 ), Type::real( 28561.0 / 56430.0 - 2197.0 / 4104.0 ), Type::real( -9.0 / 50.0 - 1.0 / 5.0 ), Type::real( 2.0 / 55.0 ) );

        );

        //auto [min, max] = matrix.buffer_wavefunction_plus.extrema();
        auto msum = matrix.buffer_wavefunction_plus.transformReduce( Type::complex( 0.0 ), CUDAMatrix<Type::complex>::transform_abs2(), CUDAMatrix<Type::complex>::transform_sum() );
        Type::real normalization_factor = CUDA::sqrt( CUDA::real( msum ) );
        Type::real integrated_error = std::sqrt( matrix.rk_error.sum() );

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
        //if ( dh < 1.0 )
        //new_dt = std::max( system.p.dt - system.dt_min * std::floor( 1.0 / dh ), system.dt_min );
        //else
        //new_dt = std::min( system.p.dt + system.dt_min * std::floor( dh ), system.dt_max );
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
            //std::cout << "ACCEPTED " << final_error << ", norm = " << normalization_factor << ", dh = " << dh << " --> new dt = " << new_dt << " (old: " << system.p.dt << ")" << std::endl;
        }

        //std::cout << final_error << ", norm = " << normalization_factor << ", dh = " << dh << " --> new dt = " << new_dt << " (old: " << system.p.dt << ")" << std::endl;
    } while ( !accept );
}