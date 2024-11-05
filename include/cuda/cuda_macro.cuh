#pragma once

#include "cuda/typedef.cuh"
#ifdef USE_CPU
  #include <immintrin.h>
#endif

// Macro to copy to contents of the buffers into shared memory. The threads can then use threadIdx.x to access the shared memory.
#ifdef USE_CPU
    #define BUFFER_TO_SHARED()
#else
    #define BUFFER_TO_SHARED()                                                                          \
        extern __shared__ Type::complex input_wf[];                                                     \
        /* Only thead 0 of the block copies the data to shared memory */                                \
        Type::uint32 bd = blockDim.x;                                                                   \
        Type::uint32 number_of_elements = 3 * bd + 6;                                                   \
        /* Copy the elements from current index of threadIdx.x = 0 (which is i) - subgrid_row_offset */ \
        /* Each Thread loads three elements*/                                                           \
        Type::uint32 tid = threadIdx.x;                                                                 \
        input_wf[tid] = io.in_wf_plus[i - args.p.subgrid_row_offset];                                   \
        input_wf[tid + bd] = io.in_wf_plus[i];                                                          \
        input_wf[tid + 2 * bd] = io.in_wf_plus[i + args.p.subgrid_row_offset];                          \
        /* Threads zero also loads the left border */                                                   \
        if ( threadIdx.x == 0 ) {                                                                       \
            /* Left Border */                                                                           \
            input_wf[0] = io.in_wf_plus[i - args.p.subgrid_row_offset - 1];                             \
            input_wf[1] = io.in_wf_plus[i - 1];                                                         \
            input_wf[2] = io.in_wf_plus[i + args.p.subgrid_row_offset - 1];                             \
        }                                                                                               \
        /* Threads zero also loads the right border */                                                  \
        if ( threadIdx.x == bd - 1 ) { /* Right Border */                                               \
            input_wf[number_of_elements - 3] = io.in_wf_plus[i - args.p.subgrid_row_offset + 1];        \
            input_wf[number_of_elements - 2] = io.in_wf_plus[i + 1];                                    \
            input_wf[number_of_elements - 1] = io.in_wf_plus[i + args.p.subgrid_row_offset + 1];        \
        } /* Shared index equivalent to "i" */                                                          \
        Type::uint32 si = threadIdx.x + bd;                                                             \
        __syncthreads();
#endif

#ifdef USE_CUDA
    // If the GPU is used, overwrite the current index with the gpu thread index.
    #define GENERATE_SUBGRID_INDEX( i, ch )                                           \
        i = blockIdx.x * blockDim.x + threadIdx.x;                                    \
        if ( i >= ( args.p.subgrid_N_c + 2 * ch ) * ( args.p.subgrid_N_r + 2 * ch ) ) \
            return;                                                                   \
        Type::uint32 r = i / ( args.p.subgrid_N_c + 2 * ch );                         \
        Type::uint32 c = i % ( args.p.subgrid_N_c + 2 * ch );                         \
        i = ( args.p.subgrid_row_offset ) * ( r + args.p.halo_size - ch ) + args.p.halo_size - ch + c;
    #define GENERATE_THREAD_INDEX( N )                 \
        int i = blockIdx.x * blockDim.x + threadIdx.x; \
        if ( i >= N )                                  \
            return;
    #define GET_THREAD_INDEX( i, N )               \
        i = blockIdx.x * blockDim.x + threadIdx.x; \
        if ( i >= N )                              \
            return;

    #define LOCAL_SHARE_STRUCT( T, in, out ) \
        __shared__ T out;                    \
        if ( threadIdx.x == 0 ) {            \
            out = in;                        \
        }                                    \
        __syncthreads();
#else
    //#define GENERATE_SUBGRID_INDEX( i, ch )                                           \
    //    Type::uint32 r = i / ( args.p.subgrid_N_c + 2 * ch );                         \
    //    Type::uint32 c = i % ( args.p.subgrid_N_c + 2 * ch );                         \
    //    i = ( args.p.subgrid_row_offset ) * ( r + args.p.halo_size - ch ) + args.p.halo_size - ch + c;
    #define GENERATE_SUBGRID_INDEX( i, ch )
    #define GENERATE_THREAD_INDEX( N ) int i = 0;
    #define GET_THREAD_INDEX( i, N )

    #define LOCAL_SHARE_STRUCT( T, in, out ) T &out = in;

#endif

// For some reason, GCC needs this to correctly unpack the variadic arguments into a templated function
#define GCC_EXPAND_VA_ARGS( ... ) __VA_ARGS__
#define GCC_EXPAND_VA_ARGS_ORDER( order, ... ) order, __VA_ARGS__

// Helper Macro to iterate a specific RK K. // Only Callable from within the solver
// This helper gets a little ugly when branching for all the specific cases using the templated kernel. Should ultimately perform better tho.
// OMG I am so sorry... but this is actually quite a bit faster than before, because we dont use function pointers any more^^
#ifdef NO_CALCULATE_K
#define CALCULATE_K( index, input_wavefunction, input_reservoir )                                                                                                               \
    {                                                                                                                                                                           \
    };
#else
#ifdef BENCH
#ifdef USE_CPU
#define CALCULATE_K( index, input_wavefunction, input_reservoir )                                                                                                               \
    {                                                                                                                                                                           \
        const Type::uint32 current_halo = system.p.halo_size - index;                                                                                                           \
        auto [current_block, current_grid] = getLaunchParameters( system.p.subgrid_N_c + 2 * current_halo, system.p.subgrid_N_r + 2 * current_halo );                           \
        Solver::InputOutput io{ matrix.input_wavefunction##_plus.getDevicePtr( subgrid ),      matrix.input_wavefunction##_minus.getDevicePtr( subgrid ),                       \
                                matrix.input_wavefunction##_iplus.getDevicePtr( subgrid ),     matrix.input_wavefunction##_iminus.getDevicePtr( subgrid ),                      \
                                matrix.input_reservoir##_plus.getDevicePtr( subgrid ),         matrix.input_reservoir##_minus.getDevicePtr( subgrid ),                          \
                                matrix.k_wavefunction_plus.getDevicePtr( subgrid, index - 1 ), matrix.k_wavefunction_minus.getDevicePtr( subgrid, index - 1 ),                  \
                                matrix.k_reservoir_plus.getDevicePtr( subgrid, index - 1 ),    matrix.k_reservoir_minus.getDevicePtr( subgrid, index - 1 ) };                   \
                                CALL_SUBGRID_KERNEL_MI( PC3::Kernel::Compute::gp_scalar<GCC_EXPAND_VA_ARGS( false, false, false, false, false, false )>, "K" #index, current_grid, \
                                                     current_block, stream, current_halo, kernel_arguments, io );                                                               \
                                CALL_SUBGRID_KERNEL( PC3::Kernel::Compute::gp_scalar<GCC_EXPAND_VA_ARGS( false, false, false, false, false, false )>, "K" #index, current_grid, \
                                                     current_block, stream, current_halo, kernel_arguments, io );                                                               \
    }
#else
#define CALCULATE_K( index, input_wavefunction, input_reservoir )                                                                                                               \
    {                                                                                                                                                                           \
        const Type::uint32 current_halo = system.p.halo_size - index;                                                                                                           \
        auto [current_block, current_grid] = getLaunchParameters( system.p.subgrid_N_c + 2 * current_halo, system.p.subgrid_N_r + 2 * current_halo );                           \
        Solver::InputOutput io{ matrix.input_wavefunction##_plus.getDevicePtr( subgrid ),      matrix.input_wavefunction##_minus.getDevicePtr( subgrid ),                       \
                                matrix.input_wavefunction##_iplus.getDevicePtr( subgrid ),     matrix.input_wavefunction##_iminus.getDevicePtr( subgrid ),                      \
                                matrix.input_reservoir##_plus.getDevicePtr( subgrid ),         matrix.input_reservoir##_minus.getDevicePtr( subgrid ),                          \
                                matrix.k_wavefunction_plus.getDevicePtr( subgrid, index - 1 ), matrix.k_wavefunction_minus.getDevicePtr( subgrid, index - 1 ),                  \
                                matrix.k_reservoir_plus.getDevicePtr( subgrid, index - 1 ),    matrix.k_reservoir_minus.getDevicePtr( subgrid, index - 1 ) };                   \
                                CALL_SUBGRID_KERNEL( PC3::Kernel::Compute::gp_scalar<GCC_EXPAND_VA_ARGS( false, false, false, false, false, false )>, "K" #index, current_grid, \
                                                     current_block, stream, current_halo, kernel_arguments, io );                                                               \
    }
