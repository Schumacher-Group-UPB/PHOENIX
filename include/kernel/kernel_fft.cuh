#pragma once
#include "cuda/typedef.cuh"
#include "cuda/cuda_macro.cuh"

namespace PC3::Kernel {

template <typename T>
PULSE_GLOBAL void kernel_make_fft_visible( int i, T* input, T* output, const Type::uint32 N ) {
    GET_THREAD_INDEX( i, N );

    const auto val = input[i];
    output[i] = Type::complex( std::log( CUDA::real( val ) * CUDA::real( val ) + CUDA::imag( val ) * PC3::CUDA::imag( val ) ), 0 );
}

template <typename T>
PULSE_GLOBAL void fft_shift_2D( int i, T* data, const Type::uint32 N_c, const Type::uint32 N_r ) {
    GET_THREAD_INDEX( i, N_c * N_r );

    // Current indices of upper left quadrant
    const int k = i / N_c;
    if ( k >= N_r / 2 )
        return;
    const int l = i % N_c;
    if ( l >= N_c / 2 )
        return;

    // Swap upper left quadrant with lower right quadrant
    swap_symbol( data[k * N_c + l], data[( k + N_r / 2 ) * N_c + l + N_c / 2] );

    // Swap lower left quadrant with upper right quadrant
    swap_symbol( data[k * N_c + l + N_c / 2], data[( k + N_r / 2 ) * N_c + l] );
}

template <typename T, typename U>
PULSE_GLOBAL void kernel_mask_fft( int i, T* data, U* mask, const Type::uint32 N ) {
    GET_THREAD_INDEX( i, N );

    data[i] = data[i] / Type::real( N ) * mask[i];
}

} // namespace PC3::Kernel