#include <omp.h>

// Include Cuda Kernel headers
#include "cuda/typedef.cuh"
#include "kernel/kernel_compute.cuh"
#include "system/system_parameters.hpp"
#include "misc/helperfunctions.hpp"
#include "cuda/cuda_matrix.cuh"
#include "solver/gpu_solver.hpp"
#include "misc/commandline_io.hpp"

/**
 * Split Step Fourier Method
 */
void PC3::Solver::iterateSplitStepFourier( dim3 block_size, dim3 grid_size ) {
    /*
    Type::complex dt = system.imag_time_amplitude != 0.0 ? Type::complex(0.0, -system.p.dt) : Type::complex(system.p.dt, 0.0);

    auto device_pointers = matrix.pointers();

    updateKernelArguments( system.p.t, dt );

    // Liner Half Step
    // Calculate the FFT of Psi
    calculateFFT( device_pointers.wavefunction_plus, device_pointers.k1_wavefunction_plus, FFT::forward );
    if (system.p.use_twin_mode)
        calculateFFT( device_pointers.wavefunction_minus, device_pointers.k1_wavefunction_minus, FFT::forward );
    CALL_KERNEL(
        RUNGE_FUNCTION_GP_LINEAR, "linear_half_step", grid_size, block_size, 0,
        kernel_arguments, 
        { 
            device_pointers.k1_wavefunction_plus, device_pointers.k1_wavefunction_minus, device_pointers.discard, device_pointers.discard,
            device_pointers.k2_wavefunction_plus, device_pointers.k2_wavefunction_minus, device_pointers.discard, device_pointers.discard
        }
    );
    // Transform back. K1 now holds the half-stepped wavefunction.
    calculateFFT( device_pointers.k2_wavefunction_plus, device_pointers.k1_wavefunction_plus, FFT::inverse );
    if (system.p.use_twin_mode)
        calculateFFT( device_pointers.k2_wavefunction_minus, device_pointers.k1_wavefunction_minus, FFT::inverse );

    // Nonlinear Full Step
    CALL_KERNEL(
        RUNGE_FUNCTION_GP_NONLINEAR, "nonlinear_full_step", grid_size, block_size, 0,
        kernel_arguments,
        { 
            device_pointers.k1_wavefunction_plus, device_pointers.k1_wavefunction_minus, device_pointers.reservoir_plus, device_pointers.reservoir_minus,
            device_pointers.k2_wavefunction_plus, device_pointers.k2_wavefunction_minus, device_pointers.buffer_reservoir_plus, device_pointers.buffer_reservoir_minus
        }
    );
    // K2 now holds the nonlinearly evolved wavefunction.

    // Liner Half Step 
    // Calculate the FFT of Psi
    calculateFFT( device_pointers.k2_wavefunction_plus, device_pointers.k1_wavefunction_plus, FFT::forward );
    if (system.p.use_twin_mode)
        calculateFFT( device_pointers.k2_wavefunction_minus, device_pointers.k1_wavefunction_minus, FFT::forward );
    CALL_KERNEL(
        RUNGE_FUNCTION_GP_LINEAR, "linear_half_step", grid_size, block_size, 0,
        kernel_arguments,
        { 
            device_pointers.k1_wavefunction_plus, device_pointers.k1_wavefunction_minus, device_pointers.discard, device_pointers.discard,
            device_pointers.k2_wavefunction_plus, device_pointers.k2_wavefunction_minus, device_pointers.discard, device_pointers.discard
        }
    );
    // Transform back. K3 now holds the half-stepped wavefunction.
    calculateFFT( device_pointers.k2_wavefunction_plus,  device_pointers.k1_wavefunction_plus, FFT::inverse );
    if (system.p.use_twin_mode)
        calculateFFT( device_pointers.k2_wavefunction_minus, device_pointers.k1_wavefunction_minus, FFT::inverse );

    CALL_KERNEL(
        RUNGE_FUNCTION_GP_INDEPENDENT, "independent", grid_size, block_size, 0,
        kernel_arguments,
        {  
            device_pointers.k1_wavefunction_plus, device_pointers.k1_wavefunction_minus, device_pointers.reservoir_plus, device_pointers.reservoir_minus,
            device_pointers.buffer_wavefunction_plus, device_pointers.buffer_wavefunction_minus, device_pointers.discard, device_pointers.discard
        }
    );
    // Buffer now holds the new result

    // Swap the next and current wavefunction buffers. This only swaps the pointers, not the data.
    swapBuffers();
    */
}