#endif
#else
#define CALCULATE_K( index, input_wavefunction, input_reservoir )                                                                                                               \
    {                                                                                                                                                                           \
        const Type::uint32 current_halo = system.p.halo_size - index;                                                                                                           \
        auto [current_block, current_grid] = getLaunchParameters( system.p.subgrid_N_c + 2 * current_halo, system.p.subgrid_N_r + 2 * current_halo );                           \
        Solver::InputOutput io{ matrix.input_wavefunction##_plus.getDevicePtr( subgrid ),      matrix.input_wavefunction##_minus.getDevicePtr( subgrid ),                       \
                                matrix.input_reservoir##_plus.getDevicePtr( subgrid ),         matrix.input_reservoir##_minus.getDevicePtr( subgrid ),                          \
                                matrix.k_wavefunction_plus.getDevicePtr( subgrid, index - 1 ), matrix.k_wavefunction_minus.getDevicePtr( subgrid, index - 1 ),                  \
                                matrix.k_reservoir_plus.getDevicePtr( subgrid, index - 1 ),    matrix.k_reservoir_minus.getDevicePtr( subgrid, index - 1 ) };                   \
        if ( not system.use_twin_mode ) {                                                                                                                                       \
            if ( system.use_reservoir ) {                                                                                                                                       \
                if ( system.use_pulses ) {                                                                                                                                      \
                    if ( system.use_pumps ) {                                                                                                                                   \
                        if ( system.use_potentials ) {                                                                                                                          \
                            if ( system.use_stochastic ) {                                                                                                                      \
                                CALL_SUBGRID_KERNEL( PC3::Kernel::Compute::gp_scalar<GCC_EXPAND_VA_ARGS( false, true, true, true, true, true )>, "K" #index, current_grid,      \
                                                     current_block, stream, current_halo, kernel_arguments, io );                                                               \
                            } else {                                                                                                                                            \
                                CALL_SUBGRID_KERNEL( PC3::Kernel::Compute::gp_scalar<GCC_EXPAND_VA_ARGS( false, true, true, true, true, false )>, "K" #index, current_grid,     \
                                                     current_block, stream, current_halo, kernel_arguments, io );                                                               \
                            }                                                                                                                                                   \
                        } else {                                                                                                                                                \
                            if ( system.use_stochastic ) {                                                                                                                      \
                                CALL_SUBGRID_KERNEL( PC3::Kernel::Compute::gp_scalar<GCC_EXPAND_VA_ARGS( false, true, true, true, false, true )>, "K" #index, current_grid,     \
                                                     current_block, stream, current_halo, kernel_arguments, io );                                                               \
                            } else {                                                                                                                                            \
                                CALL_SUBGRID_KERNEL( PC3::Kernel::Compute::gp_scalar<GCC_EXPAND_VA_ARGS( false, true, true, true, false, false )>, "K" #index, current_grid,    \
                                                     current_block, stream, current_halo, kernel_arguments, io );                                                               \
                            }                                                                                                                                                   \
                        }                                                                                                                                                       \
                    } else {                                                                                                                                                    \
                        if ( system.use_potentials ) {                                                                                                                          \
                            if ( system.use_stochastic ) {                                                                                                                      \
                                CALL_SUBGRID_KERNEL( PC3::Kernel::Compute::gp_scalar<GCC_EXPAND_VA_ARGS( false, true, true, false, true, true )>, "K" #index, current_grid,     \
                                                     current_block, stream, current_halo, kernel_arguments, io );                                                               \
                            } else {                                                                                                                                            \
                                CALL_SUBGRID_KERNEL( PC3::Kernel::Compute::gp_scalar<GCC_EXPAND_VA_ARGS( false, true, true, false, true, false )>, "K" #index, current_grid,    \
                                                     current_block, stream, current_halo, kernel_arguments, io );                                                               \
                            }                                                                                                                                                   \
                        } else {                                                                                                                                                \
                            if ( system.use_stochastic ) {                                                                                                                      \
                                CALL_SUBGRID_KERNEL( PC3::Kernel::Compute::gp_scalar<GCC_EXPAND_VA_ARGS( false, true, true, false, false, true )>, "K" #index, current_grid,    \
                                                     current_block, stream, current_halo, kernel_arguments, io );                                                               \
                            } else {                                                                                                                                            \
                                CALL_SUBGRID_KERNEL( PC3::Kernel::Compute::gp_scalar<GCC_EXPAND_VA_ARGS( false, true, true, false, false, false )>, "K" #index, current_grid,   \
                                                     current_block, stream, current_halo, kernel_arguments, io );                                                               \
                            }                                                                                                                                                   \
                        }                                                                                                                                                       \
                    }                                                                                                                                                           \
                } else {                                                                                                                                                        \
                    if ( system.use_pumps ) {                                                                                                                                   \
                        if ( system.use_potentials ) {                                                                                                                          \
                            if ( system.use_stochastic ) {                                                                                                                      \
                                CALL_SUBGRID_KERNEL( PC3::Kernel::Compute::gp_scalar<GCC_EXPAND_VA_ARGS( false, true, false, true, true, true )>, "K" #index, current_grid,     \
                                                     current_block, stream, current_halo, kernel_arguments, io );                                                               \
                            } else {                                                                                                                                            \
                                CALL_SUBGRID_KERNEL( PC3::Kernel::Compute::gp_scalar<GCC_EXPAND_VA_ARGS( false, true, false, true, true, false )>, "K" #index, current_grid,    \
                                                     current_block, stream, current_halo, kernel_arguments, io );                                                               \
                            }                                                                                                                                                   \
                        } else {                                                                                                                                                \
                            if ( system.use_stochastic ) {                                                                                                                      \
                                CALL_SUBGRID_KERNEL( PC3::Kernel::Compute::gp_scalar<GCC_EXPAND_VA_ARGS( false, true, false, true, false, true )>, "K" #index, current_grid,    \
                                                     current_block, stream, current_halo, kernel_arguments, io );                                                               \
                            } else {                                                                                                                                            \
                                CALL_SUBGRID_KERNEL( PC3::Kernel::Compute::gp_scalar<GCC_EXPAND_VA_ARGS( false, true, false, true, false, false )>, "K" #index, current_grid,   \
                                                     current_block, stream, current_halo, kernel_arguments, io );                                                               \
                            }                                                                                                                                                   \
                        }                                                                                                                                                       \
                    } else {                                                                                                                                                    \
                        if ( system.use_potentials ) {                                                                                                                          \
                            if ( system.use_stochastic ) {                                                                                                                      \
                                CALL_SUBGRID_KERNEL( PC3::Kernel::Compute::gp_scalar<GCC_EXPAND_VA_ARGS( false, true, false, false, true, true )>, "K" #index, current_grid,    \
                                                     current_block, stream, current_halo, kernel_arguments, io );                                                               \
                            } else {                                                                                                                                            \
                                CALL_SUBGRID_KERNEL( PC3::Kernel::Compute::gp_scalar<GCC_EXPAND_VA_ARGS( false, true, false, false, true, false )>, "K" #index, current_grid,   \
                                                     current_block, stream, current_halo, kernel_arguments, io );                                                               \
                            }                                                                                                                                                   \
                        } else {                                                                                                                                                \
                            if ( system.use_stochastic ) {                                                                                                                      \
                                CALL_SUBGRID_KERNEL( PC3::Kernel::Compute::gp_scalar<GCC_EXPAND_VA_ARGS( false, true, false, false, false, true )>, "K" #index, current_grid,   \
                                                     current_block, stream, current_halo, kernel_arguments, io );                                                               \
                            } else {                                                                                                                                            \
                                CALL_SUBGRID_KERNEL( PC3::Kernel::Compute::gp_scalar<GCC_EXPAND_VA_ARGS( false, true, false, false, false, false )>, "K" #index, current_grid,  \
                                                     current_block, stream, current_halo, kernel_arguments, io );                                                               \
                            }                                                                                                                                                   \
                        }                                                                                                                                                       \
                    }                                                                                                                                                           \
                }                                                                                                                                                               \
            } else {                                                                                                                                                            \
                if ( system.use_pulses ) {                                                                                                                                      \
                    if ( system.use_pumps ) {                                                                                                                                   \
                        if ( system.use_potentials ) {                                                                                                                          \
                            if ( system.use_stochastic ) {                                                                                                                      \
                                CALL_SUBGRID_KERNEL( PC3::Kernel::Compute::gp_scalar<GCC_EXPAND_VA_ARGS( false, false, true, true, true, true )>, "K" #index, current_grid,     \
                                                     current_block, stream, current_halo, kernel_arguments, io );                                                               \
                            } else {                                                                                                                                            \
                                CALL_SUBGRID_KERNEL( PC3::Kernel::Compute::gp_scalar<GCC_EXPAND_VA_ARGS( false, false, true, true, true, false )>, "K" #index, current_grid,    \
                                                     current_block, stream, current_halo, kernel_arguments, io );                                                               \
                            }                                                                                                                                                   \
                        } else {                                                                                                                                                \
                            if ( system.use_stochastic ) {                                                                                                                      \
                                CALL_SUBGRID_KERNEL( PC3::Kernel::Compute::gp_scalar<GCC_EXPAND_VA_ARGS( false, false, true, true, false, true )>, "K" #index, current_grid,    \
                                                     current_block, stream, current_halo, kernel_arguments, io );                                                               \
                            } else {                                                                                                                                            \
                                CALL_SUBGRID_KERNEL( PC3::Kernel::Compute::gp_scalar<GCC_EXPAND_VA_ARGS( false, false, true, true, false, false )>, "K" #index, current_grid,   \
                                                     current_block, stream, current_halo, kernel_arguments, io );                                                               \
                            }                                                                                                                                                   \
                        }                                                                                                                                                       \
                    } else {                                                                                                                                                    \
                        if ( system.use_potentials ) {                                                                                                                          \
                            if ( system.use_stochastic ) {                                                                                                                      \
                                CALL_SUBGRID_KERNEL( PC3::Kernel::Compute::gp_scalar<GCC_EXPAND_VA_ARGS( false, false, true, false, true, true )>, "K" #index, current_grid,    \
                                                     current_block, stream, current_halo, kernel_arguments, io );                                                               \
                            } else {                                                                                                                                            \
                                CALL_SUBGRID_KERNEL( PC3::Kernel::Compute::gp_scalar<GCC_EXPAND_VA_ARGS( false, false, true, false, true, false )>, "K" #index, current_grid,   \
                                                     current_block, stream, current_halo, kernel_arguments, io );                                                               \
                            }                                                                                                                                                   \
                        } else {                                                                                                                                                \
                            if ( system.use_stochastic ) {                                                                                                                      \
                                CALL_SUBGRID_KERNEL( PC3::Kernel::Compute::gp_scalar<GCC_EXPAND_VA_ARGS( false, false, true, false, false, true )>, "K" #index, current_grid,   \
                                                     current_block, stream, current_halo, kernel_arguments, io );                                                               \
                            } else {                                                                                                                                            \
                                CALL_SUBGRID_KERNEL( PC3::Kernel::Compute::gp_scalar<GCC_EXPAND_VA_ARGS( false, false, true, false, false, false )>, "K" #index, current_grid,  \
                                                     current_block, stream, current_halo, kernel_arguments, io );                                                               \
                            }                                                                                                                                                   \
                        }                                                                                                                                                       \
                    }                                                                                                                                                           \
                } else {                                                                                                                                                        \
                    if ( system.use_pumps ) {                                                                                                                                   \
                        if ( system.use_potentials ) {                                                                                                                          \
                            if ( system.use_stochastic ) {                                                                                                                      \
                                CALL_SUBGRID_KERNEL( PC3::Kernel::Compute::gp_scalar<GCC_EXPAND_VA_ARGS( false, false, false, true, true, true )>, "K" #index, current_grid,    \
                                                     current_block, stream, current_halo, kernel_arguments, io );                                                               \
                            } else {                                                                                                                                            \
                                CALL_SUBGRID_KERNEL( PC3::Kernel::Compute::gp_scalar<GCC_EXPAND_VA_ARGS( false, false, false, true, true, false )>, "K" #index, current_grid,   \
                                                     current_block, stream, current_halo, kernel_arguments, io );                                                               \
                            }                                                                                                                                                   \
                        } else {                                                                                                                                                \
                            if ( system.use_stochastic ) {                                                                                                                      \
                                CALL_SUBGRID_KERNEL( PC3::Kernel::Compute::gp_scalar<GCC_EXPAND_VA_ARGS( false, false, false, true, false, true )>, "K" #index, current_grid,   \
                                                     current_block, stream, current_halo, kernel_arguments, io );                                                               \
                            } else {                                                                                                                                            \
                                CALL_SUBGRID_KERNEL( PC3::Kernel::Compute::gp_scalar<GCC_EXPAND_VA_ARGS( false, false, false, true, false, false )>, "K" #index, current_grid,  \
                                                     current_block, stream, current_halo, kernel_arguments, io );                                                               \
                            }                                                                                                                                                   \
                        }                                                                                                                                                       \
                    } else {                                                                                                                                                    \
                        if ( system.use_potentials ) {                                                                                                                          \
                            if ( system.use_stochastic ) {                                                                                                                      \
                                CALL_SUBGRID_KERNEL( PC3::Kernel::Compute::gp_scalar<GCC_EXPAND_VA_ARGS( false, false, false, false, true, true )>, "K" #index, current_grid,   \
                                                     current_block, stream, current_halo, kernel_arguments, io );                                                               \
                            } else {                                                                                                                                            \
                                CALL_SUBGRID_KERNEL( PC3::Kernel::Compute::gp_scalar<GCC_EXPAND_VA_ARGS( false, false, false, false, true, false )>, "K" #index, current_grid,  \
                                                     current_block, stream, current_halo, kernel_arguments, io );                                                               \
                            }                                                                                                                                                   \
                        } else {                                                                                                                                                \
                            if ( system.use_stochastic ) {                                                                                                                      \
                                CALL_SUBGRID_KERNEL( PC3::Kernel::Compute::gp_scalar<GCC_EXPAND_VA_ARGS( false, false, false, false, false, true )>, "K" #index, current_grid,  \
                                                     current_block, stream, current_halo, kernel_arguments, io );                                                               \
                            } else {                                                                                                                                            \
                                CALL_SUBGRID_KERNEL( PC3::Kernel::Compute::gp_scalar<GCC_EXPAND_VA_ARGS( false, false, false, false, false, false )>, "K" #index, current_grid, \
                                                     current_block, stream, current_halo, kernel_arguments, io );                                                               \
                            }                                                                                                                                                   \
                        }                                                                                                                                                       \
                    }                                                                                                                                                           \
                }                                                                                                                                                               \
            }                                                                                                                                                                   \
        } else {                                                                                                                                                                \
            if ( system.use_reservoir ) {                                                                                                                                       \
                if ( system.use_pulses ) {                                                                                                                                      \
                    if ( system.use_pumps ) {                                                                                                                                   \
                        if ( system.use_potentials ) {                                                                                                                          \
                            if ( system.use_stochastic ) {                                                                                                                      \
                                CALL_SUBGRID_KERNEL( PC3::Kernel::Compute::gp_scalar<GCC_EXPAND_VA_ARGS( true, true, true, true, true, true )>, "K" #index, current_grid,       \
                                                     current_block, stream, current_halo, kernel_arguments, io );                                                               \
                            } else {                                                                                                                                            \
                                CALL_SUBGRID_KERNEL( PC3::Kernel::Compute::gp_scalar<GCC_EXPAND_VA_ARGS( true, true, true, true, true, false )>, "K" #index, current_grid,      \
                                                     current_block, stream, current_halo, kernel_arguments, io );                                                               \
                            }                                                                                                                                                   \
                        } else {                                                                                                                                                \
                            if ( system.use_stochastic ) {                                                                                                                      \
                                CALL_SUBGRID_KERNEL( PC3::Kernel::Compute::gp_scalar<GCC_EXPAND_VA_ARGS( true, true, true, true, false, true )>, "K" #index, current_grid,      \
                                                     current_block, stream, current_halo, kernel_arguments, io );                                                               \
                            } else {                                                                                                                                            \
                                CALL_SUBGRID_KERNEL( PC3::Kernel::Compute::gp_scalar<GCC_EXPAND_VA_ARGS( true, true, true, true, false, false )>, "K" #index, current_grid,     \
                                                     current_block, stream, current_halo, kernel_arguments, io );                                                               \
                            }                                                                                                                                                   \
                        }                                                                                                                                                       \
                    } else {                                                                                                                                                    \
                        if ( system.use_potentials ) {                                                                                                                          \
                            if ( system.use_stochastic ) {                                                                                                                      \
                                CALL_SUBGRID_KERNEL( PC3::Kernel::Compute::gp_scalar<GCC_EXPAND_VA_ARGS( true, true, true, false, true, true )>, "K" #index, current_grid,      \
                                                     current_block, stream, current_halo, kernel_arguments, io );                                                               \
                            } else {                                                                                                                                            \
                                CALL_SUBGRID_KERNEL( PC3::Kernel::Compute::gp_scalar<GCC_EXPAND_VA_ARGS( true, true, true, false, true, false )>, "K" #index, current_grid,     \
                                                     current_block, stream, current_halo, kernel_arguments, io );                                                               \
                            }                                                                                                                                                   \
                        } else {                                                                                                                                                \
                            if ( system.use_stochastic ) {                                                                                                                      \
                                CALL_SUBGRID_KERNEL( PC3::Kernel::Compute::gp_scalar<GCC_EXPAND_VA_ARGS( true, true, true, false, false, true )>, "K" #index, current_grid,     \
                                                     current_block, stream, current_halo, kernel_arguments, io );                                                               \
                            } else {                                                                                                                                            \
                                CALL_SUBGRID_KERNEL( PC3::Kernel::Compute::gp_scalar<GCC_EXPAND_VA_ARGS( true, true, true, false, false, false )>, "K" #index, current_grid,    \
                                                     current_block, stream, current_halo, kernel_arguments, io );                                                               \
                            }                                                                                                                                                   \
                        }                                                                                                                                                       \
                    }                                                                                                                                                           \
                } else {                                                                                                                                                        \
                    if ( system.use_pumps ) {                                                                                                                                   \
                        if ( system.use_potentials ) {                                                                                                                          \
                            if ( system.use_stochastic ) {                                                                                                                      \
                                CALL_SUBGRID_KERNEL( PC3::Kernel::Compute::gp_scalar<GCC_EXPAND_VA_ARGS( true, true, false, true, true, true )>, "K" #index, current_grid,      \
                                                     current_block, stream, current_halo, kernel_arguments, io );                                                               \
                            } else {                                                                                                                                            \
                                CALL_SUBGRID_KERNEL( PC3::Kernel::Compute::gp_scalar<GCC_EXPAND_VA_ARGS( true, true, false, true, true, false )>, "K" #index, current_grid,     \
                                                     current_block, stream, current_halo, kernel_arguments, io );                                                               \
                            }                                                                                                                                                   \
                        } else {                                                                                                                                                \
                            if ( system.use_stochastic ) {                                                                                                                      \
                                CALL_SUBGRID_KERNEL( PC3::Kernel::Compute::gp_scalar<GCC_EXPAND_VA_ARGS( true, true, false, true, false, true )>, "K" #index, current_grid,     \
                                                     current_block, stream, current_halo, kernel_arguments, io );                                                               \
                            } else {                                                                                                                                            \
                                CALL_SUBGRID_KERNEL( PC3::Kernel::Compute::gp_scalar<GCC_EXPAND_VA_ARGS( true, true, false, true, false, false )>, "K" #index, current_grid,    \
                                                     current_block, stream, current_halo, kernel_arguments, io );                                                               \
                            }                                                                                                                                                   \
                        }                                                                                                                                                       \
                    } else {                                                                                                                                                    \
                        if ( system.use_potentials ) {                                                                                                                          \
                            if ( system.use_stochastic ) {                                                                                                                      \
                                CALL_SUBGRID_KERNEL( PC3::Kernel::Compute::gp_scalar<GCC_EXPAND_VA_ARGS( true, true, false, false, true, true )>, "K" #index, current_grid,     \
                                                     current_block, stream, current_halo, kernel_arguments, io );                                                               \
                            } else {                                                                                                                                            \
                                CALL_SUBGRID_KERNEL( PC3::Kernel::Compute::gp_scalar<GCC_EXPAND_VA_ARGS( true, true, false, false, true, false )>, "K" #index, current_grid,    \
                                                     current_block, stream, current_halo, kernel_arguments, io );                                                               \
                            }                                                                                                                                                   \
                        } else {                                                                                                                                                \
                            if ( system.use_stochastic ) {                                                                                                                      \
                                CALL_SUBGRID_KERNEL( PC3::Kernel::Compute::gp_scalar<GCC_EXPAND_VA_ARGS( true, true, false, false, false, true )>, "K" #index, current_grid,    \
                                                     current_block, stream, current_halo, kernel_arguments, io );                                                               \
                            } else {                                                                                                                                            \
                                CALL_SUBGRID_KERNEL( PC3::Kernel::Compute::gp_scalar<GCC_EXPAND_VA_ARGS( true, true, false, false, false, false )>, "K" #index, current_grid,   \
                                                     current_block, stream, current_halo, kernel_arguments, io );                                                               \
                            }                                                                                                                                                   \
                        }                                                                                                                                                       \
                    }                                                                                                                                                           \
                }                                                                                                                                                               \
            } else {                                                                                                                                                            \
                if ( system.use_pulses ) {                                                                                                                                      \
                    if ( system.use_pumps ) {                                                                                                                                   \
                        if ( system.use_potentials ) {                                                                                                                          \
                            if ( system.use_stochastic ) {                                                                                                                      \
                                CALL_SUBGRID_KERNEL( PC3::Kernel::Compute::gp_scalar<GCC_EXPAND_VA_ARGS( true, false, true, true, true, true )>, "K" #index, current_grid,      \
                                                     current_block, stream, current_halo, kernel_arguments, io );                                                               \
                            } else {                                                                                                                                            \
                                CALL_SUBGRID_KERNEL( PC3::Kernel::Compute::gp_scalar<GCC_EXPAND_VA_ARGS( true, false, true, true, true, false )>, "K" #index, current_grid,     \
                                                     current_block, stream, current_halo, kernel_arguments, io );                                                               \
                            }                                                                                                                                                   \
                        } else {                                                                                                                                                \
                            if ( system.use_stochastic ) {                                                                                                                      \
                                CALL_SUBGRID_KERNEL( PC3::Kernel::Compute::gp_scalar<GCC_EXPAND_VA_ARGS( true, false, true, true, false, true )>, "K" #index, current_grid,     \
                                                     current_block, stream, current_halo, kernel_arguments, io );                                                               \
                            } else {                                                                                                                                            \
                                CALL_SUBGRID_KERNEL( PC3::Kernel::Compute::gp_scalar<GCC_EXPAND_VA_ARGS( true, false, true, true, false, false )>, "K" #index, current_grid,    \
                                                     current_block, stream, current_halo, kernel_arguments, io );                                                               \
                            }                                                                                                                                                   \
                        }                                                                                                                                                       \
                    } else {                                                                                                                                                    \
                        if ( system.use_potentials ) {                                                                                                                          \
                            if ( system.use_stochastic ) {                                                                                                                      \
                                CALL_SUBGRID_KERNEL( PC3::Kernel::Compute::gp_scalar<GCC_EXPAND_VA_ARGS( true, false, true, false, true, true )>, "K" #index, current_grid,     \
                                                     current_block, stream, current_halo, kernel_arguments, io );                                                               \
                            } else {                                                                                                                                            \
                                CALL_SUBGRID_KERNEL( PC3::Kernel::Compute::gp_scalar<GCC_EXPAND_VA_ARGS( true, false, true, false, true, false )>, "K" #index, current_grid,    \
                                                     current_block, stream, current_halo, kernel_arguments, io );                                                               \
                            }                                                                                                                                                   \
                        } else {                                                                                                                                                \
                            if ( system.use_stochastic ) {                                                                                                                      \
                                CALL_SUBGRID_KERNEL( PC3::Kernel::Compute::gp_scalar<GCC_EXPAND_VA_ARGS( true, false, true, false, false, true )>, "K" #index, current_grid,    \
                                                     current_block, stream, current_halo, kernel_arguments, io );                                                               \
                            } else {                                                                                                                                            \
                                CALL_SUBGRID_KERNEL( PC3::Kernel::Compute::gp_scalar<GCC_EXPAND_VA_ARGS( true, false, true, false, false, false )>, "K" #index, current_grid,   \
                                                     current_block, stream, current_halo, kernel_arguments, io );                                                               \
                            }                                                                                                                                                   \
                        }                                                                                                                                                       \
                    }                                                                                                                                                           \
                } else {                                                                                                                                                        \
                    if ( system.use_pumps ) {                                                                                                                                   \
                        if ( system.use_potentials ) {                                                                                                                          \
                            if ( system.use_stochastic ) {                                                                                                                      \
                                CALL_SUBGRID_KERNEL( PC3::Kernel::Compute::gp_scalar<GCC_EXPAND_VA_ARGS( true, false, false, true, true, true )>, "K" #index, current_grid,     \
                                                     current_block, stream, current_halo, kernel_arguments, io );                                                               \
                            } else {                                                                                                                                            \
                                CALL_SUBGRID_KERNEL( PC3::Kernel::Compute::gp_scalar<GCC_EXPAND_VA_ARGS( true, false, false, true, true, false )>, "K" #index, current_grid,    \
                                                     current_block, stream, current_halo, kernel_arguments, io );                                                               \
                            }                                                                                                                                                   \
                        } else {                                                                                                                                                \
                            if ( system.use_stochastic ) {                                                                                                                      \
                                CALL_SUBGRID_KERNEL( PC3::Kernel::Compute::gp_scalar<GCC_EXPAND_VA_ARGS( true, false, false, true, false, true )>, "K" #index, current_grid,    \
                                                     current_block, stream, current_halo, kernel_arguments, io );                                                               \
                            } else {                                                                                                                                            \
                                CALL_SUBGRID_KERNEL( PC3::Kernel::Compute::gp_scalar<GCC_EXPAND_VA_ARGS( true, false, false, true, false, false )>, "K" #index, current_grid,   \
                                                     current_block, stream, current_halo, kernel_arguments, io );                                                               \
                            }                                                                                                                                                   \
                        }                                                                                                                                                       \
                    } else {                                                                                                                                                    \
                        if ( system.use_potentials ) {                                                                                                                          \
                            if ( system.use_stochastic ) {                                                                                                                      \
                                CALL_SUBGRID_KERNEL( PC3::Kernel::Compute::gp_scalar<GCC_EXPAND_VA_ARGS( true, false, false, false, true, true )>, "K" #index, current_grid,    \
                                                     current_block, stream, current_halo, kernel_arguments, io );                                                               \
                            } else {                                                                                                                                            \
                                CALL_SUBGRID_KERNEL( PC3::Kernel::Compute::gp_scalar<GCC_EXPAND_VA_ARGS( true, false, false, false, true, false )>, "K" #index, current_grid,   \
                                                     current_block, stream, current_halo, kernel_arguments, io );                                                               \
                            }                                                                                                                                                   \
                        } else {                                                                                                                                                \
                            if ( system.use_stochastic ) {                                                                                                                      \
                                CALL_SUBGRID_KERNEL( PC3::Kernel::Compute::gp_scalar<GCC_EXPAND_VA_ARGS( true, false, false, false, false, true )>, "K" #index, current_grid,   \
                                                     current_block, stream, current_halo, kernel_arguments, io );                                                               \
                            } else {                                                                                                                                            \
                                CALL_SUBGRID_KERNEL( PC3::Kernel::Compute::gp_scalar<GCC_EXPAND_VA_ARGS( true, false, false, false, false, false )>, "K" #index, current_grid,  \
                                                     current_block, stream, current_halo, kernel_arguments, io );                                                               \
                            }                                                                                                                                                   \
                        }                                                                                                                                                       \
                    }                                                                                                                                                           \
                }                                                                                                                                                               \
            }                                                                                                                                                                   \
        }                                                                                                                                                                       \
    }

