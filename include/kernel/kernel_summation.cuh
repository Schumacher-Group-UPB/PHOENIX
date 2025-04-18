#pragma once
#include "cuda/typedef.cuh"
#include "solver/gpu_solver.hpp"

namespace PHOENIX::Kernel::Summation {

template <typename buffer_type, Type::uint32 NMax, Type::real w, Type::real... W>
PHOENIX_DEVICE PHOENIX_INLINE buffer_type sum_single_k( Type::uint32 i, buffer_type* buffer, Type::uint32 offset ) {
    if constexpr ( sizeof...( W ) == 0 ) {
        // Last Weight
        return w * buffer[i + offset * ( NMax - sizeof...( W ) - 1 )];
    }
    if constexpr ( w == 0.0 ) {
        return sum_single_k<buffer_type, NMax, W...>( i, buffer, offset );
    }
    // The constexpr if is logically redundant, but we need it so the compiler doesnt complain about not being able to call <buffer_type,int,w>
    // For sizeof..(W)==0, this line is never reached, but the compiler stil complains.
    if constexpr ( sizeof...( W ) > 0 ) {
        return w * buffer[i + offset * ( NMax - sizeof...( W ) - 1 )] + sum_single_k<buffer_type, NMax, W...>( i, buffer, offset );
    }
}

// TODO: summation kernel aufteilen in part mit und part ohne dw
// TODO: summation kernel nur noch einzen für jeden buffer. dann
// für gpu switch case machen mit wf,wf+rv,wfp,wfm,wfp+wfm+rvp+rvm
// für cu auch; launched dann entsprechend die loops. switch VOR den loops,
// d.h. in jedem case steht ein loop.
// Sollte für cu im fall ohne rv dann dafür sorgen, dass da nur eine einzelne summation steht, die ezpz simd optimiert werden kann.

// Specifically use Type::uint32 N instead of sizeof(Weights) to force MSVC to NOT inline this function for different solvers (RK3,RK4) which cases the respective RK solver to call the wrong template function.

template <typename buffer_type, bool complex_dt, Type::uint32 N, Type::real... Weights>
PHOENIX_DEVICE PHOENIX_INLINE void runge_sum_to_input_kw( Type::uint32 i, Type::uint32 current_halo, Solver::KernelArguments args, buffer_type* input, buffer_type* output, buffer_type* k_vec ) {
    buffer_type res = sum_single_k<buffer_type, sizeof...( Weights ), Weights...>( i, k_vec, args.p.subgrid_N2_with_halo );
    if constexpr ( not complex_dt ) {
        output[i] = input[i] + args.time[1] * res;
    } else {
        output[i] = input[i] + PHOENIX::Type::complex( 0.0f, -args.time[1] ) * res;
    }
}

template <typename buffer_type, bool complex_dt, Type::uint32 N, Type::real... Weights>
PHOENIX_DEVICE PHOENIX_INLINE void runge_add_to_input_kw( Type::uint32 i, Type::uint32 current_halo, Solver::KernelArguments args, buffer_type* input_output, buffer_type* k_vec ) {
    buffer_type res = sum_single_k<buffer_type, sizeof...( Weights ), Weights...>( i, k_vec, args.p.subgrid_N2_with_halo );

    if constexpr ( not complex_dt ) {
        input_output[i] += args.time[1] * res;
    } else {
        input_output[i] += PHOENIX::Type::complex( 0.0f, -args.time[1] ) * res;
    }
}

template <Type::real... Weights>
constexpr Type::real sum_weights() {
    return ( Weights + ... ); // Fold expression in C++17 or later
}

// Hardcoded RK1 Kernel
template <typename buffer_type, bool complex_dt, Type::uint32 N, Type::real w>
PHOENIX_DEVICE PHOENIX_INLINE void runge_sum_to_input_k1( Type::uint32 i, Type::uint32 offset, Type::uint32 current_halo, Solver::KernelArguments args, buffer_type* input, buffer_type* output, buffer_type* k_vec ) {
    if constexpr ( not complex_dt ) {
        output[i] = input[i] + args.time[1] * w * k_vec[i + offset];
    } else {
        output[i] = input[i] + PHOENIX::Type::complex( 0.0f, -args.time[1] ) * w * k_vec[i + offset];
    }
}
template <typename buffer_type, bool complex_dt, Type::uint32 N, Type::real w>
PHOENIX_DEVICE PHOENIX_INLINE void runge_add_to_input_k1( Type::uint32 i, Type::uint32 offset, Type::uint32 current_halo, Solver::KernelArguments args, buffer_type* input_output, buffer_type* k_vec ) {
    if constexpr ( not complex_dt ) {
        input_output[i] += args.time[1] * w * k_vec[i + offset];
    } else {
        input_output[i] += PHOENIX::Type::complex( 0.0f, -args.time[1] ) * w * k_vec[i + offset];
    }
}

// Hardcoded RK2 Kernel
template <typename buffer_type, bool complex_dt, Type::uint32 N, Type::real w1, Type::real w2>
PHOENIX_DEVICE PHOENIX_INLINE void runge_sum_to_input_k2( Type::uint32 i, Type::uint32 current_halo, Solver::KernelArguments args, buffer_type* input, buffer_type* output, buffer_type* k_vec ) {
    if constexpr ( not complex_dt ) {
        output[i] = input[i] + args.time[1] * ( w1 * k_vec[i] + w2 * k_vec[i + args.p.subgrid_N2_with_halo] );
    } else {
        output[i] = input[i] + PHOENIX::Type::complex( 0.0f, -args.time[1] ) * ( w1 * k_vec[i] + w2 * k_vec[i + args.p.subgrid_N2_with_halo] );
    }
}
template <typename buffer_type, bool complex_dt, Type::uint32 N, Type::real w1, Type::real w2>
PHOENIX_DEVICE PHOENIX_INLINE void runge_add_to_input_k2( Type::uint32 i, Type::uint32 current_halo, Solver::KernelArguments args, buffer_type* input_output, buffer_type* k_vec ) {
    if constexpr ( not complex_dt ) {
        input_output[i] += args.time[1] * ( w1 * k_vec[i] + w2 * k_vec[i + args.p.subgrid_N2_with_halo] );
    } else {
        input_output[i] += PHOENIX::Type::complex( 0.0f, -args.time[1] ) * ( w1 * k_vec[i] + w2 * k_vec[i + args.p.subgrid_N2_with_halo] );
    }
}

// Hardcoded RK3 Kernel
template <typename buffer_type, bool complex_dt, Type::uint32 N, Type::real w1, Type::real w2, Type::real w3>
PHOENIX_DEVICE PHOENIX_INLINE void runge_sum_to_input_k3( Type::uint32 i, Type::uint32 current_halo, Solver::KernelArguments args, buffer_type* input, buffer_type* output, buffer_type* k_vec ) {
    if constexpr ( not complex_dt ) {
        output[i] = input[i] + args.time[1] * ( w1 * k_vec[i] + w2 * k_vec[i + args.p.subgrid_N2_with_halo] + w3 * k_vec[i + 2 * args.p.subgrid_N2_with_halo] );
    } else {
        output[i] = input[i] + PHOENIX::Type::complex( 0.0f, -args.time[1] ) * ( w1 * k_vec[i] + w2 * k_vec[i + args.p.subgrid_N2_with_halo] + w3 * k_vec[i + 2 * args.p.subgrid_N2_with_halo] );
    }
}
template <typename buffer_type, bool complex_dt, Type::uint32 N, Type::real w1, Type::real w2, Type::real w3>
PHOENIX_DEVICE PHOENIX_INLINE void runge_add_to_input_k3( Type::uint32 i, Type::uint32 current_halo, Solver::KernelArguments args, buffer_type* input_output, buffer_type* k_vec ) {
    if constexpr ( not complex_dt ) {
        input_output[i] += args.time[1] * ( w1 * k_vec[i] + w2 * k_vec[i + args.p.subgrid_N2_with_halo] + w3 * k_vec[i + 2 * args.p.subgrid_N2_with_halo] );
    } else {
        input_output[i] += PHOENIX::Type::complex( 0.0f, -args.time[1] ) * ( w1 * k_vec[i] + w2 * k_vec[i + args.p.subgrid_N2_with_halo] + w3 * k_vec[i + 2 * args.p.subgrid_N2_with_halo] );
    }
}

// Hardcoded RK4 kernel
template <typename buffer_type, bool complex_dt, Type::uint32 N, Type::real w1, Type::real w2, Type::real w3, Type::real w4>
PHOENIX_DEVICE PHOENIX_INLINE void runge_sum_to_input_k4( Type::uint32 i, Type::uint32 current_halo, Solver::KernelArguments args, buffer_type* input, buffer_type* output, buffer_type* k_vec ) {
    if constexpr ( not complex_dt ) {
        output[i] = input[i] + args.time[1] * ( w1 * k_vec[i] + w2 * k_vec[i + args.p.subgrid_N2_with_halo] + w3 * k_vec[i + 2 * args.p.subgrid_N2_with_halo] + w4 * k_vec[i + 3 * args.p.subgrid_N2_with_halo] );
    } else {
        output[i] = input[i] + PHOENIX::Type::complex( 0.0f, -args.time[1] ) * ( w1 * k_vec[i] + w2 * k_vec[i + args.p.subgrid_N2_with_halo] + w3 * k_vec[i + 2 * args.p.subgrid_N2_with_halo] + w4 * k_vec[i + 3 * args.p.subgrid_N2_with_halo] );
    }
}
template <typename buffer_type, bool complex_dt, Type::uint32 N, Type::real w1, Type::real w2, Type::real w3, Type::real w4>
PHOENIX_DEVICE PHOENIX_INLINE void runge_add_to_input_k4( Type::uint32 i, Type::uint32 current_halo, Solver::KernelArguments args, buffer_type* input_output, buffer_type* k_vec ) {
    if constexpr ( not complex_dt ) {
        input_output[i] += args.time[1] * ( w1 * k_vec[i] + w2 * k_vec[i + args.p.subgrid_N2_with_halo] + w3 * k_vec[i + 2 * args.p.subgrid_N2_with_halo] + w4 * k_vec[i + 3 * args.p.subgrid_N2_with_halo] );
    } else {
        input_output[i] += PHOENIX::Type::complex( 0.0f, -args.time[1] ) * ( w1 * k_vec[i] + w2 * k_vec[i + args.p.subgrid_N2_with_halo] + w3 * k_vec[i + 2 * args.p.subgrid_N2_with_halo] + w4 * k_vec[i + 3 * args.p.subgrid_N2_with_halo] );
    }
}

// Hardcoded RK5 kernel
template <typename buffer_type, bool complex_dt, Type::uint32 N, Type::real w1, Type::real w2, Type::real w3, Type::real w4, Type::real w5>
PHOENIX_DEVICE PHOENIX_INLINE void runge_sum_to_input_k5( Type::uint32 i, Type::uint32 current_halo, Solver::KernelArguments args, buffer_type* input, buffer_type* output, buffer_type* k_vec ) {
    if constexpr ( not complex_dt ) {
        output[i] = input[i] + args.time[1] * ( w1 * k_vec[i] + w2 * k_vec[i + args.p.subgrid_N2_with_halo] + w3 * k_vec[i + 2 * args.p.subgrid_N2_with_halo] + w4 * k_vec[i + 3 * args.p.subgrid_N2_with_halo] + w5 * k_vec[i + 4 * args.p.subgrid_N2_with_halo] );
    } else {
        output[i] = input[i] + PHOENIX::Type::complex( 0.0f, -args.time[1] ) * ( w1 * k_vec[i] + w2 * k_vec[i + args.p.subgrid_N2_with_halo] + w3 * k_vec[i + 2 * args.p.subgrid_N2_with_halo] + w4 * k_vec[i + 3 * args.p.subgrid_N2_with_halo] + w5 * k_vec[i + 4 * args.p.subgrid_N2_with_halo] );
    }
}
template <typename buffer_type, bool complex_dt, Type::uint32 N, Type::real w1, Type::real w2, Type::real w3, Type::real w4, Type::real w5>
PHOENIX_DEVICE PHOENIX_INLINE void runge_add_to_input_k5( Type::uint32 i, Type::uint32 current_halo, Solver::KernelArguments args, buffer_type* input_output, buffer_type* k_vec ) {
    if constexpr ( not complex_dt ) {
        input_output[i] += args.time[1] * ( w1 * k_vec[i] + w2 * k_vec[i + args.p.subgrid_N2_with_halo] + w3 * k_vec[i + 2 * args.p.subgrid_N2_with_halo] + w4 * k_vec[i + 3 * args.p.subgrid_N2_with_halo] + w5 * k_vec[i + 4 * args.p.subgrid_N2_with_halo] );
    } else {
        input_output[i] += PHOENIX::Type::complex( 0.0f, -args.time[1] ) * ( w1 * k_vec[i] + w2 * k_vec[i + args.p.subgrid_N2_with_halo] + w3 * k_vec[i + 2 * args.p.subgrid_N2_with_halo] + w4 * k_vec[i + 3 * args.p.subgrid_N2_with_halo] + w5 * k_vec[i + 4 * args.p.subgrid_N2_with_halo] );
    }
}

// Hardcoded RK6 kernel
template <typename buffer_type, bool complex_dt, Type::uint32 N, Type::real w1, Type::real w2, Type::real w3, Type::real w4, Type::real w5, Type::real w6>
PHOENIX_DEVICE PHOENIX_INLINE void runge_sum_to_input_k6( Type::uint32 i, Type::uint32 current_halo, Solver::KernelArguments args, buffer_type* input, buffer_type* output, buffer_type* k_vec ) {
    if constexpr ( not complex_dt ) {
        output[i] = input[i] + args.time[1] * ( w1 * k_vec[i] + w2 * k_vec[i + args.p.subgrid_N2_with_halo] + w3 * k_vec[i + 2 * args.p.subgrid_N2_with_halo] + w4 * k_vec[i + 3 * args.p.subgrid_N2_with_halo] + w5 * k_vec[i + 4 * args.p.subgrid_N2_with_halo] + w6 * k_vec[i + 5 * args.p.subgrid_N2_with_halo] );
    } else {
        output[i] = input[i] + PHOENIX::Type::complex( 0.0f, -args.time[1] ) * ( w1 * k_vec[i] + w2 * k_vec[i + args.p.subgrid_N2_with_halo] + w3 * k_vec[i + 2 * args.p.subgrid_N2_with_halo] + w4 * k_vec[i + 3 * args.p.subgrid_N2_with_halo] + w5 * k_vec[i + 4 * args.p.subgrid_N2_with_halo] + w6 * k_vec[i + 5 * args.p.subgrid_N2_with_halo] );
    }
}
template <typename buffer_type, bool complex_dt, Type::uint32 N, Type::real w1, Type::real w2, Type::real w3, Type::real w4, Type::real w5, Type::real w6>
PHOENIX_DEVICE PHOENIX_INLINE void runge_add_to_input_k6( Type::uint32 i, Type::uint32 current_halo, Solver::KernelArguments args, buffer_type* input_output, buffer_type* k_vec ) {
    if constexpr ( not complex_dt ) {
        input_output[i] += args.time[1] * ( w1 * k_vec[i] + w2 * k_vec[i + args.p.subgrid_N2_with_halo] + w3 * k_vec[i + 2 * args.p.subgrid_N2_with_halo] + w4 * k_vec[i + 3 * args.p.subgrid_N2_with_halo] + w5 * k_vec[i + 4 * args.p.subgrid_N2_with_halo] + w6 * k_vec[i + 5 * args.p.subgrid_N2_with_halo] );
    } else {
        input_output[i] += PHOENIX::Type::complex( 0.0f, -args.time[1] ) * ( w1 * k_vec[i] + w2 * k_vec[i + args.p.subgrid_N2_with_halo] + w3 * k_vec[i + 2 * args.p.subgrid_N2_with_halo] + w4 * k_vec[i + 3 * args.p.subgrid_N2_with_halo] + w5 * k_vec[i + 4 * args.p.subgrid_N2_with_halo] + w6 * k_vec[i + 5 * args.p.subgrid_N2_with_halo] );
    }
}

// Hardcoded RK7 kernel
template <typename buffer_type, bool complex_dt, Type::uint32 N, Type::real w1, Type::real w2, Type::real w3, Type::real w4, Type::real w5, Type::real w6, Type::real w7>
PHOENIX_DEVICE PHOENIX_INLINE void runge_sum_to_input_k7( Type::uint32 i, Type::uint32 current_halo, Solver::KernelArguments args, buffer_type* input, buffer_type* output, buffer_type* k_vec ) {
    if constexpr ( not complex_dt ) {
        output[i] = input[i] + args.time[1] * ( w1 * k_vec[i] + w2 * k_vec[i + args.p.subgrid_N2_with_halo] + w3 * k_vec[i + 2 * args.p.subgrid_N2_with_halo] + w4 * k_vec[i + 3 * args.p.subgrid_N2_with_halo] + w5 * k_vec[i + 4 * args.p.subgrid_N2_with_halo] + w6 * k_vec[i + 5 * args.p.subgrid_N2_with_halo] + w7 * k_vec[i + 6 * args.p.subgrid_N2_with_halo] );
    } else {
        output[i] = input[i] + PHOENIX::Type::complex( 0.0f, -args.time[1] ) * ( w1 * k_vec[i] + w2 * k_vec[i + args.p.subgrid_N2_with_halo] + w3 * k_vec[i + 2 * args.p.subgrid_N2_with_halo] + w4 * k_vec[i + 3 * args.p.subgrid_N2_with_halo] + w5 * k_vec[i + 4 * args.p.subgrid_N2_with_halo] + w6 * k_vec[i + 5 * args.p.subgrid_N2_with_halo] + w7 * k_vec[i + 6 * args.p.subgrid_N2_with_halo] );
    }
}
template <typename buffer_type, bool complex_dt, Type::uint32 N, Type::real w1, Type::real w2, Type::real w3, Type::real w4, Type::real w5, Type::real w6, Type::real w7>
PHOENIX_DEVICE PHOENIX_INLINE void runge_add_to_input_k7( Type::uint32 i, Type::uint32 current_halo, Solver::KernelArguments args, buffer_type* input_output, buffer_type* k_vec ) {
    if constexpr ( not complex_dt ) {
        input_output[i] += args.time[1] * ( w1 * k_vec[i] + w2 * k_vec[i + args.p.subgrid_N2_with_halo] + w3 * k_vec[i + 2 * args.p.subgrid_N2_with_halo] + w4 * k_vec[i + 3 * args.p.subgrid_N2_with_halo] + w5 * k_vec[i + 4 * args.p.subgrid_N2_with_halo] + w6 * k_vec[i + 5 * args.p.subgrid_N2_with_halo] + w7 * k_vec[i + 6 * args.p.subgrid_N2_with_halo] );
    } else {
        input_output[i] += PHOENIX::Type::complex( 0.0f, -args.time[1] ) * ( w1 * k_vec[i] + w2 * k_vec[i + args.p.subgrid_N2_with_halo] + w3 * k_vec[i + 2 * args.p.subgrid_N2_with_halo] + w4 * k_vec[i + 3 * args.p.subgrid_N2_with_halo] + w5 * k_vec[i + 4 * args.p.subgrid_N2_with_halo] + w6 * k_vec[i + 5 * args.p.subgrid_N2_with_halo] + w7 * k_vec[i + 6 * args.p.subgrid_N2_with_halo] );
    }
}

// Helper function to chose the correct kernel function
// This way we can hardcode a lot of the RK kernels and still have a single kernel function to call, hopefully at no performance cost.
// This way we can also hardcode more K functions, if we want to.
template <typename buffer_type, bool complex_dt, bool include_dw, bool include_reservoir, Type::uint32 N, Type::real... Weights>
PHOENIX_GLOBAL PHOENIX_COMPILER_SPECIFIC void runge_sum_to_input_k( Type::uint32 i, Type::uint32 current_halo, Solver::KernelArguments args, buffer_type* input, buffer_type* output, buffer_type* k_vec ) {
    GENERATE_SUBGRID_INDEX( i, current_halo );

    if constexpr ( sizeof...( Weights ) == 1 ) {
        runge_sum_to_input_k1<buffer_type, complex_dt, N, Weights...>( i, ( N - 1 ) * args.p.subgrid_N2_with_halo, current_halo, args, input, output, k_vec );
    } else if constexpr ( sizeof...( Weights ) == 2 ) {
        runge_sum_to_input_k2<buffer_type, complex_dt, N, Weights...>( i, current_halo, args, input, output, k_vec );
    } else if constexpr ( sizeof...( Weights ) == 3 ) {
        runge_sum_to_input_k3<buffer_type, complex_dt, N, Weights...>( i, current_halo, args, input, output, k_vec );
    } else if constexpr ( sizeof...( Weights ) == 4 ) {
        runge_sum_to_input_k4<buffer_type, complex_dt, N, Weights...>( i, current_halo, args, input, output, k_vec );
    } else if constexpr ( sizeof...( Weights ) == 5 ) {
        runge_sum_to_input_k5<buffer_type, complex_dt, N, Weights...>( i, current_halo, args, input, output, k_vec );
    } else if constexpr ( sizeof...( Weights ) == 6 ) {
        runge_sum_to_input_k6<buffer_type, complex_dt, N, Weights...>( i, current_halo, args, input, output, k_vec );
    } else if constexpr ( sizeof...( Weights ) == 7 ) {
        runge_sum_to_input_k7<buffer_type, complex_dt, N, Weights...>( i, current_halo, args, input, output, k_vec );
    } else {
        runge_sum_to_input_kw<buffer_type, complex_dt, N, Weights...>( i, current_halo, args, input, output, k_vec );
    }
    if constexpr ( include_dw ) {
        constexpr Type::real w_sum = sum_weights<Weights...>();
        if constexpr ( include_reservoir ) {
            auto dw = w_sum * args.dev_ptrs.random_number[i] * CUDA::sqrt( ( args.p.R * args.dev_ptrs.reservoir_plus[i] + args.p.gamma_c ) / ( Type::real( 4.0 ) * args.p.dV ) ); // / args.time[1];
            output[i] += dw;
        } else {
            auto dw = w_sum * args.dev_ptrs.random_number[i] * CUDA::sqrt( args.p.gamma_c / ( Type::real( 4.0 ) * args.p.dV ) ); // / args.time[1];
            output[i] += dw;
        }
    }
}
template <typename buffer_type, bool complex_dt, bool include_dw, bool include_reservoir, Type::uint32 N, Type::real... Weights>
PHOENIX_GLOBAL PHOENIX_COMPILER_SPECIFIC void runge_add_to_input_k( Type::uint32 i, Type::uint32 current_halo, Solver::KernelArguments args, buffer_type* input_output, buffer_type* k_vec ) {
    GENERATE_SUBGRID_INDEX( i, current_halo );

    if constexpr ( sizeof...( Weights ) == 1 ) {
        runge_add_to_input_k1<buffer_type, complex_dt, N, Weights...>( i, ( N - 1 ) * args.p.subgrid_N2_with_halo, current_halo, args, input_output, k_vec );
    } else if constexpr ( sizeof...( Weights ) == 2 ) {
        runge_add_to_input_k2<buffer_type, complex_dt, N, Weights...>( i, current_halo, args, input_output, k_vec );
    } else if constexpr ( sizeof...( Weights ) == 3 ) {
        runge_add_to_input_k3<buffer_type, complex_dt, N, Weights...>( i, current_halo, args, input_output, k_vec );
    } else if constexpr ( sizeof...( Weights ) == 4 ) {
        runge_add_to_input_k4<buffer_type, complex_dt, N, Weights...>( i, current_halo, args, input_output, k_vec );
    } else if constexpr ( sizeof...( Weights ) == 5 ) {
        runge_add_to_input_k5<buffer_type, complex_dt, N, Weights...>( i, current_halo, args, input_output, k_vec );
    } else if constexpr ( sizeof...( Weights ) == 6 ) {
        runge_add_to_input_k6<buffer_type, complex_dt, N, Weights...>( i, current_halo, args, input_output, k_vec );
    } else if constexpr ( sizeof...( Weights ) == 7 ) {
        runge_add_to_input_k7<buffer_type, complex_dt, N, Weights...>( i, current_halo, args, input_output, k_vec );
    } else {
        runge_add_to_input_kw<buffer_type, complex_dt, N, Weights...>( i, current_halo, args, input_output, k_vec );
    }
    if constexpr ( include_dw ) {
        constexpr Type::real w_sum = sum_weights<Weights...>();
        if constexpr ( include_reservoir ) {
            auto dw = w_sum * args.dev_ptrs.random_number[i] * CUDA::sqrt( ( args.p.R * args.dev_ptrs.reservoir_plus[i] + args.p.gamma_c ) / ( Type::real( 4.0 ) * args.p.dV ) ); // / args.time[1];
            input_output[i] += dw;
        } else {
            auto dw = w_sum * args.dev_ptrs.random_number[i] * CUDA::sqrt( args.p.gamma_c / ( Type::real( 4.0 ) * args.p.dV ) ); // / args.time[1];
            input_output[i] += dw;
        }
    }
}

template <int NMax, int N, Type::real w, Type::real... W>
PHOENIX_DEVICE PHOENIX_COMPILER_SPECIFIC void sum_single_error_k( int i, Type::complex& error, Type::complex* k_wavefunction, Type::uint32 offset ) {
    if constexpr ( w != 0.0 ) {
        error += w * k_wavefunction[i + offset * ( NMax - N )];
    }
    if constexpr ( sizeof...( W ) > 0 ) {
        sum_single_error_k<NMax, N - 1, W...>( i, error, k_wavefunction, offset );
    }
}

template <typename buffer_type, bool complex_dt, bool reset, Type::real... Weights>
PHOENIX_GLOBAL PHOENIX_COMPILER_SPECIFIC void runge_sum_to_error( int i, Type::uint32 current_halo, Solver::KernelArguments args, buffer_type* k_wavefunction ) {
    GENERATE_SUBGRID_INDEX( i, current_halo );

    Type::complex error = 0.0;

    sum_single_error_k<sizeof...( Weights ), sizeof...( Weights ), Weights...>( i, error, k_wavefunction, args.p.subgrid_N2_with_halo );

    if constexpr ( not complex_dt ) {
        if constexpr ( reset )
            args.dev_ptrs.rk_error[i] = CUDA::abs2( args.time[1] * error );
        else
            args.dev_ptrs.rk_error[i] += CUDA::abs2( args.time[1] * error );
    } else {
        if constexpr ( reset )
            args.dev_ptrs.rk_error[i] = CUDA::abs2( PHOENIX::Type::complex( 0.0f, -args.time[1] ) * error );
        else
            args.dev_ptrs.rk_error[i] += CUDA::abs2( PHOENIX::Type::complex( 0.0f, -args.time[1] ) * error );
    }
}
} // namespace PHOENIX::Kernel::Summation
