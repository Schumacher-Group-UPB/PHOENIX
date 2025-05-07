#pragma once
#include "cuda/typedef.cuh"
#include "solver/solver.hpp"

#include "kernel/kernel_gp_compute.cuh"

/**
 * Contains the Kernels required for the Runge Kutta Solver
 * These Kernels rely on Solver::KernelArguments and Solver::InputOutput
 * to access the necessary data.
 */

namespace PHOENIX::Kernel {

PHOENIX_GLOBAL void initialize_random_number_generator( int i, Type::uint32 seed, Type::cuda_random_state* state, const Type::uint32 N );
PHOENIX_GLOBAL void generate_random_numbers( int i, Type::cuda_random_state* state, Type::complex* buffer, const Type::uint32 N, const Type::real real_amp, const Type::real imag_amp );

} // namespace PHOENIX::Kernel