#endif
#endif
// Only Callable from within the solver
#ifdef NO_INTERMEDIATE_SUM_K
#define INTERMEDIATE_SUM_K( index, ... )                                                                                                                                          \
    {                                                                                                                                                                             \
    };
#else
#ifdef BENCH
#define INTERMEDIATE_SUM_K( index, ... )                                                                                                                                          \
    {                                                                                                                                                                             \
        const Type::uint32 current_halo = system.p.halo_size - index;                                                                                                             \
        auto [current_block, current_grid] = getLaunchParameters( system.p.subgrid_N_c + 2 * current_halo, system.p.subgrid_N_r + 2 * current_halo );                             \
        Solver::InputOutput io{ matrix.wavefunction_plus.getDevicePtr( subgrid ),        matrix.wavefunction_minus.getDevicePtr( subgrid ),                                       \
                                matrix.wavefunction##_iplus.getDevicePtr( subgrid ),     matrix.wavefunction##_iminus.getDevicePtr( subgrid ),                      \
                                matrix.reservoir_plus.getDevicePtr( subgrid ),           matrix.reservoir_minus.getDevicePtr( subgrid ),                                          \
                                matrix.buffer_wavefunction_plus.getDevicePtr( subgrid ), matrix.buffer_wavefunction_minus.getDevicePtr( subgrid ),                                \
                                matrix.buffer_reservoir_plus.getDevicePtr( subgrid ),    matrix.buffer_reservoir_minus.getDevicePtr( subgrid ) };                                 \
        Type::complex *k_vec_wf_plus = matrix.k_wavefunction_plus.getDevicePtr( subgrid );                                                                                        \
                    CALL_SUBGRID_KERNEL( Kernel::Summation::runge_sum_to_input_k<GCC_EXPAND_VA_ARGS_ORDER( Type::complex, false, false, false, index, __VA_ARGS__ )>,             \
                                         "Sum for K" #index, current_grid, current_block, stream, current_halo, kernel_arguments, io.in_wf_plus, io.out_wf_plus, k_vec_wf_plus ); \
    };
#else
#define INTERMEDIATE_SUM_K( index, ... )                                                                                                                                          \
    {                                                                                                                                                                             \
        const Type::uint32 current_halo = system.p.halo_size - index;                                                                                                             \
        auto [current_block, current_grid] = getLaunchParameters( system.p.subgrid_N_c + 2 * current_halo, system.p.subgrid_N_r + 2 * current_halo );                             \
        Solver::InputOutput io{ matrix.wavefunction_plus.getDevicePtr( subgrid ),        matrix.wavefunction_minus.getDevicePtr( subgrid ),                                       \
                                matrix.reservoir_plus.getDevicePtr( subgrid ),           matrix.reservoir_minus.getDevicePtr( subgrid ),                                          \
                                matrix.buffer_wavefunction_plus.getDevicePtr( subgrid ), matrix.buffer_wavefunction_minus.getDevicePtr( subgrid ),                                \
                                matrix.buffer_reservoir_plus.getDevicePtr( subgrid ),    matrix.buffer_reservoir_minus.getDevicePtr( subgrid ) };                                 \
        Type::complex *k_vec_wf_plus = matrix.k_wavefunction_plus.getDevicePtr( subgrid );                                                                                        \
        if ( system.use_reservoir ) {                                                                                                                                             \
            if ( system.use_stochastic ) {                                                                                                                                        \
                if ( system.imag_time_amplitude == 0.0 ) {                                                                                                                        \
                    CALL_SUBGRID_KERNEL( Kernel::Summation::runge_sum_to_input_k<GCC_EXPAND_VA_ARGS_ORDER( Type::complex, false, true, true, index, __VA_ARGS__ )>,               \
                                         "Sum for K" #index, current_grid, current_block, stream, current_halo, kernel_arguments, io.in_wf_plus, io.out_wf_plus, k_vec_wf_plus ); \
                } else {                                                                                                                                                          \
                    CALL_SUBGRID_KERNEL( Kernel::Summation::runge_sum_to_input_k<GCC_EXPAND_VA_ARGS_ORDER( Type::complex, true, true, true, index, __VA_ARGS__ )>,                \
                                         "Sum for K" #index, current_grid, current_block, stream, current_halo, kernel_arguments, io.in_wf_plus, io.out_wf_plus, k_vec_wf_plus ); \
                }                                                                                                                                                                 \
            } else {                                                                                                                                                              \
                if ( system.imag_time_amplitude == 0.0 ) {                                                                                                                        \
                    CALL_SUBGRID_KERNEL( Kernel::Summation::runge_sum_to_input_k<GCC_EXPAND_VA_ARGS_ORDER( Type::complex, false, false, true, index, __VA_ARGS__ )>,              \
                                         "Sum for K" #index, current_grid, current_block, stream, current_halo, kernel_arguments, io.in_wf_plus, io.out_wf_plus, k_vec_wf_plus ); \
                } else {                                                                                                                                                          \
                    CALL_SUBGRID_KERNEL( Kernel::Summation::runge_sum_to_input_k<GCC_EXPAND_VA_ARGS_ORDER( Type::complex, true, false, true, index, __VA_ARGS__ )>,               \
                                         "Sum for K" #index, current_grid, current_block, stream, current_halo, kernel_arguments, io.in_wf_plus, io.out_wf_plus, k_vec_wf_plus ); \
                }                                                                                                                                                                 \
            }                                                                                                                                                                     \
            Type::complex *k_vec_res_plus = matrix.k_reservoir_plus.getDevicePtr( subgrid );                                                                                      \
            if ( system.imag_time_amplitude == 0.0 ) {                                                                                                                            \
                CALL_SUBGRID_KERNEL( Kernel::Summation::runge_sum_to_input_k<GCC_EXPAND_VA_ARGS_ORDER( Type::complex, false, false, true, index, __VA_ARGS__ )>,                  \
                                     "Sum for K" #index, current_grid, current_block, stream, current_halo, kernel_arguments, io.in_rv_plus, io.out_rv_plus, k_vec_res_plus );    \
            } else {                                                                                                                                                              \
                CALL_SUBGRID_KERNEL( Kernel::Summation::runge_sum_to_input_k<GCC_EXPAND_VA_ARGS_ORDER( Type::complex, true, false, true, index, __VA_ARGS__ )>,                   \
                                     "Sum for K" #index, current_grid, current_block, stream, current_halo, kernel_arguments, io.in_rv_plus, io.out_rv_plus, k_vec_res_plus );    \
            }                                                                                                                                                                     \
            if ( system.use_twin_mode ) {                                                                                                                                         \
                Type::complex *k_vec_wf_minus = matrix.k_wavefunction_minus.getDevicePtr( subgrid );                                                                              \
                if ( system.use_stochastic ) {                                                                                                                                    \
                    if ( system.imag_time_amplitude == 0.0 ) {                                                                                                                    \
                        CALL_SUBGRID_KERNEL( Kernel::Summation::runge_sum_to_input_k<GCC_EXPAND_VA_ARGS_ORDER( Type::complex, false, true, true, index, __VA_ARGS__ )>,           \
                                             "Sum for K" #index, current_grid, current_block, stream, current_halo, kernel_arguments, io.in_wf_minus, io.out_wf_minus,            \
                                             k_vec_wf_minus );                                                                                                                    \
                    } else {                                                                                                                                                      \
                        CALL_SUBGRID_KERNEL( Kernel::Summation::runge_sum_to_input_k<GCC_EXPAND_VA_ARGS_ORDER( Type::complex, true, true, true, index, __VA_ARGS__ )>,            \
                                             "Sum for K" #index, current_grid, current_block, stream, current_halo, kernel_arguments, io.in_wf_minus, io.out_wf_minus,            \
                                             k_vec_wf_minus );                                                                                                                    \
                    }                                                                                                                                                             \
                } else {                                                                                                                                                          \
                    if ( system.imag_time_amplitude == 0.0 ) {                                                                                                                    \
                        CALL_SUBGRID_KERNEL( Kernel::Summation::runge_sum_to_input_k<GCC_EXPAND_VA_ARGS_ORDER( Type::complex, false, false, true, index, __VA_ARGS__ )>,          \
                                             "Sum for K" #index, current_grid, current_block, stream, current_halo, kernel_arguments, io.in_wf_minus, io.out_wf_minus,            \
                                             k_vec_wf_minus );                                                                                                                    \
                    } else {                                                                                                                                                      \
                        CALL_SUBGRID_KERNEL( Kernel::Summation::runge_sum_to_input_k<GCC_EXPAND_VA_ARGS_ORDER( Type::complex, true, false, true, index, __VA_ARGS__ )>,           \
                                             "Sum for K" #index, current_grid, current_block, stream, current_halo, kernel_arguments, io.in_wf_minus, io.out_wf_minus,            \
                                             k_vec_wf_minus );                                                                                                                    \
                    }                                                                                                                                                             \
                }                                                                                                                                                                 \
                Type::complex *k_vec_res_minus = matrix.k_reservoir_minus.getDevicePtr( subgrid );                                                                                \
                if ( system.imag_time_amplitude == 0.0 ) {                                                                                                                        \
                    CALL_SUBGRID_KERNEL( Kernel::Summation::runge_sum_to_input_k<GCC_EXPAND_VA_ARGS_ORDER( Type::complex, false, false, true, index, __VA_ARGS__ )>,              \
                                         "Sum for K" #index, current_grid, current_block, stream, current_halo, kernel_arguments, io.in_rv_minus, io.out_rv_minus,                \
                                         k_vec_res_minus );                                                                                                                       \
                } else {                                                                                                                                                          \
                    CALL_SUBGRID_KERNEL( Kernel::Summation::runge_sum_to_input_k<GCC_EXPAND_VA_ARGS_ORDER( Type::complex, true, false, true, index, __VA_ARGS__ )>,               \
                                         "Sum for K" #index, current_grid, current_block, stream, current_halo, kernel_arguments, io.in_rv_minus, io.out_rv_minus,                \
                                         k_vec_res_minus );                                                                                                                       \
                }                                                                                                                                                                 \
            }                                                                                                                                                                     \
        } else {                                                                                                                                                                  \
            if ( system.use_stochastic ) {                                                                                                                                        \
                if ( system.imag_time_amplitude == 0.0 ) {                                                                                                                        \
                    CALL_SUBGRID_KERNEL( Kernel::Summation::runge_sum_to_input_k<GCC_EXPAND_VA_ARGS_ORDER( Type::complex, false, true, false, index, __VA_ARGS__ )>,              \
                                         "Sum for K" #index, current_grid, current_block, stream, current_halo, kernel_arguments, io.in_wf_plus, io.out_wf_plus, k_vec_wf_plus ); \
                } else {                                                                                                                                                          \
                    CALL_SUBGRID_KERNEL( Kernel::Summation::runge_sum_to_input_k<GCC_EXPAND_VA_ARGS_ORDER( Type::complex, true, true, false, index, __VA_ARGS__ )>,               \
                                         "Sum for K" #index, current_grid, current_block, stream, current_halo, kernel_arguments, io.in_wf_plus, io.out_wf_plus, k_vec_wf_plus ); \
                }                                                                                                                                                                 \
            } else {                                                                                                                                                              \
                if ( system.imag_time_amplitude == 0.0 ) {                                                                                                                        \
                    CALL_SUBGRID_KERNEL( Kernel::Summation::runge_sum_to_input_k<GCC_EXPAND_VA_ARGS_ORDER( Type::complex, false, false, false, index, __VA_ARGS__ )>,             \
                                         "Sum for K" #index, current_grid, current_block, stream, current_halo, kernel_arguments, io.in_wf_plus, io.out_wf_plus, k_vec_wf_plus ); \
                } else {                                                                                                                                                          \
                    CALL_SUBGRID_KERNEL( Kernel::Summation::runge_sum_to_input_k<GCC_EXPAND_VA_ARGS_ORDER( Type::complex, true, false, false, index, __VA_ARGS__ )>,              \
                                         "Sum for K" #index, current_grid, current_block, stream, current_halo, kernel_arguments, io.in_wf_plus, io.out_wf_plus, k_vec_wf_plus ); \
                }                                                                                                                                                                 \
            }                                                                                                                                                                     \
            if ( system.use_twin_mode ) {                                                                                                                                         \
                Type::complex *k_vec_wf_minus = matrix.k_wavefunction_minus.getDevicePtr( subgrid );                                                                              \
                if ( system.use_stochastic ) {                                                                                                                                    \
                    if ( system.imag_time_amplitude == 0.0 ) {                                                                                                                    \
                        CALL_SUBGRID_KERNEL( Kernel::Summation::runge_sum_to_input_k<GCC_EXPAND_VA_ARGS_ORDER( Type::complex, false, true, false, index, __VA_ARGS__ )>,          \
                                             "Sum for K" #index, current_grid, current_block, stream, current_halo, kernel_arguments, io.in_wf_minus, io.out_wf_minus,            \
                                             k_vec_wf_minus );                                                                                                                    \
                    } else {                                                                                                                                                      \
                        CALL_SUBGRID_KERNEL( Kernel::Summation::runge_sum_to_input_k<GCC_EXPAND_VA_ARGS_ORDER( Type::complex, true, true, false, index, __VA_ARGS__ )>,           \
                                             "Sum for K" #index, current_grid, current_block, stream, current_halo, kernel_arguments, io.in_wf_minus, io.out_wf_minus,            \
                                             k_vec_wf_minus );                                                                                                                    \
                    }                                                                                                                                                             \
                } else {                                                                                                                                                          \
                    if ( system.imag_time_amplitude == 0.0 ) {                                                                                                                    \
                        CALL_SUBGRID_KERNEL( Kernel::Summation::runge_sum_to_input_k<GCC_EXPAND_VA_ARGS_ORDER( Type::complex, false, false, false, index, __VA_ARGS__ )>,         \
                                             "Sum for K" #index, current_grid, current_block, stream, current_halo, kernel_arguments, io.in_wf_minus, io.out_wf_minus,            \
                                             k_vec_wf_minus );                                                                                                                    \
                    } else {                                                                                                                                                      \
                        CALL_SUBGRID_KERNEL( Kernel::Summation::runge_sum_to_input_k<GCC_EXPAND_VA_ARGS_ORDER( Type::complex, true, false, false, index, __VA_ARGS__ )>,          \
                                             "Sum for K" #index, current_grid, current_block, stream, current_halo, kernel_arguments, io.in_wf_minus, io.out_wf_minus,            \
                                             k_vec_wf_minus );                                                                                                                    \
                    }                                                                                                                                                             \
                }                                                                                                                                                                 \
            }                                                                                                                                                                     \
        }                                                                                                                                                                         \
    };
#endif
#endif
// Only Callable from within the solver
#ifdef NO_FINAL_SUM_K
#define FINAL_SUM_K( index, ... )                                                                                                                                         \
    {                                                                                                                                                                     \
    };
#else
#ifdef BENCH
#define FINAL_SUM_K( index, ... )                                                                                                                                         \
    {                                                                                                                                                                     \
        Type::uint32 current_halo = system.p.halo_size;                                                                                                                   \
        auto [current_block, current_grid] = getLaunchParameters( system.p.subgrid_N_c + 2 * current_halo, system.p.subgrid_N_r + 2 * current_halo );                     \
        Solver::InputOutput io{ matrix.wavefunction_plus.getDevicePtr( subgrid ), matrix.wavefunction_minus.getDevicePtr( subgrid ),                                      \
                                matrix.wavefunction##_iplus.getDevicePtr( subgrid ),     matrix.wavefunction##_iminus.getDevicePtr( subgrid ),                      \
                                matrix.reservoir_plus.getDevicePtr( subgrid ),    matrix.reservoir_minus.getDevicePtr( subgrid ),                                         \
                                matrix.wavefunction_plus.getDevicePtr( subgrid ), matrix.wavefunction_minus.getDevicePtr( subgrid ),                                      \
                                matrix.reservoir_plus.getDevicePtr( subgrid ),    matrix.reservoir_minus.getDevicePtr( subgrid ) };                                       \
        Type::complex *k_vec_wf_plus = matrix.k_wavefunction_plus.getDevicePtr( subgrid );                                                                                \
                    CALL_SUBGRID_KERNEL( Kernel::Summation::runge_add_to_input_k<GCC_EXPAND_VA_ARGS_ORDER( Type::complex, false, false, false, index, __VA_ARGS__ )>,     \
                                         "Sum for K" #index, current_grid, current_block, stream, current_halo, kernel_arguments, io.in_wf_plus, k_vec_wf_plus );         \
    };
#else
#define FINAL_SUM_K( index, ... )                                                                                                                                         \
    {                                                                                                                                                                     \
        Type::uint32 current_halo = system.p.halo_size;                                                                                                                   \
        auto [current_block, current_grid] = getLaunchParameters( system.p.subgrid_N_c + 2 * current_halo, system.p.subgrid_N_r + 2 * current_halo );                     \
        Solver::InputOutput io{ matrix.wavefunction_plus.getDevicePtr( subgrid ), matrix.wavefunction_minus.getDevicePtr( subgrid ),                                      \
                                matrix.reservoir_plus.getDevicePtr( subgrid ),    matrix.reservoir_minus.getDevicePtr( subgrid ),                                         \
                                matrix.wavefunction_plus.getDevicePtr( subgrid ), matrix.wavefunction_minus.getDevicePtr( subgrid ),                                      \
                                matrix.reservoir_plus.getDevicePtr( subgrid ),    matrix.reservoir_minus.getDevicePtr( subgrid ) };                                       \
        Type::complex *k_vec_wf_plus = matrix.k_wavefunction_plus.getDevicePtr( subgrid );                                                                                \
        if ( system.use_reservoir ) {                                                                                                                                     \
            if ( system.use_stochastic ) {                                                                                                                                \
                if ( system.imag_time_amplitude == 0.0 ) {                                                                                                                \
                    CALL_SUBGRID_KERNEL( Kernel::Summation::runge_add_to_input_k<GCC_EXPAND_VA_ARGS_ORDER( Type::complex, false, true, true, index, __VA_ARGS__ )>,       \
                                         "Sum for K" #index, current_grid, current_block, stream, current_halo, kernel_arguments, io.in_wf_plus, k_vec_wf_plus );         \
                } else {                                                                                                                                                  \
                    CALL_SUBGRID_KERNEL( Kernel::Summation::runge_add_to_input_k<GCC_EXPAND_VA_ARGS_ORDER( Type::complex, true, true, true, index, __VA_ARGS__ )>,        \
                                         "Sum for K" #index, current_grid, current_block, stream, current_halo, kernel_arguments, io.in_wf_plus, k_vec_wf_plus );         \
                }                                                                                                                                                         \
            } else {                                                                                                                                                      \
                if ( system.imag_time_amplitude == 0.0 ) {                                                                                                                \
                    CALL_SUBGRID_KERNEL( Kernel::Summation::runge_add_to_input_k<GCC_EXPAND_VA_ARGS_ORDER( Type::complex, false, false, true, index, __VA_ARGS__ )>,      \
                                         "Sum for K" #index, current_grid, current_block, stream, current_halo, kernel_arguments, io.in_wf_plus, k_vec_wf_plus );         \
                } else {                                                                                                                                                  \
                    CALL_SUBGRID_KERNEL( Kernel::Summation::runge_add_to_input_k<GCC_EXPAND_VA_ARGS_ORDER( Type::complex, true, false, true, index, __VA_ARGS__ )>,       \
                                         "Sum for K" #index, current_grid, current_block, stream, current_halo, kernel_arguments, io.in_wf_plus, k_vec_wf_plus );         \
                }                                                                                                                                                         \
            }                                                                                                                                                             \
            Type::complex *k_vec_res_plus = matrix.k_reservoir_plus.getDevicePtr( subgrid );                                                                              \
            if ( system.imag_time_amplitude == 0.0 ) {                                                                                                                    \
                CALL_SUBGRID_KERNEL( Kernel::Summation::runge_add_to_input_k<GCC_EXPAND_VA_ARGS_ORDER( Type::complex, false, false, true, index, __VA_ARGS__ )>,          \
                                     "Sum for K" #index, current_grid, current_block, stream, current_halo, kernel_arguments, io.in_rv_plus, k_vec_res_plus );            \
            } else {                                                                                                                                                      \
                CALL_SUBGRID_KERNEL( Kernel::Summation::runge_add_to_input_k<GCC_EXPAND_VA_ARGS_ORDER( Type::complex, true, false, true, index, __VA_ARGS__ )>,           \
                                     "Sum for K" #index, current_grid, current_block, stream, current_halo, kernel_arguments, io.in_rv_plus, k_vec_res_plus );            \
            }                                                                                                                                                             \
            if ( system.use_twin_mode ) {                                                                                                                                 \
                Type::complex *k_vec_wf_minus = matrix.k_wavefunction_minus.getDevicePtr( subgrid );                                                                      \
                if ( system.use_stochastic ) {                                                                                                                            \
                    if ( system.imag_time_amplitude == 0.0 ) {                                                                                                            \
                        CALL_SUBGRID_KERNEL( Kernel::Summation::runge_add_to_input_k<GCC_EXPAND_VA_ARGS_ORDER( Type::complex, false, true, true, index, __VA_ARGS__ )>,   \
                                             "Sum for K" #index, current_grid, current_block, stream, current_halo, kernel_arguments, io.in_wf_minus, k_vec_wf_minus );   \
                    } else {                                                                                                                                              \
                        CALL_SUBGRID_KERNEL( Kernel::Summation::runge_add_to_input_k<GCC_EXPAND_VA_ARGS_ORDER( Type::complex, true, true, true, index, __VA_ARGS__ )>,    \
                                             "Sum for K" #index, current_grid, current_block, stream, current_halo, kernel_arguments, io.in_wf_minus, k_vec_wf_minus );   \
                    }                                                                                                                                                     \
                } else {                                                                                                                                                  \
                    if ( system.imag_time_amplitude == 0.0 ) {                                                                                                            \
                        CALL_SUBGRID_KERNEL( Kernel::Summation::runge_add_to_input_k<GCC_EXPAND_VA_ARGS_ORDER( Type::complex, false, false, true, index, __VA_ARGS__ )>,  \
                                             "Sum for K" #index, current_grid, current_block, stream, current_halo, kernel_arguments, io.in_wf_minus, k_vec_wf_minus );   \
                    } else {                                                                                                                                              \
                        CALL_SUBGRID_KERNEL( Kernel::Summation::runge_add_to_input_k<GCC_EXPAND_VA_ARGS_ORDER( Type::complex, true, false, true, index, __VA_ARGS__ )>,   \
                                             "Sum for K" #index, current_grid, current_block, stream, current_halo, kernel_arguments, io.in_wf_minus, k_vec_wf_minus );   \
                    }                                                                                                                                                     \
                }                                                                                                                                                         \
                Type::complex *k_vec_res_minus = matrix.k_reservoir_minus.getDevicePtr( subgrid );                                                                        \
                if ( system.imag_time_amplitude == 0.0 ) {                                                                                                                \
                    CALL_SUBGRID_KERNEL( Kernel::Summation::runge_add_to_input_k<GCC_EXPAND_VA_ARGS_ORDER( Type::complex, false, false, true, index, __VA_ARGS__ )>,      \
                                         "Sum for K" #index, current_grid, current_block, stream, current_halo, kernel_arguments, io.in_rv_minus, k_vec_res_minus );      \
                } else {                                                                                                                                                  \
                    CALL_SUBGRID_KERNEL( Kernel::Summation::runge_add_to_input_k<GCC_EXPAND_VA_ARGS_ORDER( Type::complex, true, false, true, index, __VA_ARGS__ )>,       \
                                         "Sum for K" #index, current_grid, current_block, stream, current_halo, kernel_arguments, io.in_rv_minus, k_vec_res_minus );      \
                }                                                                                                                                                         \
            }                                                                                                                                                             \
        } else {                                                                                                                                                          \
            if ( system.use_stochastic ) {                                                                                                                                \
                if ( system.imag_time_amplitude == 0.0 ) {                                                                                                                \
                    CALL_SUBGRID_KERNEL( Kernel::Summation::runge_add_to_input_k<GCC_EXPAND_VA_ARGS_ORDER( Type::complex, false, true, false, index, __VA_ARGS__ )>,      \
                                         "Sum for K" #index, current_grid, current_block, stream, current_halo, kernel_arguments, io.in_wf_plus, k_vec_wf_plus );         \
                } else {                                                                                                                                                  \
                    CALL_SUBGRID_KERNEL( Kernel::Summation::runge_add_to_input_k<GCC_EXPAND_VA_ARGS_ORDER( Type::complex, true, true, false, index, __VA_ARGS__ )>,       \
                                         "Sum for K" #index, current_grid, current_block, stream, current_halo, kernel_arguments, io.in_wf_plus, k_vec_wf_plus );         \
                }                                                                                                                                                         \
            } else {                                                                                                                                                      \
                if ( system.imag_time_amplitude == 0.0 ) {                                                                                                                \
                    CALL_SUBGRID_KERNEL( Kernel::Summation::runge_add_to_input_k<GCC_EXPAND_VA_ARGS_ORDER( Type::complex, false, false, false, index, __VA_ARGS__ )>,     \
                                         "Sum for K" #index, current_grid, current_block, stream, current_halo, kernel_arguments, io.in_wf_plus, k_vec_wf_plus );         \
                } else {                                                                                                                                                  \
                    CALL_SUBGRID_KERNEL( Kernel::Summation::runge_add_to_input_k<GCC_EXPAND_VA_ARGS_ORDER( Type::complex, true, false, false, index, __VA_ARGS__ )>,      \
                                         "Sum for K" #index, current_grid, current_block, stream, current_halo, kernel_arguments, io.in_wf_plus, k_vec_wf_plus );         \
                }                                                                                                                                                         \
            }                                                                                                                                                             \
            if ( system.use_twin_mode ) {                                                                                                                                 \
                Type::complex *k_vec_wf_minus = matrix.k_wavefunction_minus.getDevicePtr( subgrid );                                                                      \
                if ( system.use_stochastic ) {                                                                                                                            \
                    if ( system.imag_time_amplitude == 0.0 ) {                                                                                                            \
                        CALL_SUBGRID_KERNEL( Kernel::Summation::runge_add_to_input_k<GCC_EXPAND_VA_ARGS_ORDER( Type::complex, false, true, false, index, __VA_ARGS__ )>,  \
                                             "Sum for K" #index, current_grid, current_block, stream, current_halo, kernel_arguments, io.in_wf_minus, k_vec_wf_minus );   \
                    } else {                                                                                                                                              \
                        CALL_SUBGRID_KERNEL( Kernel::Summation::runge_add_to_input_k<GCC_EXPAND_VA_ARGS_ORDER( Type::complex, true, true, false, index, __VA_ARGS__ )>,   \
                                             "Sum for K" #index, current_grid, current_block, stream, current_halo, kernel_arguments, io.in_wf_minus, k_vec_wf_minus );   \
                    }                                                                                                                                                     \
                } else {                                                                                                                                                  \
                    if ( system.imag_time_amplitude == 0.0 ) {                                                                                                            \
                        CALL_SUBGRID_KERNEL( Kernel::Summation::runge_add_to_input_k<GCC_EXPAND_VA_ARGS_ORDER( Type::complex, false, false, false, index, __VA_ARGS__ )>, \
                                             "Sum for K" #index, current_grid, current_block, stream, current_halo, kernel_arguments, io.in_wf_minus, k_vec_wf_minus );   \
                    } else {                                                                                                                                              \
                        CALL_SUBGRID_KERNEL( Kernel::Summation::runge_add_to_input_k<GCC_EXPAND_VA_ARGS_ORDER( Type::complex, true, false, false, index, __VA_ARGS__ )>,  \
                                             "Sum for K" #index, current_grid, current_block, stream, current_halo, kernel_arguments, io.in_wf_minus, k_vec_wf_minus );   \
                    }                                                                                                                                                     \
                }                                                                                                                                                         \
            }                                                                                                                                                             \
        }                                                                                                                                                                 \
    };

#endif
#endif
#define ERROR_K( order, ... )                                                                                                                                               \
    {                                                                                                                                                                       \
        auto [current_block, current_grid] = getLaunchParameters( system.p.subgrid_N_c, system.p.subgrid_N_r );                                                             \
        CALL_SUBGRID_KERNEL( Kernel::Summation::runge_sum_to_error<GCC_EXPAND_VA_ARGS( __VA_ARGS__ )>, "Error", current_grid, current_block, stream, 0, kernel_arguments ); \
    };

// Only Callable from within the solver
// For now, use this macro to synchronize the halos. This is a bit of a mess, but it works. TODO: move halo_map to static CUDAMatrix vector and call synchronize_halos from there.
#ifdef NO_HALO_SYNC
#define SYNCHRONIZE_HALOS( _stream, subgrids )                                                                                                                         \
    {                                                                                                                                                                  \
    }
#else
#define SYNCHRONIZE_HALOS( _stream, subgrids )                                                                                                                         \
    {                                                                                                                                                                  \
        Type::uint32 halo_map_size = matrix.halo_map.size() / 6;                                                                                                       \
        auto [current_block, current_grid] = getLaunchParameters( halo_map_size * system.p.subgrids_columns * system.p.subgrids_rows );                                \
        CALL_FULL_KERNEL( Kernel::Halo::synchronize_halos, "Synchronization", current_grid, current_block, _stream, system.p.subgrids_columns, system.p.subgrids_rows, \
                          system.p.subgrid_N_c, system.p.subgrid_N_r, system.p.halo_size, halo_map_size, system.p.periodic_boundary_x, system.p.periodic_boundary_y,   \
                          GET_RAW_PTR( matrix.halo_map ), subgrids )                                                                                                   \
    }
#endif
// Helper to retrieve the raw device pointer. When using nvcc and thrust, we need a raw pointer cast.
#ifdef USE_CPU
    #define GET_RAW_PTR( vec ) vec.data()
#else
    #define GET_RAW_PTR( vec ) thrust::raw_pointer_cast( vec.data() )
#endif

#ifdef USE_NUMA
    #define PULSE_NUMA_INSERT                           \
        int numa_domain = subgrid % PULSE_NUMA_DOMAINS; \
        numa_run_on_node( numa_domain );                \
        numa_set_preferred( numa_domain );              \
        numa_set_localalloc();
#else
    #define PULSE_NUMA_INSERT
#endif

#ifdef USE_CUDA
    // Execudes a CUDA Command, checks for the latest error and prints it
    // This is technically not a requirement, but usually good practice
    #define CHECK_CUDA_ERROR( func, msg )                             \
        {                                                             \
            func;                                                     \
            cudaError_t err = cudaGetLastError();                     \
            if ( err != cudaSuccess ) {                               \
                printf( "%s: %s\n", msg, cudaGetErrorString( err ) ); \
            }                                                         \
        }

    // Calls a Kernel and also checks for errors.
    // The Kernel call requires a name and a grid and block size that
    // are not further passed to the actual compute Kernel. Instead, they
    // are used as launch parameters and for debugging.
    // Don't use shared_mem_size for now, as it is not used and will result in large grids crashing the kernel launch.
    //size_t shared_mem_size = sizeof( Type::complex ) * ( 2 * system.p.subgrid_row_offset + system.block_size + 1 );
    #define CALL_SUBGRID_KERNEL( func, name, grid, block, stream, ... )                                                     \
        {                                                                                                                   \
            func<<<grid, block, 0, stream>>>( 0, __VA_ARGS__ );                                               \
        }
    #define CALL_FULL_KERNEL( func, name, grid, block, stream, ... ) \
        { func<<<grid, block, 0, stream>>>( 0, __VA_ARGS__ ); }
    // Wraps the successive calls to the CUDA Kernels into a single CUDA Graph.
    // Edit: Oh God what a mess.
    #define SOLVER_SEQUENCE( with_graph, content )                                                                                                        \
        {                                                                                                                                                 \
            static bool cuda_graph_created = false;                                                                                                       \
            static cudaGraph_t graph;                                                                                                                     \
            static cudaGraphExec_t instance;                                                                                                              \
            static cudaStream_t stream;                                                                                                                   \
            static cudaGraphNode_t *nodes;                                                                                                                \
            static size_t num_nodes;                                                                                                                      \
            if ( not cuda_graph_created or not with_graph ) {                                                                                             \
                std::vector<Solver::KernelArguments> v_kernel_arguments;                                                                                  \
                for ( Type::uint32 subgrid = 0; subgrid < system.p.subgrids_columns * system.p.subgrids_rows; subgrid++ ) {                               \
                    v_kernel_arguments.push_back( generateKernelArguments( subgrid ) );                                                                   \
                }                                                                                                                                         \
                if ( with_graph ) {                                                                                                                       \
                    cudaStreamCreate( &stream );                                                                                                          \
                    cudaStreamBeginCapture( stream, cudaStreamCaptureModeGlobal );                                                                        \
                    std::cout << PC3::CLIO::prettyPrint( "Capturing CUDA Graph", PC3::CLIO::Control::Secondary | PC3::CLIO::Control::Info ) << std::endl; \
                }                                                                                                                                         \
                if ( system.use_twin_mode ) {                                                                                                             \
                    SYNCHRONIZE_HALOS( stream, matrix.wavefunction_plus.getSubgridDevicePtrs() );                                                         \
                    SYNCHRONIZE_HALOS( stream, matrix.wavefunction_minus.getSubgridDevicePtrs() );                                                        \
                    if ( system.use_reservoir ) {                                                                                                         \
                        SYNCHRONIZE_HALOS( stream, matrix.reservoir_plus.getSubgridDevicePtrs() );                                                        \
                        SYNCHRONIZE_HALOS( stream, matrix.reservoir_minus.getSubgridDevicePtrs() );                                                       \
                    }                                                                                                                                     \
                } else {                                                                                                                                  \
                    SYNCHRONIZE_HALOS( stream, matrix.wavefunction_plus.getSubgridDevicePtrs() );                                                         \
                    if ( system.use_reservoir ) {                                                                                                         \
                        SYNCHRONIZE_HALOS( stream, matrix.reservoir_plus.getSubgridDevicePtrs() );                                                        \
                    }                                                                                                                                     \
                }                                                                                                                                         \
                for ( Type::uint32 subgrid = 0; subgrid < system.p.subgrids_columns * system.p.subgrids_rows; subgrid++ ) {                               \
                    auto &kernel_arguments = v_kernel_arguments[subgrid];                                                                                 \
                    content;                                                                                                                              \
                }                                                                                                                                         \
                if ( with_graph ) {                                                                                                                       \
                    cudaStreamEndCapture( stream, &graph );                                                                                               \
                    cudaGraphInstantiate( &instance, graph, NULL, NULL, 0 );                                                                              \
                    cuda_graph_created = true;                                                                                                            \
                    cudaGraphGetNodes( graph, nullptr, &num_nodes );                                                                                      \
                    nodes = new cudaGraphNode_t[num_nodes];                                                                                               \
                    cudaGraphGetNodes( graph, nodes, &num_nodes );                                                                                        \
                    std::cout << PC3::CLIO::prettyPrint( "CUDA Graph created with " + std::to_string( num_nodes ) + " nodes",                             \
                                                         PC3::CLIO::Control::Secondary | PC3::CLIO::Control::Info )                                       \
                              << std::endl;                                                                                                               \
                }                                                                                                                                         \
            } else {                                                                                                                                      \
                cudaGraphLaunch( instance, stream );                                                                                                      \
            }                                                                                                                                             \
        }

#else
    // On the CPU, the check for CUDA errors does nothing
    #define CHECK_CUDA_ERROR( func, msg )
    // On the CPU, the Kernel call does not execute a parallel GPU Kernel. Instead,
    // it launches a group of threads using a #pragma omp instruction.

    // CALL_SUBGRID_KERNEL will call the kernel row-wise, making sure that memory accesses are coalesced and the innermost loop is vectorizable
    // CALL_FULL_KERNEL will also handle the indexing, making sure that the function is called with the correct, modified row-col index depending on the current halo.
    #define CALL_SUBGRID_KERNEL( func, name, grid, block, stream, ... )                                                        \
        {                                                                                                                      \
            const int halo_rem = system.p.halo_size - current_halo;                                                         \
            const int nc=system.p.subgrid_N_c; \
            const int bx=block.x; \
            for ( int row = 0; row < bx; row++ ) {                                                               \
                int index_start = ( row + halo_rem ) * system.p.subgrid_row_offset + halo_rem;                        \
                _Pragma( "omp simd" ) for ( int col = 0; col < nc + 2 * ( current_halo ); col++ ) { \
                    func( index_start + col, __VA_ARGS__ );                                                                    \
                }                                                                                                              \
            }                                                                                                                  \
        }
#ifdef BENCH        
  #ifdef AVX2
    #define CALL_SUBGRID_KERNEL_MI( func, name, grid, block, stream, ... )                                                        \
        {                                                                                                                      \
          const int n=system.p.subgrid_N2_with_halo; \
          static const float m[8] = { 1,-1,1,-1,1,-1,1,-1}; \
          const __m256 c=_mm256_loadu_ps(m); \
          for (int i = 0; i < n-n%4; i += 4) \
          { \
            __m256 a = _mm256_loadu_ps (reinterpret_cast<const float*> (io.in_wf_plus + i    )); \
            __m256 b = _mm256_permute_ps (a, 0b10110001); \
            a=_mm256_mul_ps(b,c); \
            _mm256_storeu_ps (reinterpret_cast<float*>(io.in_wf_plus_i +i), a); \
          } \
          for (int i = n-n%4; i<n;i++) \
          { \
            io.in_wf_plus_i[i]=std::complex(imag(io.in_wf_plus[i]),-real(io.in_wf_plus[i])); \
          } \
        }
  #else
    #define CALL_SUBGRID_KERNEL_MI( func, name, grid, block, stream, ... )                                                        \
        {                                                                                                                      \
          const int n=system.p.subgrid_N2_with_halo; \
          for (int i = 0; i<n;i++) \
          { \
            io.in_wf_plus_i[i]=std::complex(imag(io.in_wf_plus[i]),-real(io.in_wf_plus[i])); \
          } \
        }
  #endif
#endif
    #define CALL_FULL_KERNEL( func, name, grid, block, stream, ... )                                              \
        {                                                                                                         \
            const Type::uint32 execution_range = block.x * grid.x;                                                      \
            _Pragma( "omp parallel for schedule(static)" ) for ( Type::uint32 i = 0; i < execution_range; ++i ) { \
                func( i, __VA_ARGS__ );                                                                           \
            }                                                                                                     \
        }
    // Merges the Kernel calls into a single function call. This is not required on the CPU.
    #define SOLVER_SEQUENCE( with_graph, content )                                                                                                                     \
        {                                                                                                                                                              \
            PC3::Type::stream_t stream;                                                                                                                                \
            static bool first_time = false;                                                                                                                            \
            static std::vector<Solver::KernelArguments> v_kernel_arguments;                                                                                            \
            Type::uint32 current_halo = system.p.halo_size;                                                                                                            \
            if ( not first_time ) {                                                                                                                                    \
                for ( Type::uint32 subgrid = 0; subgrid < system.p.subgrids_columns * system.p.subgrids_rows; subgrid++ ) {                                            \
                    v_kernel_arguments.push_back( generateKernelArguments( subgrid ) );                                                                                \
                }                                                                                                                                                      \
                first_time = true;                                                                                                                                     \
            }                                                                                                                                                          \
            if ( system.use_twin_mode ) {                                                                                                                              \
                SYNCHRONIZE_HALOS( stream, matrix.wavefunction_plus.getSubgridDevicePtrs() )                                                                           \
                SYNCHRONIZE_HALOS( stream, matrix.wavefunction_minus.getSubgridDevicePtrs() )                                                                          \
                if ( system.use_reservoir ) {                                                                                                                          \
                    SYNCHRONIZE_HALOS( stream, matrix.reservoir_plus.getSubgridDevicePtrs() )                                                                          \
                    SYNCHRONIZE_HALOS( stream, matrix.reservoir_minus.getSubgridDevicePtrs() )                                                                         \
                }                                                                                                                                                      \
            } else {                                                                                                                                                   \
                SYNCHRONIZE_HALOS( stream, matrix.wavefunction_plus.getSubgridDevicePtrs() )                                                                           \
                if ( system.use_reservoir ) {                                                                                                                          \
                    SYNCHRONIZE_HALOS( stream, matrix.reservoir_plus.getSubgridDevicePtrs() )                                                                          \
                }                                                                                                                                                      \
            }                                                                                                                                                          \
            _Pragma( "omp parallel for schedule(static)" ) for ( Type::uint32 subgrid = 0; subgrid < system.p.subgrids_columns * system.p.subgrids_rows; subgrid++ ) { \
                PULSE_NUMA_INSERT;                                                                                                                                     \
                auto &kernel_arguments = v_kernel_arguments[subgrid];                                                                                                  \
                content;                                                                                                                                               \
            }                                                                                                                                                          \
        }
#endif

// Swaps symbols a and b
#define swap_symbol( a, b ) \
    {                       \
        auto tmp = a;       \
        a = b;              \
        b = tmp;            \
    }

// CUDA Specific Alloc and Free
#ifndef USE_CPU
    #define DEVICE_ALLOC( ptr, size, name ) \
        { CHECK_CUDA_ERROR( cudaMalloc( (void **)&ptr, size ), name ); }
    #define MEMCOPY_TO_DEVICE( dst, src, size, name ) \
        { CHECK_CUDA_ERROR( cudaMemcpy( dst, src, size, cudaMemcpyHostToDevice ), name ); }
    #define MEMCOPY_FROM_DEVICE( dst, src, size, name ) \
        { CHECK_CUDA_ERROR( cudaMemcpy( dst, src, size, cudaMemcpyDeviceToHost ), name ); }
    #define SYMBOL_TO_DEVICE( dest, source, size, name ) \
        { CHECK_CUDA_ERROR( cudaMemcpyToSymbol( dest, source, size ), name ); }
    #define SYMBOL_TO_HOST( dest, source, size, name ) \
        { CHECK_CUDA_ERROR( cudaMemcpyFromSymbol( dest, source, size ), name ); }
    #define DEVICE_FREE( ptr, name ) \
        { CHECK_CUDA_ERROR( cudaFree( ptr ), name ); }
#else
    #define DEVICE_ALLOC( ptr, size, name ) \
        { ptr = (decltype( ptr ))malloc( size ); }
    #define MEMCOPY_TO_DEVICE( dst, src, size, name ) \
        { memcpy( dst, src, size ); }
    #define MEMCOPY_FROM_DEVICE( dst, src, size, name ) \
        { memcpy( dst, src, size ); }
    #define SYMBOL_TO_DEVICE( dest, source, size, name ) \
        { dest = *( source ); }
    #define SYMBOL_TO_HOST( dest, source, size, name ) \
        { dest = *( source ); }
    #define DEVICE_FREE( ptr, name ) \
        { free( ptr ); }
#endif
