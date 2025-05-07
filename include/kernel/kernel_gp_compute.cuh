#pragma once
#include "cuda/typedef.cuh"
#include "cuda/cuda_macro.cuh"
#include "solver/solver.hpp"

/*
 * The Main Compute Kernel is structured using small inlined subkernels. These subkernels define the system components.
 * We branch for the following components in order:
 * Scalar, TE/TM
 * Wavefunction only, Wavefunction and Reservoir
 * Linear (Hamiltonian), Nonlinear, Pulse, Pump, Potential, Stochastic
 * These components are then chosen by a master Kernel, which is called by the main loop.
 * Since all subfunctions are inlined, the resulting Kernel should be a single, inlinable function
*/

namespace PHOENIX::Kernel::Compute {

template <bool tmp_use_tetm, bool tmp_use_reservoir, bool tmp_use_pulse, bool tmp_use_pump, bool tmp_use_potential, bool tmp_use_stochastic>
PHOENIX_GLOBAL PHOENIX_COMPILER_SPECIFIC void gp_scalar( int i, Type::real w, Type::uint32 current_halo, Solver::KernelArguments args, Solver::InputOutput io ) {
    GENERATE_SUBGRID_INDEX( i, current_halo );

    // For now, we do a giant case switch for TE/TM, repeating a lot of code. Maybe we will change this later to include TE/TM throughout the regular kernel.
    const Type::real m_eff_scaled = args.p.m_eff_scaled;
    const Type::real m2_over_dx2_p_dy2 = args.p.m2_over_dx2_p_dy2;
    const Type::real one_over_dy2 = args.p.one_over_dy2;
    const Type::real one_over_dx2 = args.p.one_over_dx2;
    const int subgrid_row_offset = args.p.subgrid_row_offset;
    const Type::real one_over_h_bar_s = args.p.one_over_h_bar_s;
    const Type::real g_c = args.p.g_c;
    const Type::real gamma_c = args.p.gamma_c;

    //==========================================================================================//
    //==================================== Scalar GP Kernel ====================================//
    //==========================================================================================//
    // MARK: Scalar

    if constexpr ( not tmp_use_tetm ) {
        // Specialized Benchmark for CPU
#if defined( BENCH ) && defined( USE_CPU )
        const Type::complex in_wf = io.in_wf_plus[i];
        const Type::complex in_wf_mi = io.in_wf_plus_i[i];
        const Type::real in_psi_norm = CUDA::abs2( in_wf );
        Type::complex wf_plus = m_eff_scaled * ( m2_over_dx2_p_dy2 * io.in_wf_plus_i[i] + ( io.in_wf_plus_i[i + subgrid_row_offset] + io.in_wf_plus_i[i - subgrid_row_offset] ) * one_over_dy2 + ( io.in_wf_plus_i[i + 1] + io.in_wf_plus_i[i - 1] ) * one_over_dx2 );
        wf_plus = wf_plus * one_over_h_bar_s;
        wf_plus += one_over_h_bar_s * g_c * in_psi_norm * in_wf_mi;
        wf_plus -= Type::real( 0.5 ) * gamma_c * in_wf;

#else

        const Type::complex in_wf = io.in_wf_plus[i];
        // Use this for -i*in_wf

        //const Type::complex in_wf_mi = Type::complex( CUDA::imag( in_wf ), -1.0f * CUDA::real( in_wf ) );
        const Type::complex in_wf_mi = CUDA::mi_conjugate( in_wf );

        // |Psi|^2
        const Type::real in_psi_norm = CUDA::abs2( in_wf );

        // Hamiltonian

        Type::complex wf_plus = m_eff_scaled * ( m2_over_dx2_p_dy2 * in_wf + ( io.in_wf_plus[i + subgrid_row_offset] + io.in_wf_plus[i - subgrid_row_offset] ) * one_over_dy2 + ( io.in_wf_plus[i + 1] + io.in_wf_plus[i - 1] ) * one_over_dx2 );
        // -i/hbar * H
        //wf_plus = Type::complex( CUDA::imag( wf_plus ), -1.0f * CUDA::real( wf_plus ) ) * one_over_h_bar_s;
        wf_plus = CUDA::mi_conjugate( wf_plus ) * one_over_h_bar_s;
        wf_plus += one_over_h_bar_s * g_c * in_psi_norm * in_wf_mi;

        wf_plus -= Type::real( 0.5 ) * gamma_c * in_wf;
#endif

        if constexpr ( tmp_use_reservoir ) {
            const Type::complex in_rv = io.in_rv_plus[i];
            wf_plus += args.p.one_over_h_bar_s * args.p.g_r * in_rv * in_wf_mi;
            wf_plus += Type::real( 0.5 ) * args.p.R * in_rv * in_wf;
            Type::complex rv_plus = -( args.p.gamma_r + args.p.R * in_psi_norm ) * in_rv;

            if constexpr ( tmp_use_pump ) {
                for ( int k = 0; k < args.pump_pointers.n; k++ ) {
                    PHOENIX::Type::uint32 offset = args.p.subgrid_N2_with_halo * k;
                    rv_plus += args.dev_ptrs.pump_plus[i + offset] * ( args.pump_pointers.amp[k]*(Type::real(1.0)-w) + w*args.pump_pointers.amp_next[k] );
                }
            }

            if constexpr ( tmp_use_stochastic ) {
                rv_plus += args.p.R * in_rv / args.p.dV;
            }

            io.out_rv_plus[i] = rv_plus;
        }

        if constexpr ( tmp_use_potential ) {
            for ( int k = 0; k < args.potential_pointers.n; k++ ) {
                PHOENIX::Type::uint32 offset = args.p.subgrid_N2_with_halo * k;
                const Type::complex potential = args.dev_ptrs.potential_plus[i + offset] * (args.potential_pointers.amp[k]*(Type::real(1.0)-w) + w*args.potential_pointers.amp_next[k]);
                wf_plus += args.p.one_over_h_bar_s * potential * in_wf_mi;
            }
        }

        if constexpr ( tmp_use_pulse ) {
            for ( int k = 0; k < args.pulse_pointers.n; k++ ) {
                PHOENIX::Type::uint32 offset = args.p.subgrid_N2_with_halo * k;
                const Type::complex pulse = args.dev_ptrs.pulse_plus[i + offset];
                wf_plus += args.p.one_over_h_bar_s * pulse * (args.pulse_pointers.amp[k]*(Type::real(1.0)-w) + w*args.pulse_pointers.amp_next[k]);
            }
        }

        if constexpr ( tmp_use_stochastic ) {
            wf_plus -= args.p.one_over_h_bar_s * args.p.g_c * in_wf_mi / args.p.dV;
        }

        io.out_wf_plus[i] = wf_plus;

    } else {
        //==========================================================================================//
        //===================================== TE/TM GP Kernel ====================================//
        //==========================================================================================//
        // MARK: TE/TM
        const Type::complex in_wf_plus = io.in_wf_plus[i];
        const Type::complex in_wf_minus = io.in_wf_minus[i];
        // Use this for -i*in_wf
        const Type::complex in_wf_plus_mi = Type::complex( CUDA::imag( in_wf_plus ), -1.0f * CUDA::real( in_wf_plus ) );
        const Type::complex in_wf_minus_mi = Type::complex( CUDA::imag( in_wf_minus ), -1.0f * CUDA::real( in_wf_minus ) );

        Type::complex horizontal_plus = ( io.in_wf_plus[i + 1] + io.in_wf_plus[i - 1] ) * args.p.one_over_dx2;
        Type::complex vertical_plus = ( io.in_wf_plus[i + args.p.subgrid_row_offset] + io.in_wf_plus[i - args.p.subgrid_row_offset] ) * args.p.one_over_dy2;
        Type::complex horizontal_minus = ( io.in_wf_minus[i + 1] + io.in_wf_minus[i - 1] ) * args.p.one_over_dx2;
        Type::complex vertical_minus = ( io.in_wf_minus[i + args.p.subgrid_row_offset] + io.in_wf_minus[i - args.p.subgrid_row_offset] ) * args.p.one_over_dy2;
        Type::complex hamilton_cross_plus = horizontal_minus - vertical_minus + args.p.half_i / args.p.dx / args.p.dy * ( io.in_wf_minus[i + args.p.subgrid_row_offset + 1] + io.in_wf_minus[i - args.p.subgrid_row_offset - 1] - io.in_wf_minus[i + args.p.subgrid_row_offset - 1] - io.in_wf_minus[i - args.p.subgrid_row_offset + 1] );
        Type::complex hamilton_cross_minus = horizontal_plus - vertical_plus - args.p.half_i / args.p.dx / args.p.dy * ( io.in_wf_plus[i + args.p.subgrid_row_offset + 1] + io.in_wf_plus[i - args.p.subgrid_row_offset - 1] - io.in_wf_plus[i + args.p.subgrid_row_offset - 1] - io.in_wf_plus[i - args.p.subgrid_row_offset + 1] );
        Type::complex hamilton_regular_plus = args.p.m2_over_dx2_p_dy2 * in_wf_plus + horizontal_plus + vertical_plus;
        Type::complex hamilton_regular_minus = args.p.m2_over_dx2_p_dy2 * in_wf_minus + horizontal_minus + vertical_minus;

        const Type::complex in_rv_plus = io.in_rv_plus[i];
        const Type::complex in_rv_minus = io.in_rv_minus[i];
        const Type::real in_psi_plus_norm = CUDA::abs2( in_wf_plus );
        const Type::real in_psi_minus_norm = CUDA::abs2( in_wf_minus );

        // MARK: Wavefunction Plus
        // -i/hbar * H
        hamilton_regular_plus = Type::complex( CUDA::imag( hamilton_regular_plus ), -1.0f * CUDA::real( hamilton_regular_plus ) );
        hamilton_regular_minus = Type::complex( CUDA::imag( hamilton_regular_minus ), -1.0f * CUDA::real( hamilton_regular_minus ) );
        hamilton_cross_plus = Type::complex( CUDA::imag( hamilton_cross_plus ), -1.0f * CUDA::real( hamilton_cross_plus ) );
        hamilton_cross_minus = Type::complex( CUDA::imag( hamilton_cross_minus ), -1.0f * CUDA::real( hamilton_cross_minus ) );

        Type::complex result = args.p.one_over_h_bar_s * args.p.m_eff_scaled * hamilton_regular_plus;

        for ( int k = 0; k < args.potential_pointers.n; k++ ) {
            PHOENIX::Type::uint32 offset = args.p.subgrid_N2_with_halo * k;
            const Type::complex potential = args.dev_ptrs.potential_plus[i + offset] * (args.potential_pointers.amp[k]*(Type::real(1.0)-w) + w*args.potential_pointers.amp_next[k]);
            result += args.p.one_over_h_bar_s * potential * in_wf_plus_mi; // TODO: remove this complex multiplication!
        }

        result += args.p.one_over_h_bar_s * args.p.g_c * in_psi_plus_norm * in_wf_plus_mi;
        result += args.p.one_over_h_bar_s * args.p.g_r * in_rv_plus * in_wf_plus_mi;
        result += Type::real( 0.5 ) * args.p.R * in_rv_plus * in_wf_plus;
        result -= Type::real( 0.5 ) * args.p.gamma_c * in_wf_plus;

        result += args.p.one_over_h_bar_s * args.p.g_pm * in_psi_minus_norm * in_wf_plus_mi;
        result += args.p.one_over_h_bar_s * args.p.delta_LT * hamilton_cross_plus;

        // MARK: Pulse Plus
        for ( int k = 0; k < args.pulse_pointers.n; k++ ) {
            PHOENIX::Type::uint32 offset = args.p.subgrid_N2_with_halo * k;
            const Type::complex pulse = args.dev_ptrs.pulse_plus[i + offset];
            result += args.p.one_over_h_bar_s * pulse * (args.pulse_pointers.amp[k]*(Type::real(1.0)-w) + w*args.pulse_pointers.amp_next[k]); // TODO: remove this complex multiplication!
        }

        // MARK: Stochastic
        if ( args.p.stochastic_amplitude > 0.0 ) {
            const Type::complex dw = args.dev_ptrs.random_number[i] * CUDA::sqrt( ( args.p.R * in_rv_plus + args.p.gamma_c ) / ( Type::real( 4.0 ) * args.p.dV ) );
            result -= args.p.one_over_h_bar_s * args.p.g_c * in_wf_plus_mi / args.p.dV;
        }

        io.out_wf_plus[i] = result;

        // MARK: Reservoir Plus
        result = -( args.p.gamma_r + args.p.R * in_psi_plus_norm ) * in_rv_plus;

        for ( int k = 0; k < args.pump_pointers.n; k++ ) {
            const auto gauss = args.pump_pointers.amp[k]*(Type::real(1.0)-w) + w*args.pump_pointers.amp_next[k];
            PHOENIX::Type::uint32 offset = args.p.subgrid_N2_with_halo * k;
            result += args.dev_ptrs.pump_plus[i + offset] * gauss; // TODO: remove this complex multiplication!
        }

        // MARK: Stochastic-2
        if ( args.p.stochastic_amplitude > 0.0 )
            result += args.p.R * in_rv_plus / args.p.dV;

        io.out_rv_plus[i] = result;

        // MARK: Wavefunction Minus
        result = args.p.one_over_h_bar_s * args.p.m_eff_scaled * hamilton_regular_minus;

        for ( int k = 0; k < args.potential_pointers.n; k++ ) {
            PHOENIX::Type::uint32 offset = args.p.subgrid_N2_with_halo * k;
            const Type::complex potential = args.dev_ptrs.potential_minus[i + offset] * (args.potential_pointers.amp[k]*(Type::real(1.0)-w) + w*args.potential_pointers.amp_next[k]);
            result += args.p.one_over_h_bar_s * potential * in_wf_minus_mi; // TODO: remove this complex multiplication!
        }

        result += args.p.one_over_h_bar_s * args.p.g_c * in_psi_minus_norm * in_wf_minus_mi;
        result += args.p.one_over_h_bar_s * args.p.g_r * in_rv_minus * in_wf_minus_mi;
        result += Type::real( 0.5 ) * args.p.R * in_rv_minus * in_wf_minus;
        result -= Type::real( 0.5 ) * args.p.gamma_c * in_wf_minus;

        result += args.p.one_over_h_bar_s * args.p.g_pm * in_psi_plus_norm * in_wf_minus_mi;
        result += args.p.one_over_h_bar_s * args.p.delta_LT * hamilton_cross_minus;

        // MARK: Pulse Minus
        for ( int k = 0; k < args.pulse_pointers.n; k++ ) {
            PHOENIX::Type::uint32 offset = args.p.subgrid_N2_with_halo * k;
            const Type::complex pulse = args.dev_ptrs.pulse_minus[i + offset];
            result += args.p.one_over_h_bar_s * pulse * (args.pulse_pointers.amp[k]*(Type::real(1.0)-w) + w*args.pulse_pointers.amp_next[k]); // TODO: remove this complex multiplication!
        }

        if ( args.p.stochastic_amplitude > 0.0 ) {
            const Type::complex dw = args.dev_ptrs.random_number[i] * CUDA::sqrt( ( args.p.R * in_rv_minus + args.p.gamma_c ) / ( Type::real( 4.0 ) * args.p.dV ) );
            result -= args.p.one_over_h_bar_s * args.p.g_c * in_wf_minus_mi / args.p.dV;
        }

        io.out_wf_minus[i] = result;

        // MARK: Reservoir Minus
        result = -( args.p.gamma_r + args.p.R * in_psi_minus_norm ) * in_rv_minus;

        for ( int k = 0; k < args.pump_pointers.n; k++ ) {
            const auto gauss = args.pump_pointers.amp[k]*(Type::real(1.0)-w) + w*args.pump_pointers.amp_next[k];
            PHOENIX::Type::uint32 offset = args.p.subgrid_N2_with_halo * k;
            result += args.dev_ptrs.pump_minus[i + offset] * gauss; // TODO: remove this complex multiplication!
        }

        // MARK: Stochastic-2
        if ( args.p.stochastic_amplitude > 0.0 )
            result += args.p.R * in_rv_minus / args.p.dV;

        io.out_rv_minus[i] = result;
    }
}

/**
 * Linear, Nonlinear and Independet parts of the upper Kernel
 * These isolated implementations serve for the Split Step
 * Fourier Method (SSFM)
*/

template <bool tmp_use_tetm>
PHOENIX_GLOBAL PHOENIX_COMPILER_SPECIFIC void gp_scalar_linear_fourier( int i, Solver::KernelArguments args, Solver::InputOutput io ) {
    GET_THREAD_INDEX( i, args.p.N2 );

    // We do some weird looking casting to avoid intermediate casts to Type::uint32
    Type::real row = Type::real( Type::uint32( i / args.p.N_c ) );
    Type::real col = Type::real( Type::uint32( i % args.p.N_c ) );

    const Type::real k_x = 2.0 * 3.1415926535 * Type::real( col <= args.p.N_c / 2 ? col : -Type::real( args.p.N_c ) + col ) / args.p.L_x;
    const Type::real k_y = 2.0 * 3.1415926535 * Type::real( row <= args.p.N_r / 2 ? row : -Type::real( args.p.N_r ) + row ) / args.p.L_y;
    Type::real linear = args.p.h_bar_s / 2.0 / args.p.m_eff * ( k_x * k_x + k_y * k_y );

    if constexpr ( not tmp_use_tetm ) {
        io.out_wf_plus[i] = io.in_wf_plus[i] / Type::real( args.p.N2 ) * CUDA::exp( args.p.minus_i * linear * args.time[1] / Type::real( 2.0 ) );
    } else {
        io.out_wf_plus[i] = io.in_wf_plus[i] / Type::real( args.p.N2 ) * CUDA::exp( args.p.minus_i * linear * args.time[1] / Type::real( 2.0 ) );
        io.out_wf_minus[i] = io.in_wf_minus[i] / Type::real( args.p.N2 ) * CUDA::exp( args.p.minus_i * linear * args.time[1] / Type::real( 2.0 ) );
    }
}

template <bool tmp_use_tetm>
PHOENIX_GLOBAL PHOENIX_COMPILER_SPECIFIC void gp_scalar_nonlinear( int i, Solver::KernelArguments args, Solver::InputOutput io ) {
    GET_THREAD_INDEX( i, args.p.N2 );

    if constexpr ( not tmp_use_tetm ) {
        const Type::complex in_wf = io.in_wf_plus[i];
        const Type::complex in_rv = io.in_rv_plus[i];
        const Type::real in_psi_norm = CUDA::abs2( in_wf );

        // MARK: Wavefunction
        Type::complex result = { args.p.g_c * in_psi_norm, -args.p.h_bar_s * Type::real( 0.5 ) * args.p.gamma_c };

        for ( int k = 0; k < args.potential_pointers.n; k++ ) {
            PHOENIX::Type::uint32 offset = args.p.subgrid_N2_with_halo * k;
            const Type::complex potential = args.dev_ptrs.potential_plus[i + offset] * args.potential_pointers.amp[k];
            result += potential;
        }

        result += args.p.g_r * in_rv;
        result += args.p.i * args.p.h_bar_s * Type::real( 0.5 ) * args.p.R * in_rv;

        // MARK: Stochastic
        if ( args.p.stochastic_amplitude > 0.0 ) {
            const Type::complex dw = args.dev_ptrs.random_number[i] * CUDA::sqrt( ( args.p.R * in_rv + args.p.gamma_c ) / ( Type::real( 4.0 ) * args.p.dV ) );
            result -= args.p.g_c / args.p.dV;
        }

        result = Type::complex( result.imag(), -1.0f * result.real() );
        io.out_wf_plus[i] = in_wf * CUDA::exp( args.p.one_over_h_bar_s * result * args.time[1] );

        // MARK: Reservoir
        result = -args.p.gamma_r * in_rv;
        result -= args.p.R * in_psi_norm * in_rv;
        for ( int k = 0; k < args.pump_pointers.n; k++ ) {
            PHOENIX::Type::uint32 offset = args.p.subgrid_N2_with_halo * k;
            result += args.dev_ptrs.pump_plus[i + offset] * args.pump_pointers.amp[k];
        }
        // MARK: Stochastic-2
        if ( args.p.stochastic_amplitude > 0.0 )
            result += args.p.R * in_rv / args.p.dV;
        io.out_rv_plus[i] = in_rv + result * args.time[1];
    } else {
        const Type::complex in_wf_plus = io.in_wf_plus[i];
        const Type::complex in_rv_plus = io.in_rv_plus[i];
        const Type::complex in_wf_minus = io.in_wf_minus[i];
        const Type::complex in_rv_minus = io.in_rv_minus[i];
        const Type::real in_psi_plus_norm = CUDA::abs2( in_wf_plus );
        const Type::real in_psi_minus_norm = CUDA::abs2( in_wf_minus );

        // MARK: Wavefunction Plus
        Type::complex result = { args.p.g_c * in_psi_plus_norm, -args.p.h_bar_s * Type::real( 0.5 ) * args.p.gamma_c };

        for ( int k = 0; k < args.potential_pointers.n; k++ ) {
            PHOENIX::Type::uint32 offset = args.p.subgrid_N2_with_halo * k;
            const Type::complex potential = args.dev_ptrs.potential_plus[i + offset] * args.potential_pointers.amp[k];
            result += potential;
        }

        result += args.p.g_r * in_rv_plus;
        result += args.p.i * args.p.h_bar_s * Type::real( 0.5 ) * args.p.R * in_rv_plus;

        Type::complex cross = args.p.g_pm * in_psi_minus_norm;
        //cross += args.p.delta_LT * hamilton_cross_plus;

        // MARK: Stochastic
        if ( args.p.stochastic_amplitude > 0.0 ) {
            const Type::complex dw = args.dev_ptrs.random_number[i] * CUDA::sqrt( ( args.p.R * in_rv_plus + args.p.gamma_c ) / ( Type::real( 4.0 ) * args.p.dV ) );
            result -= args.p.g_c / args.p.dV;
        }

        io.out_wf_plus[i] = in_wf_plus * CUDA::exp( args.p.minus_i_over_h_bar_s * ( result + cross ) * args.time[1] );

        // MARK: Reservoir
        result = -args.p.gamma_r * in_rv_plus;
        result -= args.p.R * in_psi_plus_norm * in_rv_plus;
        for ( int k = 0; k < args.pump_pointers.n; k++ ) {
            PHOENIX::Type::uint32 offset = args.p.subgrid_N2_with_halo * k;
            result += args.dev_ptrs.pump_plus[i + offset] * args.pump_pointers.amp[k];
        }
        // MARK: Stochastic-2
        if ( args.p.stochastic_amplitude > 0.0 )
            result += args.p.R * in_rv_plus / args.p.dV;
        io.out_rv_plus[i] = in_rv_plus + result * args.time[1];

        // MARK: Wavefunction Minus
        result = Type::complex( args.p.g_c * in_psi_minus_norm, -args.p.h_bar_s * Type::real( 0.5 ) * args.p.gamma_c );

        for ( int k = 0; k < args.potential_pointers.n; k++ ) {
            PHOENIX::Type::uint32 offset = args.p.subgrid_N2_with_halo * k;
            const Type::complex potential = args.dev_ptrs.potential_minus[i + offset] * args.potential_pointers.amp[k];
            result += potential;
        }

        result += args.p.g_r * in_rv_minus;
        result += args.p.i * args.p.h_bar_s * Type::real( 0.5 ) * args.p.R * in_rv_minus;

        cross = args.p.g_pm * in_psi_plus_norm;
        //cross += args.p.delta_LT * hamilton_cross_minus;

        // MARK: Stochastic
        if ( args.p.stochastic_amplitude > 0.0 ) {
            const Type::complex dw = args.dev_ptrs.random_number[i] * CUDA::sqrt( ( args.p.R * in_rv_minus + args.p.gamma_c ) / ( Type::real( 4.0 ) * args.p.dV ) );
            result -= args.p.g_c / args.p.dV;
        }

        io.out_wf_minus[i] = in_wf_minus * CUDA::exp( args.p.minus_i_over_h_bar_s * ( result + cross ) * args.time[1] );

        // MARK: Reservoir
        result = -args.p.gamma_r * in_rv_minus;
        result -= args.p.R * in_psi_minus_norm * in_rv_minus;
        for ( int k = 0; k < args.pump_pointers.n; k++ ) {
            PHOENIX::Type::uint32 offset = args.p.subgrid_N2_with_halo * k;
            result += args.dev_ptrs.pump_minus[i + offset] * args.pump_pointers.amp[k];
        }
        // MARK: Stochastic-2
        if ( args.p.stochastic_amplitude > 0.0 )
            result += args.p.R * in_rv_minus / args.p.dV;
        io.out_rv_minus[i] = in_rv_minus + result * args.time[1];
    }
}

// This kernel is somewhat special, because the reservoir input holds the old reservoir (before the fullstep)
// and the output reservoir hols the new reservoir. We need to use the old reservoir for calculations and then
// write the new reservoir to the output.
template <bool tmp_use_tetm>
PHOENIX_GLOBAL PHOENIX_COMPILER_SPECIFIC void gp_scalar_independent( int i, Solver::KernelArguments args, Solver::InputOutput io ) {
    GET_THREAD_INDEX( i, args.p.N2 );

    Type::complex result = { 0.0, 0.0 };
    if constexpr ( not tmp_use_tetm ) {
        // MARK: Pulse
        for ( int k = 0; k < args.pulse_pointers.n; k++ ) {
            PHOENIX::Type::uint32 offset = args.p.subgrid_N2_with_halo * k;
            const Type::complex pulse = args.dev_ptrs.pulse_plus[i + offset];
            result += args.p.one_over_h_bar_s * args.time[1] * pulse * args.pulse_pointers.amp[k];
        }

        // MARK: Stochastic
        if ( args.p.stochastic_amplitude > 0.0 ) {
            const Type::complex in_rv = io.out_rv_plus[i]; // Input Reservoir is in output buffer.
            const Type::complex dw = args.dev_ptrs.random_number[i] * CUDA::sqrt( ( args.p.R * in_rv + args.p.gamma_c ) / ( Type::real( 4.0 ) * args.p.dV ) );
            result += dw;
        }
        io.out_wf_plus[i] = io.in_wf_plus[i] + result;
        // Swap the reservoirs
        io.out_rv_plus[i] = io.in_rv_plus[i];
    } else {
        // MARK: Pulse
        for ( int k = 0; k < args.pulse_pointers.n; k++ ) {
            PHOENIX::Type::uint32 offset = args.p.subgrid_N2_with_halo * k;
            const Type::complex pulse = args.dev_ptrs.pulse_plus[i + offset];
            result += args.p.minus_i_over_h_bar_s * args.time[1] * pulse * args.pulse_pointers.amp[k]; //CUDA::gaussian_complex_oscillator(t, args.pulse_pointers.t0[k], args.pulse_pointers.sigma[k], args.pulse_pointers.freq[k]);
        }
        if ( args.p.stochastic_amplitude > 0.0 ) {
            const Type::complex in_rv = io.in_rv_plus[i];
            const Type::complex dw = args.dev_ptrs.random_number[i] * CUDA::sqrt( ( args.p.R * in_rv + args.p.gamma_c ) / ( Type::real( 4.0 ) * args.p.dV ) );
            result += dw;
        }
        io.out_wf_plus[i] = io.in_wf_plus[i] + result;

        // MARK: Minus
        result = 0.0;

        // MARK: Pulse
        for ( int k = 0; k < args.pulse_pointers.n; k++ ) {
            PHOENIX::Type::uint32 offset = args.p.subgrid_N2_with_halo * k;
            const Type::complex pulse = args.dev_ptrs.pulse_minus[i + offset];
            result += args.p.minus_i_over_h_bar_s * args.time[1] * pulse * args.pulse_pointers.amp[k]; //CUDA::gaussian_complex_oscillator(t, args.pulse_pointers.t0[k], args.pulse_pointers.sigma[k], args.pulse_pointers.freq[k]);
        }
        if ( args.p.stochastic_amplitude > 0.0 ) {
            const Type::complex in_rv = io.in_rv_minus[i];
            const Type::complex dw = args.dev_ptrs.random_number[i] * CUDA::sqrt( ( args.p.R * in_rv + args.p.gamma_c ) / ( Type::real( 4.0 ) * args.p.dV ) );
            result += dw;
        }
        io.out_wf_minus[i] = io.in_wf_minus[i] + result;
    }
}

} // namespace PHOENIX::Kernel::Compute
