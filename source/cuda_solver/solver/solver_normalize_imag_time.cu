
#include "cuda/typedef.cuh"
#ifdef USE_CUDA
    #include <thrust/reduce.h>
    #include <thrust/transform_reduce.h>
    #include <thrust/execution_policy.h>
#else
    #include <numeric>
#endif
#include <iostream>
#include "solver/solver.hpp"
#include "kernel/kernel_compute.cuh"

void PHOENIX::Solver::normalizeImaginaryTimePropagation() {
    // Calculate sums
    Type::real sum_psi_plus = CUDA::real( matrix.wavefunction_plus.transformReduce( 0.0, [] PHOENIX_HOST_DEVICE( Type::complex a ) { return Type::complex( CUDA::abs2( a ) ); }, [] PHOENIX_HOST_DEVICE( Type::complex a, Type::complex b ) { return a + b; } ) );
    Type::real sum_res_plus = CUDA::real( matrix.reservoir_plus.transformReduce( 0.0, [] PHOENIX_HOST_DEVICE( Type::complex a ) { return Type::complex( CUDA::abs2( a ) ); }, [] PHOENIX_HOST_DEVICE( Type::complex a, Type::complex b ) { return a + b; } ) );

    if ( sum_psi_plus < 1e-10 )
        sum_psi_plus = 1.0;
    if ( sum_res_plus < 1e-10 )
        sum_res_plus = 1.0;

    sum_psi_plus = std::sqrt( system.imag_time_amplitude / ( sum_psi_plus * system.p.dV ) );
    sum_res_plus = std::sqrt( system.imag_time_amplitude / ( sum_res_plus * system.p.dV ) );

    matrix.wavefunction_plus.transform( [sum_psi_plus] PHOENIX_HOST_DEVICE( Type::complex val ) { return val * sum_psi_plus; } );
    matrix.reservoir_plus.transform( [sum_res_plus] PHOENIX_HOST_DEVICE( Type::complex val ) { return val * sum_res_plus; } );

    if ( not system.use_twin_mode )
        return;

    // Calculate sums
    Type::real sum_psi_minus = CUDA::real( matrix.wavefunction_minus.transformReduce( 0.0, [] PHOENIX_HOST_DEVICE( Type::complex a ) { return Type::complex( CUDA::abs2( a ) ); }, [] PHOENIX_HOST_DEVICE( Type::complex a, Type::complex b ) { return a + b; } ) );
    Type::real sum_res_minus = CUDA::real( matrix.reservoir_minus.transformReduce( 0.0, [] PHOENIX_HOST_DEVICE( Type::complex a ) { return Type::complex( CUDA::abs2( a ) ); }, [] PHOENIX_HOST_DEVICE( Type::complex a, Type::complex b ) { return a + b; } ) );

    if ( sum_psi_minus < 1e-10 )
        sum_psi_minus = 1.0;
    if ( sum_res_minus < 1e-10 )
        sum_res_minus = 1.0;

    sum_psi_minus = std::sqrt( system.imag_time_amplitude / ( sum_psi_minus * system.p.dV ) );
    sum_res_minus = std::sqrt( system.imag_time_amplitude / ( sum_res_minus * system.p.dV ) );

    matrix.wavefunction_minus.transform( [sum_psi_minus] PHOENIX_HOST_DEVICE( Type::complex val ) { return val * sum_psi_minus; } );
    matrix.reservoir_minus.transform( [sum_res_minus] PHOENIX_HOST_DEVICE( Type::complex val ) { return val * sum_res_minus; } );
}