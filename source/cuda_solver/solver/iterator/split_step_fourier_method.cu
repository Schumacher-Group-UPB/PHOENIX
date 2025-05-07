#include <omp.h>
#include "cuda/typedef.cuh"
#include "kernel/kernel_compute.cuh"
#include "kernel/kernel_summation.cuh"
#include "kernel/kernel_halo.cuh"
#include "system/system_parameters.hpp"
#include "cuda/cuda_matrix.cuh"
#include "solver/iterator/ssfm.cuh"
#include "solver/solver_factory.hpp"

namespace PHOENIX {

SSFM::SSFM( SystemParameters& system ) : Solver( system ) {
    k_max_ = 0;
    halo_size_ = 0;
    is_adaptive_ = false;
    name_ = "SSFM";
    description_ = "Split Step Fourier Method";
    butcher_tableau_ = "Not a Runge-Kutta method";
}

/**
 * Split Step Fourier Method
 */
void SSFM::step( bool variable_time_step ) {
    auto kernel_arguments = generateKernelArguments();
    auto [block_size, grid_size] = getLaunchParameters( system.p.N_c, system.p.N_r );
    // Liner Half Step
    // Calculate the FFT of Psi
    calculateFFT( kernel_arguments.dev_ptrs.wavefunction_plus, kernel_arguments.dev_ptrs.fft_plus, FFT::forward );
    if ( system.use_twin_mode )
        calculateFFT( kernel_arguments.dev_ptrs.wavefunction_minus, kernel_arguments.dev_ptrs.fft_minus, FFT::forward );
    if ( system.use_twin_mode ) {
        CALL_FULL_KERNEL( Kernel::Compute::gp_scalar_linear_fourier<true>, "linear_half_step", grid_size, block_size, 0, kernel_arguments, { kernel_arguments.dev_ptrs.fft_plus, kernel_arguments.dev_ptrs.fft_minus, kernel_arguments.dev_ptrs.discard, kernel_arguments.dev_ptrs.discard, kernel_arguments.dev_ptrs.wavefunction_plus, kernel_arguments.dev_ptrs.wavefunction_minus, kernel_arguments.dev_ptrs.discard, kernel_arguments.dev_ptrs.discard } );
    } else {
        CALL_FULL_KERNEL( Kernel::Compute::gp_scalar_linear_fourier<false>, "linear_half_step", grid_size, block_size, 0, kernel_arguments, { kernel_arguments.dev_ptrs.fft_plus, kernel_arguments.dev_ptrs.fft_minus, kernel_arguments.dev_ptrs.discard, kernel_arguments.dev_ptrs.discard, kernel_arguments.dev_ptrs.wavefunction_plus, kernel_arguments.dev_ptrs.wavefunction_minus, kernel_arguments.dev_ptrs.discard, kernel_arguments.dev_ptrs.discard } );
    }
    // Transform back. WF now holds the half-stepped wavefunction.
    calculateFFT( kernel_arguments.dev_ptrs.wavefunction_plus, kernel_arguments.dev_ptrs.fft_plus, FFT::inverse );
    if ( system.use_twin_mode )
        calculateFFT( kernel_arguments.dev_ptrs.wavefunction_minus, kernel_arguments.dev_ptrs.fft_minus, FFT::inverse );

    // Nonlinear Full Step
    if ( system.use_twin_mode ) {
        CALL_FULL_KERNEL( Kernel::Compute::gp_scalar_nonlinear<true>, "nonlinear_full_step", grid_size, block_size, 0, kernel_arguments, { kernel_arguments.dev_ptrs.fft_plus, kernel_arguments.dev_ptrs.fft_minus, kernel_arguments.dev_ptrs.reservoir_plus, kernel_arguments.dev_ptrs.reservoir_minus, kernel_arguments.dev_ptrs.wavefunction_plus, kernel_arguments.dev_ptrs.wavefunction_minus, kernel_arguments.dev_ptrs.buffer_reservoir_plus, kernel_arguments.dev_ptrs.buffer_reservoir_minus } );
    } else {
        CALL_FULL_KERNEL( Kernel::Compute::gp_scalar_nonlinear<false>, "nonlinear_full_step", grid_size, block_size, 0, kernel_arguments, { kernel_arguments.dev_ptrs.fft_plus, kernel_arguments.dev_ptrs.fft_minus, kernel_arguments.dev_ptrs.reservoir_plus, kernel_arguments.dev_ptrs.reservoir_minus, kernel_arguments.dev_ptrs.wavefunction_plus, kernel_arguments.dev_ptrs.wavefunction_minus, kernel_arguments.dev_ptrs.buffer_reservoir_plus, kernel_arguments.dev_ptrs.buffer_reservoir_minus } );
    }
    // WF now holds the nonlinearly evolved wavefunction.

    // Liner Half Step
    // Calculate the FFT of Psi
    calculateFFT( kernel_arguments.dev_ptrs.wavefunction_plus, kernel_arguments.dev_ptrs.fft_plus, FFT::forward );
    if ( system.use_twin_mode )
        calculateFFT( kernel_arguments.dev_ptrs.wavefunction_minus, kernel_arguments.dev_ptrs.fft_minus, FFT::forward );
    if ( system.use_twin_mode ) {
        CALL_FULL_KERNEL( Kernel::Compute::gp_scalar_linear_fourier<true>, "linear_half_step", grid_size, block_size, 0, kernel_arguments, { kernel_arguments.dev_ptrs.fft_plus, kernel_arguments.dev_ptrs.fft_minus, kernel_arguments.dev_ptrs.discard, kernel_arguments.dev_ptrs.discard, kernel_arguments.dev_ptrs.wavefunction_plus, kernel_arguments.dev_ptrs.wavefunction_minus, kernel_arguments.dev_ptrs.discard, kernel_arguments.dev_ptrs.discard } );
    } else {
        CALL_FULL_KERNEL( Kernel::Compute::gp_scalar_linear_fourier<false>, "linear_half_step", grid_size, block_size, 0, kernel_arguments, { kernel_arguments.dev_ptrs.fft_plus, kernel_arguments.dev_ptrs.fft_minus, kernel_arguments.dev_ptrs.discard, kernel_arguments.dev_ptrs.discard, kernel_arguments.dev_ptrs.wavefunction_plus, kernel_arguments.dev_ptrs.wavefunction_minus, kernel_arguments.dev_ptrs.discard, kernel_arguments.dev_ptrs.discard } );
    }
    // Transform back. WF now holds the half-stepped wavefunction.
    calculateFFT( kernel_arguments.dev_ptrs.wavefunction_plus, kernel_arguments.dev_ptrs.fft_plus, FFT::inverse );
    if ( system.use_twin_mode )
        calculateFFT( kernel_arguments.dev_ptrs.wavefunction_minus, kernel_arguments.dev_ptrs.fft_minus, FFT::inverse );

    if ( system.use_twin_mode ) {
        CALL_FULL_KERNEL( Kernel::Compute::gp_scalar_independent<true>, "independent", grid_size, block_size, 0, kernel_arguments, { kernel_arguments.dev_ptrs.fft_plus, kernel_arguments.dev_ptrs.fft_minus, kernel_arguments.dev_ptrs.buffer_reservoir_plus, kernel_arguments.dev_ptrs.buffer_reservoir_minus, kernel_arguments.dev_ptrs.wavefunction_plus, kernel_arguments.dev_ptrs.wavefunction_minus, kernel_arguments.dev_ptrs.reservoir_plus, kernel_arguments.dev_ptrs.reservoir_minus } );
    } else {
        CALL_FULL_KERNEL( Kernel::Compute::gp_scalar_independent<false>, "independent", grid_size, block_size, 0, kernel_arguments, { kernel_arguments.dev_ptrs.fft_plus, kernel_arguments.dev_ptrs.fft_minus, kernel_arguments.dev_ptrs.buffer_reservoir_plus, kernel_arguments.dev_ptrs.buffer_reservoir_minus, kernel_arguments.dev_ptrs.wavefunction_plus, kernel_arguments.dev_ptrs.wavefunction_minus, kernel_arguments.dev_ptrs.reservoir_plus, kernel_arguments.dev_ptrs.reservoir_minus } );
    }
    // WF now holds the new result
}

REGISTER_SOLVER( "SSFM", SSFM, false, "Split Step Fourier Method" );

} // namespace PHOENIX