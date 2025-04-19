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

void PHOENIX::Solver::iterateFixedTimestepRungeKutta3() {
    SOLVER_SEQUENCE( true /*Capture CUDA Graph*/,

                     CALCULATE_K( 1, wavefunction, reservoir );

                     INTERMEDIATE_SUM_K( 1, Type::real( 0.5 ) );

                     CALCULATE_K( 2, buffer_wavefunction, buffer_reservoir );

                     INTERMEDIATE_SUM_K( 2, Type::real( -1.0 ), Type::real( 2.0 ) );

                     CALCULATE_K( 3, buffer_wavefunction, buffer_reservoir );

                     FINAL_SUM_K( 3, Type::real( 1.0 / 6.0 ), Type::real( 2.0 / 3.0 ), Type::real( 1.0 / 6.0 ), Type::real( 1.0 / 6.0 ) );

    );
}

/*
 * This function iterates the Runge Kutta Kernel using a fixed time step.
 * A 4th order Runge-Kutta method is used. This function calls a single
 * rungeFuncSum function with varying delta-t. Calculation of the inputs
 * for the next rungeFuncKernel call is done in the rungeFuncSum function.
 * The general implementation of the RK4 method goes as follows:
 * ------------------------------------------------------------------------------
 * k1 =f(t, y) = rungeFuncKernel(current)
 * input_for_k2 = current + 0.5 * dt * k1
 * k2 = f(t + 0.5 * dt, input_for_k2) = rungeFuncKernel(input_for_k2)
 * input_for_k3 = current + 0.5 * dt * k2
 * k3 = f(t + 0.5 * dt, input_for_k3) = rungeFuncKernel(input_for_k3)
 * input_for_k4 = current + dt * k3
 * k4 = f(t + dt, input_for_k4) = rungeFuncKernel(input_for_k4) 
 * next = current + dt * (1/6 * k1 + 1/3 * k2 + 1/3 * k3 + 1/6 * k4)
 * ------------------------------------------------------------------------------ 
 * The Runge method iterates psi,k1-k4 to psi_next using a wave-like approach.
 * We calculate 4 rows of k1, 3 rows of k2, 2 rows of k3 and 1 row of k4 before the first iteration.
 * Then, we iterate all of the remaining rows after each other, incrementing the buffer for the next iteration.
 */

void PHOENIX::Solver::iterateFixedTimestepRungeKutta4() {
    SOLVER_SEQUENCE( true /*Capture CUDA Graph*/,

                     CALCULATE_K( 1, wavefunction, reservoir );

                     INTERMEDIATE_SUM_K( 1, Type::real(0.5) );

                     CALCULATE_K( 2, buffer_wavefunction, buffer_reservoir );

                     INTERMEDIATE_SUM_K( 2, Type::real(0.5) );

                     CALCULATE_K( 3, buffer_wavefunction, buffer_reservoir );

                     INTERMEDIATE_SUM_K( 3, Type::real(1.0) );

                     CALCULATE_K( 4, buffer_wavefunction, buffer_reservoir );

                     FINAL_SUM_K( 4, Type::real(1.0 / 6.0), Type::real(1.0 / 3.0), Type::real(1.0 / 3.0), Type::real(1.0 / 6.0) );

    );
}
