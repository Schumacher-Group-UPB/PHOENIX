#include <memory>
#include <algorithm>
#include <random>
#include <ranges>
#include <vector>
#include "cuda/typedef.cuh"
#include "solver/solver.hpp"
#include "misc/escape_sequences.hpp"
#include "misc/commandline_io.hpp"

namespace PHOENIX {

void Solver::initialize() {
    std::cout << CLIO::prettyPrint( "Creating Solver...", CLIO::Control::Info ) << std::endl;
    // Number of subgrid points
    // TODO: make this better, double definition
    system.p.halo_size = halo_size_;

    system.p.subgrid_N_c = system.p.N_c / system.p.subgrids_columns;
    system.p.subgrid_N_r = system.p.N_r / system.p.subgrids_rows;
    system.p.subgrid_N2 = system.p.subgrid_N_c * system.p.subgrid_N_r;
    system.p.subgrid_N2_with_halo = ( system.p.subgrid_N_c + 2 * system.p.halo_size ) * ( system.p.subgrid_N_r + 2 * system.p.halo_size );
    // Row offset for a subgrid- i +/- row offset is the row above/below
    system.p.subgrid_row_offset = system.p.subgrid_N_c + 2 * system.p.halo_size;

    // Initialize all matrices
    initializeMatricesFromSystem();
    // Then output all matrices to file. If --output was not passed in argv, this method outputs everything.
#ifndef BENCH
    outputInitialMatrices();
#endif
}

void Solver::initializeMatricesFromSystem() {
    std::cout << EscapeSequence::BOLD
              << "-------------------- Initializing Host and Device Matrices "
                 "------------------------"
              << EscapeSequence::RESET << std::endl;

    // First, construct all required host matrices
    bool use_fft = system.fft_every < system.t_max or system.iterator == "ssfm";
    // For now, both the plus and the minus components are the same. TODO: Change
    Type::uint32 pulse_size = system.pulse.groupSize();
    Type::uint32 pump_size = system.pump.groupSize();
    Type::uint32 potential_size = system.potential.groupSize();
    matrix.constructAll( system.p.N_c, system.p.N_r, system.use_twin_mode, use_fft, system.use_stochastic, system.use_reservoir, k_max_, pulse_size, pump_size, potential_size, pulse_size, pump_size, potential_size, system.p.subgrids_columns, system.p.subgrids_rows, system.p.halo_size );

    // ==================================================
    // =................... Halo Map ...................=
    // ==================================================
    initializeHaloMap();

    // ==================================================
    // =................ Initial States ................=
    // ==================================================
    std::cout << CLIO::prettyPrint( "Initializing Host Matrices...", CLIO::Control::Info ) << std::endl;

    Envelope::Dimensions dim{ system.p.N_c, system.p.N_r, system.p.L_x, system.p.L_y, system.p.dx, system.p.dy };

    // First, check whether we should adjust the starting states to match a mask. This will initialize the buffer.
    system.initial_state.calculate( system.filehandler, matrix.initial_state_plus.data(), Envelope::AllGroups, Envelope::Polarization::Plus, dim );
    if ( system.use_reservoir )
        system.initial_reservoir.calculate( system.filehandler, matrix.initial_reservoir_plus.data(), Envelope::AllGroups, Envelope::Polarization::Plus, dim );
    if ( system.use_twin_mode ) {
        system.initial_state.calculate( system.filehandler, matrix.initial_state_minus.data(), Envelope::AllGroups, Envelope::Polarization::Minus, dim );
        if ( system.use_reservoir )
            system.initial_reservoir.calculate( system.filehandler, matrix.initial_reservoir_minus.data(), Envelope::AllGroups, Envelope::Polarization::Minus, dim );
    }

    // Then, check whether we should initialize the system randomly. Add that random value to the initial state.
    if ( system.randomly_initialize_system ) {
        // Fill the buffer with random values
        std::mt19937 gen{ system.random_seed };
        std::uniform_real_distribution<Type::real> dist{ -system.random_system_amplitude, system.random_system_amplitude };
        std::ranges::for_each( matrix.initial_state_plus.begin(), matrix.initial_state_plus.end(), [&dist, &gen]( Type::complex& z ) { z += Type::complex{ dist( gen ), dist( gen ) }; } );
        // Also fill minus component if use_twin_mode is true
        if ( system.use_twin_mode )
            std::ranges::for_each( matrix.initial_state_minus.begin(), matrix.initial_state_minus.end(), [&dist, &gen]( Type::complex& z ) { z += Type::complex{ dist( gen ), dist( gen ) }; } );
    }
    // Copy the initial state to the device wavefunction, synchronize it to the device and synchronize the halos
    matrix.wavefunction_plus.setTo( matrix.initial_state_plus );
    matrix.wavefunction_plus.hostToDeviceSync();
    SYNCHRONIZE_HALOS( 0, matrix.wavefunction_plus.getSubgridDevicePtrs() );
    if ( system.use_reservoir ) {
        matrix.reservoir_plus.setTo( matrix.initial_reservoir_plus );
        matrix.reservoir_plus.hostToDeviceSync();
        SYNCHRONIZE_HALOS( 0, matrix.reservoir_plus.getSubgridDevicePtrs() );
    }

    if ( system.use_twin_mode ) {
        matrix.wavefunction_minus.setTo( matrix.initial_state_minus );
        matrix.wavefunction_minus.hostToDeviceSync();
        SYNCHRONIZE_HALOS( 0, matrix.wavefunction_minus.getSubgridDevicePtrs() );
        if ( system.use_reservoir ) {
            matrix.reservoir_minus.setTo( matrix.initial_reservoir_minus );
            matrix.reservoir_minus.hostToDeviceSync();
            SYNCHRONIZE_HALOS( 0, matrix.reservoir_minus.getSubgridDevicePtrs() );
        }
    }

    // ==================================================
    // =................ Pump Envelopes ................=
    // ==================================================
    std::cout << CLIO::prettyPrint( "Initializing Pump Envelopes...", CLIO::Control::Info ) << std::endl;
    for ( int pump = 0; pump < system.pump.groupSize(); pump++ ) {
        system.pump.calculate( system.filehandler, matrix.pump_plus.getHostPtr( pump ), pump, Envelope::Polarization::Plus, dim );
        matrix.pump_plus.hostToDeviceSync( pump );
        SYNCHRONIZE_HALOS( 0, matrix.pump_plus.getSubgridDevicePtrs( pump ) );
        if ( system.use_twin_mode ) {
            system.pump.calculate( system.filehandler, matrix.pump_minus.getHostPtr( pump ), pump, Envelope::Polarization::Minus, dim );
            matrix.pump_minus.hostToDeviceSync( pump );
            SYNCHRONIZE_HALOS( 0, matrix.pump_minus.getSubgridDevicePtrs( pump ) );
        }
    }
    std::cout << CLIO::prettyPrint( "Succesfull, designated number of pump groups: " + std::to_string( system.pump.groupSize() ), CLIO::Control::Secondary | CLIO::Control::Success ) << std::endl;

    // ==================================================
    // =............. Potential Envelopes ..............=
    // ==================================================
    std::cout << CLIO::prettyPrint( "Initializing Potential Envelopes...", CLIO::Control::Info ) << std::endl;
    for ( int potential = 0; potential < system.potential.groupSize(); potential++ ) {
        system.potential.calculate( system.filehandler, matrix.potential_plus.getHostPtr( potential ), potential, Envelope::Polarization::Plus, dim );
        matrix.potential_plus.hostToDeviceSync( potential );
        SYNCHRONIZE_HALOS( 0, matrix.potential_plus.getSubgridDevicePtrs( potential ) );
        if ( system.use_twin_mode ) {
            system.potential.calculate( system.filehandler, matrix.potential_minus.getHostPtr( potential ), potential, Envelope::Polarization::Minus, dim );
            matrix.potential_minus.hostToDeviceSync( potential );
            SYNCHRONIZE_HALOS( 0, matrix.potential_minus.getSubgridDevicePtrs( potential ) );
        }
    }
    std::cout << CLIO::prettyPrint( "Succesfull, designated number of potential groups: " + std::to_string( system.potential.groupSize() ), CLIO::Control::Secondary | CLIO::Control::Success ) << std::endl;

    // ==================================================
    // =............... Pulse Envelopes ................=
    // ==================================================
    std::cout << CLIO::prettyPrint( "Initializing Pulse Envelopes...", CLIO::Control::Info ) << std::endl;
    for ( int pulse = 0; pulse < system.pulse.groupSize(); pulse++ ) {
        system.pulse.calculate( system.filehandler, matrix.pulse_plus.getHostPtr( pulse ), pulse, Envelope::Polarization::Plus, dim );
        matrix.pulse_plus.hostToDeviceSync( pulse );
        SYNCHRONIZE_HALOS( 0, matrix.pulse_plus.getSubgridDevicePtrs( pulse ) );
        if ( system.use_twin_mode ) {
            system.pulse.calculate( system.filehandler, matrix.pulse_minus.getHostPtr( pulse ), pulse, Envelope::Polarization::Minus, dim );
            matrix.pulse_minus.hostToDeviceSync( pulse );
            SYNCHRONIZE_HALOS( 0, matrix.pulse_minus.getSubgridDevicePtrs( pulse ) );
        }
    }
    std::cout << CLIO::prettyPrint( "Succesfull, designated number of pulse groups: " + std::to_string( system.pulse.groupSize() ), CLIO::Control::Secondary | CLIO::Control::Success ) << std::endl;

    // ==================================================
    // =................. FFT Envelopes ................=
    // ==================================================
    Type::host_vector<Type::real> buffer( system.p.N_c * system.p.N_r, 0.0 );
    std::cout << CLIO::prettyPrint( "Initializing FFT Envelopes...", CLIO::Control::Info ) << std::endl;
    if ( !system.use_fft_mask ) {
        std::cout << CLIO::prettyPrint( "No fft mask provided.", CLIO::Control::Secondary | CLIO::Control::Warning ) << std::endl;
    } else {
        system.fft_mask.calculate( system.filehandler, buffer.data(), Envelope::AllGroups, Envelope::Polarization::Plus, dim, 1.0 /* Default if no mask is applied */ );
        matrix.fft_mask_plus = buffer;
        // Shift the filter
        auto [block_size, grid_size] = getLaunchParameters( system.p.N_c, system.p.N_r );
        CALL_FULL_KERNEL( Kernel::fft_shift_2D<Type::real>, "FFT Shift Plus", grid_size, block_size, 0, GET_RAW_PTR( matrix.fft_mask_plus ), system.p.N_c, system.p.N_r );
        if ( system.use_twin_mode ) {
            system.fft_mask.calculate( system.filehandler, buffer.data(), Envelope::AllGroups, Envelope::Polarization::Minus, dim, 1.0 /* Default if no mask is applied */ );
            matrix.fft_mask_minus = buffer;
            // Shift the filter
            CALL_FULL_KERNEL( Kernel::fft_shift_2D<Type::real>, "FFT Shift Minus", grid_size, block_size, 0, GET_RAW_PTR( matrix.fft_mask_minus ), system.p.N_c, system.p.N_r );
        }
    }

    //////////////////////////////////////////////////
    // Custom Envelope Initializations go here      //
    // Just copy the one above and change the names //
    //////////////////////////////////////////////////
}

template <typename T>
T delta( T a, T b ) {
    return a == b ? (T)1 : (T)0;
}

void Solver::initializeHaloMap() {
    std::cout << CLIO::prettyPrint( "Initializing Halo Map...", CLIO::Control::Info ) << std::endl;

    Type::host_vector<int> halo_map;

    // Create subgrid map
    for ( int dr = -1; dr <= 1; dr++ ) {
        for ( int dc = -1; dc <= 1; dc++ ) {
            if ( dc == 0 and dr == 0 )
                continue;

            const Type::uint32 fr0 = delta( -1, dr ) * system.p.subgrid_N_r + ( 1 - delta( -1, dr ) ) * system.p.halo_size;
            const Type::uint32 fr1 = ( delta( 0, dr ) + delta( -1, dr ) ) * system.p.subgrid_N_r + system.p.halo_size + delta( dr, 1 ) * system.p.halo_size;
            const Type::uint32 fc0 = delta( -1, dc ) * system.p.subgrid_N_c + ( 1 - delta( -1, dc ) ) * system.p.halo_size;
            const Type::uint32 fc1 = ( delta( 0, dc ) + delta( -1, dc ) ) * system.p.subgrid_N_c + system.p.halo_size + delta( dc, 1 ) * system.p.halo_size;

            const Type::uint32 tr0 = delta( 1, dr ) * system.p.subgrid_N_r + ( 1 - delta( -1, dr ) ) * system.p.halo_size;
            const Type::uint32 tr1 = ( 1 - delta( -1, dr ) ) * system.p.subgrid_N_r + system.p.halo_size + delta( 1, dr ) * system.p.halo_size;
            const Type::uint32 tc0 = delta( 1, dc ) * system.p.subgrid_N_c + ( 1 - delta( -1, dc ) ) * system.p.halo_size;
            const Type::uint32 tc1 = ( 1 - delta( -1, dc ) ) * system.p.subgrid_N_c + system.p.halo_size + delta( 1, dc ) * system.p.halo_size;

            for ( int i = 0; i < fr1 - fr0; i++ ) {
                for ( int j = 0; j < fc1 - fc0; j++ ) {
                    const int from_row = fr0 + i;
                    const int from_col = fc0 + j;
                    const int to_row = tr0 + i;
                    const int to_col = tc0 + j;
                    halo_map.push_back( dr );
                    halo_map.push_back( dc );
                    halo_map.push_back( from_row );
                    halo_map.push_back( from_col );
                    halo_map.push_back( to_row );
                    halo_map.push_back( to_col );
                }
            }
        }
    }
    std::cout << CLIO::prettyPrint( "Designated number of halo cells: " + std::to_string( halo_map.size() / 6 ), CLIO::Control::Secondary | CLIO::Control::Success ) << std::endl;
    matrix.halo_map = halo_map;
}

} // namespace PHOENIX