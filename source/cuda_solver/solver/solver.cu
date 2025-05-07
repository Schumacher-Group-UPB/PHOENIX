#include <omp.h>

// Include Cuda Kernel headers
#include "cuda/typedef.cuh"
#include "kernel/kernel_compute.cuh"
#include "system/system_parameters.hpp"
#include "cuda/cuda_matrix.cuh"
#include "solver/solver.hpp"
#include "misc/commandline_io.hpp"

namespace PHOENIX {

/*
* Helper variable for caching the current time for FFT evaluations.
* We dont need this variable anywhere else, so we just create it
* locally to this file here.
*/
// TODO: Make these member variables of the solver class
PHOENIX::Type::real fft_cached_t = 0.0;
bool first_time = true;

bool Solver::iterate( bool force_fixed_time_step ) {
    if ( system.use_adaptive_timestep && system.use_adaptive_timestep != is_adaptive_ ) {
        std::cout << CLIO::prettyPrint( "Cannot use variable time step with this solver.", CLIO::Control::Error ) << std::endl;
        system.use_adaptive_timestep = false;
    }

    // Check if the maximum time has been reached
#ifndef BENCH
    if ( system.p.t >= system.t_max )
        return false;
#endif

    // If required, calculate new set of random numbers.
    // TODO: move this back into subgrids, because for large number of subgrids this will look very correlated!
    if ( system.evaluateStochastic() ) {
        auto args = generateKernelArguments();
        auto [block_size, grid_size] = getLaunchParameters( 1, system.p.subgrid_N2_with_halo );
        if ( first_time ) {
            first_time = false;
            CALL_FULL_KERNEL( Kernel::initialize_random_number_generator, "random_number_init", grid_size, block_size, 0, system.random_seed, args.dev_ptrs.random_state, system.p.subgrid_N2_with_halo );
            std::cout << CLIO::prettyPrint( "Initialized Random Number Generator", CLIO::Control::Info ) << std::endl;
        }
        CALL_FULL_KERNEL( Kernel::generate_random_numbers, "random_number_gen", grid_size, block_size, 0, args.dev_ptrs.random_state, args.dev_ptrs.random_number, system.p.subgrid_N2_with_halo, system.p.stochastic_amplitude * std::sqrt( system.p.dt ), system.p.stochastic_amplitude * std::sqrt( system.p.dt ) );
    }

    updateKernelTime();

    // Increase t.
    system.p.t = system.p.t + system.p.dt;

    // Iterate the solver
    step( system.use_adaptive_timestep && !force_fixed_time_step );
    // Call the normalization for imaginary time propagation if required
    if ( system.imag_time_amplitude != 0.0 )
        normalizeImaginaryTimePropagation();

    // For statistical purposes, increase the iteration counter
    system.iteration++;

    // FFT Guard
    if ( system.p.t - fft_cached_t < system.fft_every )
        return true;

    // Calculate the FFT
    fft_cached_t = system.p.t;
    applyFFTFilter( system.fft_mask.size() > 0 );

    return true;
}

bool Solver::adaptTimeStep( const Type::real power, bool use_discrete_update_steps ) {
    auto msum = matrix.buffer_wavefunction_plus.transformReduce( Type::complex( 0.0 ), CUDAMatrix<Type::complex>::transform_abs2(), CUDAMatrix<Type::complex>::transform_sum() );
    Type::real normalization_factor = CUDA::real( msum );
    Type::real integrated_error = matrix.rk_error.sum();

    Type::real final_error = std::abs( integrated_error / normalization_factor );
    Type::real dh_arg = system.tolerance / 2.0 / CUDA::max( std::numeric_limits<Type::real>::min(), final_error );
    Type::real dh = std::pow<Type::real>( dh_arg, Type::real( power ) );

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
    }
    system.p.dt = new_dt;
    
    updateKernelTime();

    if (final_error < system.tolerance) {
        // Accept the solution and set the new time step
        return true;
    }
    
    return false;
}

void Solver::swapBuffers() {
    matrix.wavefunction_plus.swap( matrix.buffer_wavefunction_plus );
    matrix.reservoir_plus.swap( matrix.buffer_reservoir_plus );
    if ( system.use_twin_mode ) {
        matrix.wavefunction_minus.swap( matrix.buffer_wavefunction_minus );
        matrix.reservoir_minus.swap( matrix.buffer_reservoir_minus );
    }
}

} // namespace PHOENIX