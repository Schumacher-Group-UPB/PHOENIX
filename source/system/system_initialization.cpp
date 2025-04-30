#include <memory>
#include <algorithm>
#include <ranges>
#include <random>
#include "system/system_parameters.hpp"
#include "system/filehandler.hpp"
#include "misc/commandline_io.hpp"
#include "misc/escape_sequences.hpp"
#include "system/envelope.hpp"
#include "solver/iterator_config.hpp"
#include "omp.h"

void PHOENIX::SystemParameters::init( int argc, char** argv ) {
    // Initialize system
    int index = 0;

    // Structure
    use_twin_mode = false;
    if ( ( index = PHOENIX::CLIO::findInArgv( "-tetm", argc, argv ) ) != -1 ) {
        use_twin_mode = true;
    }

    if ( ( index = PHOENIX::CLIO::findInArgv( { "gammaC", "gamma_C", "gammac", "gamma_c" }, argc, argv, 0, "--" ) ) != -1 )
        p.gamma_c = PHOENIX::CLIO::getNextInput( argv, argc, "gamma_c", ++index );
    if ( ( index = PHOENIX::CLIO::findInArgv( { "gammaR", "gamma_R", "gammar", "gamma_r" }, argc, argv, 0, "--" ) ) != -1 )
        p.gamma_r = PHOENIX::CLIO::getNextInput( argv, argc, "gamma_r", ++index );
    if ( ( index = PHOENIX::CLIO::findInArgv( { "gc", "g_c" }, argc, argv, 0, "--" ) ) != -1 )
        p.g_c = PHOENIX::CLIO::getNextInput( argv, argc, "g_c", ++index );
    if ( ( index = PHOENIX::CLIO::findInArgv( { "gr", "g_r" }, argc, argv, 0, "--" ) ) != -1 )
        p.g_r = PHOENIX::CLIO::getNextInput( argv, argc, "g_r", ++index );
    if ( ( index = PHOENIX::CLIO::findInArgv( "--R", argc, argv ) ) != -1 ) {
        p.R = PHOENIX::CLIO::getNextInput( argv, argc, "R", ++index );
    }
    if ( ( index = PHOENIX::CLIO::findInArgv( { "L", "gridlength", "xmax" }, argc, argv, 0, "--" ) ) != -1 ) {
        p.L_x = PHOENIX::CLIO::getNextInput( argv, argc, "L", ++index );
        p.L_y = PHOENIX::CLIO::getNextInput( argv, argc, "L", index );
    }
    if ( ( index = PHOENIX::CLIO::findInArgv( { "g_pm", "gpm", "g_PM" }, argc, argv, 0, "--" ) ) != -1 ) {
        p.g_pm = PHOENIX::CLIO::getNextInput( argv, argc, "gm", ++index );
    }
    if ( ( index = PHOENIX::CLIO::findInArgv( { "deltaLT", "delta_LT", "deltalt", "dlt" }, argc, argv, 0, "--" ) ) != -1 ) {
        p.delta_LT = PHOENIX::CLIO::getNextInput( argv, argc, "deltaLT", ++index );
    }

    omp_max_threads = 4;
    if ( ( index = PHOENIX::CLIO::findInArgv( "--threads", argc, argv ) ) != -1 )
        omp_max_threads = (int)PHOENIX::CLIO::getNextInput( argv, argc, "threads", ++index );
    omp_set_num_threads( omp_max_threads );

    if ( ( index = PHOENIX::CLIO::findInArgv( "--blocksize", argc, argv ) ) != -1 )
        block_size = (int)PHOENIX::CLIO::getNextInput( argv, argc, "block_size", ++index );

    if ( ( index = PHOENIX::CLIO::findInArgv( "output", argc, argv ) ) != -1 ) {
        output_keys.clear();
        auto output_string = PHOENIX::CLIO::getNextStringInput( argv, argc, "output", ++index );
        // Split output_string at ","
        for ( auto range : output_string | std::views::split( ',' ) ) {
            std::string split_str;
            for ( auto ch : range ) {
                split_str += ch;
            }
            output_keys.emplace_back( split_str );
            //output_keys.emplace_back( std::string{ std::ranges::begin( range ), std::ranges::end( range ) } );
        }
    }

    // Numerik
    if ( ( index = PHOENIX::CLIO::findInArgv( { "N", "gridsize" }, argc, argv, 0, "--" ) ) != -1 ) {
        p.N_c = (int)PHOENIX::CLIO::getNextInput( argv, argc, "N_c", ++index );
        p.N_r = (int)PHOENIX::CLIO::getNextInput( argv, argc, "N_r", index );
    }
    p.subgrids_columns = 0;
    p.subgrids_rows = 0;
    if ( ( index = PHOENIX::CLIO::findInArgv( { "subgrids", "sg" }, argc, argv, 0, "--" ) ) != -1 ) {
        p.subgrids_columns = (int)PHOENIX::CLIO::getNextInput( argv, argc, "subgrids_columns", ++index );
        p.subgrids_rows = (int)PHOENIX::CLIO::getNextInput( argv, argc, "subgrids_rows", index );
    }

    // We can also disable to SFML renderer by using the --nosfml flag.
    disableRender = true;
#ifdef SFML_RENDER
    if ( PHOENIX::CLIO::findInArgv( "-nosfml", argc, argv ) == -1 and PHOENIX::CLIO::findInArgv( "-norender", argc, argv ) == -1 )
        disableRender = false;
#endif

    if ( ( index = PHOENIX::CLIO::findInArgv( { "tmax", "tend" }, argc, argv, 0, "--" ) ) != -1 )
        t_max = PHOENIX::CLIO::getNextInput( argv, argc, "s_t_max", ++index );
    if ( ( index = PHOENIX::CLIO::findInArgv( { "tstep", "dt" }, argc, argv, 0, "--" ) ) != -1 ) {
        p.dt = PHOENIX::CLIO::getNextInput( argv, argc, "t_step", ++index );
        do_overwrite_dt = false;
        std::cout << PHOENIX::CLIO::prettyPrint( "Overwritten (initial) dt to " + PHOENIX::CLIO::to_str( p.dt ), PHOENIX::CLIO::Control::Warning ) << std::endl;
    }
    if ( ( index = PHOENIX::CLIO::findInArgv( "--tol", argc, argv ) ) != -1 ) {
        tolerance = PHOENIX::CLIO::getNextInput( argv, argc, "tol", ++index );
    }
    if ( ( index = PHOENIX::CLIO::findInArgv( "--rkvdt", argc, argv ) ) != -1 ) {
        dt_min = PHOENIX::CLIO::getNextInput( argv, argc, "dt_min", ++index );
        dt_max = PHOENIX::CLIO::getNextInput( argv, argc, "dt_max", index );
    }
    imag_time_amplitude = 0.0;
    if ( ( index = PHOENIX::CLIO::findInArgv( "--imagTime", argc, argv ) ) != -1 ) {
        imag_time_amplitude = PHOENIX::CLIO::getNextInput( argv, argc, "imag_time_amplitude", ++index );
    }

    if ( ( index = PHOENIX::CLIO::findInArgv( "--fftEvery", argc, argv ) ) != -1 ) {
        fft_every = PHOENIX::CLIO::getNextInput( argv, argc, "fft_every", ++index );
    }

    // Choose the iterator
    iterator = "RK4";
    if ( ( index = PHOENIX::CLIO::findInArgv( "-ssfm", argc, argv ) ) != -1 ) {
        iterator = "SSFM";
    }
    if ( ( index = PHOENIX::CLIO::findInArgv( "--iterator", argc, argv ) ) != -1 ) {
        std::string it = PHOENIX::CLIO::getNextStringInput( argv, argc, "iterator", ++index );
        iterator = it;
    }

    if ( Iterator::available.find( iterator ) == Iterator::available.end() || !Iterator::available.at(iterator).implemented ) {
        std::cout << PHOENIX::CLIO::prettyPrint( "Iterator '" + iterator + "' is not implemented. Falling back to 'RK4'", PHOENIX::CLIO::Control::Warning ) << std::endl;
        std::cout << PHOENIX::CLIO::prettyPrint( "Available iterators are: ", PHOENIX::CLIO::Control::Info ) << std::endl;
        for ( auto& it : Iterator::available ) {
            std::cout << PHOENIX::CLIO::prettyPrint( " - " + it.first + ": " + std::string(it.second.name) + (it.second.implemented ? "" : "(not implemented)"), PHOENIX::CLIO::Control::Info ) << std::endl;
        }
        iterator = "RK4";
    }
    p.halo_size = Iterator::available.at(iterator).halo_size;
    std::cout << PHOENIX::CLIO::prettyPrint( "Using iterator '" + iterator + " - " + std::string(Iterator::available.at(iterator).name) + "' with halo size " + std::to_string( p.halo_size ), PHOENIX::CLIO::Control::Info ) << std::endl; 
    std::cout << PHOENIX::CLIO::prettyPrint( "Butcher Tableau: ", PHOENIX::CLIO::Control::Info ) << std::endl;
    std::cout << Iterator::available.at( iterator ).butcher_tableau << std::endl;

    if ( ( index = PHOENIX::CLIO::findInArgv( { "initRandom", "iR" }, argc, argv, 0, "--" ) ) != -1 ) {
        randomly_initialize_system = true;
        random_system_amplitude = PHOENIX::CLIO::getNextInput( argv, argc, "random_system_amplitude", ++index );
        random_seed = std::random_device{}();
        auto str_seed = PHOENIX::CLIO::getNextStringInput( argv, argc, "random_seed", index );
        if ( str_seed != "random" ) {
            random_seed = (Type::uint32)std::stod( str_seed );
            std::cout << PHOENIX::CLIO::prettyPrint( "Overwritten random seed to " + std::to_string( random_seed ), PHOENIX::CLIO::Control::Info ) << std::endl;
        }
    }

    if ( ( index = PHOENIX::CLIO::findInArgv( "--dw", argc, argv ) ) != -1 ) {
        p.stochastic_amplitude = PHOENIX::CLIO::getNextInput( argv, argc, "dw", ++index );
    }

    if ( ( index = PHOENIX::CLIO::findInArgv( "--outEvery", argc, argv ) ) != -1 )
        output_every = PHOENIX::CLIO::getNextInput( argv, argc, "output_every", ++index );

    history_matrix_output_increment = 1u;
    history_matrix_start_x = 0;
    history_matrix_start_y = 0;
    history_matrix_end_x = p.N_c;
    history_matrix_end_y = p.N_r;
    do_output_history_matrix = false;
    output_history_matrix_every = 1;
    output_history_start_time = 0.0;
    if ( ( index = PHOENIX::CLIO::findInArgv( { "historyMatrix", "hM" }, argc, argv, 0, "--" ) ) != -1 ) {
        history_matrix_start_x = (Type::uint32)PHOENIX::CLIO::getNextInput( argv, argc, "history_matrix_start_x", ++index );
        history_matrix_end_x = (Type::uint32)PHOENIX::CLIO::getNextInput( argv, argc, "history_matrix_end_x", index );
        history_matrix_start_y = (Type::uint32)PHOENIX::CLIO::getNextInput( argv, argc, "history_matrix_start_y", index );
        history_matrix_end_y = (Type::uint32)PHOENIX::CLIO::getNextInput( argv, argc, "history_matrix_end_y", index );
        history_matrix_output_increment = (Type::uint32)PHOENIX::CLIO::getNextInput( argv, argc, "history_matrix_output_increment", index );
        do_output_history_matrix = true;
    }
    if ( ( index = PHOENIX::CLIO::findInArgv( { "historyTime", "hT" }, argc, argv, 0, "--" ) ) != -1 ) {
        output_history_start_time = PHOENIX::CLIO::getNextInput( argv, argc, "history_time", ++index );
        output_history_matrix_every = int( PHOENIX::CLIO::getNextInput( argv, argc, "history_time_every", index ) );
    }

    p.periodic_boundary_x = false;
    p.periodic_boundary_y = false;
    if ( ( index = PHOENIX::CLIO::findInArgv( "--boundary", argc, argv ) ) != -1 ) {
        auto boundary_x = PHOENIX::CLIO::getNextStringInput( argv, argc, "boundary_x", ++index );
        auto boundary_y = PHOENIX::CLIO::getNextStringInput( argv, argc, "boundary_y", index );
        if ( boundary_x == "periodic" ) {
            p.periodic_boundary_x = true;
        }
        if ( boundary_y == "periodic" ) {
            p.periodic_boundary_y = true;
        }
    }

    // Initialize t_0 as 0.
    p.t = 0.0;
    if ( ( index = PHOENIX::CLIO::findInArgv( "--t0", argc, argv ) ) != -1 ) {
        p.t = PHOENIX::CLIO::getNextInput( argv, argc, "t0", ++index );
        std::cout << PHOENIX::CLIO::prettyPrint( "Overwritten (initial) t to " + PHOENIX::CLIO::to_str( p.t ), PHOENIX::CLIO::Control::Warning ) << std::endl;
    }

    // Even though one probably shouldn't do this, here we read the electron charge, hbar and electron mass from the commandline
    if ( ( index = PHOENIX::CLIO::findInArgv( "--hbar", argc, argv ) ) != -1 ) {
        p.h_bar = PHOENIX::CLIO::getNextInput( argv, argc, "hbar", ++index );
    }
    if ( ( index = PHOENIX::CLIO::findInArgv( { "electron_charge", "e" }, argc, argv, 0, "--" ) ) != -1 ) {
        p.e_e = PHOENIX::CLIO::getNextInput( argv, argc, "e", ++index );
    }
    if ( ( index = PHOENIX::CLIO::findInArgv( { "me", "m_e", "electron_mass" }, argc, argv, 0, "--" ) ) != -1 ) {
        p.m_e = PHOENIX::CLIO::getNextInput( argv, argc, "me", ++index );
    }
    // We can also directly set h_bar_scaled, which will result in hbar, e and me to be ignored
    if ( ( index = PHOENIX::CLIO::findInArgv( { "hbarscaled", "hbar_scaled", "hbars" }, argc, argv, 0, "--" ) ) != -1 ) {
        p.h_bar_s = PHOENIX::CLIO::getNextInput( argv, argc, "hbars", ++index );
    }
    // Same goes for the scaled mass.
    if ( ( index = PHOENIX::CLIO::findInArgv( { "meff", "m_eff" }, argc, argv, 0, "--" ) ) != -1 )
        p.m_eff = PHOENIX::CLIO::getNextInput( argv, argc, "m_eff", ++index );

    //////////////////////////////
    // Custom Read-Ins go here! //
    //////////////////////////////

    // Pumps
    pump = PHOENIX::Envelope::fromCommandlineArguments( argc, argv, "pump", true /* Can have oscillation component */ );
    // Potential
    potential = PHOENIX::Envelope::fromCommandlineArguments( argc, argv, "potential", true /* Can have oscillation component */ );
    // Pulses
    pulse = PHOENIX::Envelope::fromCommandlineArguments( argc, argv, "pulse", true /* Can have oscillation component */ );
    // FFT Mask
    fft_mask = PHOENIX::Envelope::fromCommandlineArguments( argc, argv, "fftMask", false );
    // Initial State and Reservoir
    initial_state = PHOENIX::Envelope::fromCommandlineArguments( argc, argv, { "initState", "initialState", "iS" }, false );
    initial_reservoir = PHOENIX::Envelope::fromCommandlineArguments( argc, argv, { "initReservoir", "initialReservoir", "iR" }, false );

    // Set evaluation flags
    use_reservoir = true;
    use_pumps = pump.size() > 0;
    use_pulses = pulse.size() > 0;
    use_potentials = potential.size() > 0;
    use_fft_mask = fft_mask.size() > 0;
    use_stochastic = p.stochastic_amplitude > 0.0;
    if ( pump.size() == 0 && initial_reservoir.size() == 0 ) {
        use_reservoir = false;
    }
    if ( ( index = PHOENIX::CLIO::findInArgv( "-noReservoir", argc, argv ) ) != -1 ) {
        use_reservoir = false;
    }

    std::cout << PHOENIX::CLIO::prettyPrint( "Using Reservoir: " + std::to_string( use_reservoir ), PHOENIX::CLIO::Control::Info ) << std::endl;
    std::cout << PHOENIX::CLIO::prettyPrint( "Using Pumps: " + std::to_string( use_pumps ), PHOENIX::CLIO::Control::Info ) << std::endl;
    std::cout << PHOENIX::CLIO::prettyPrint( "Using Pulses: " + std::to_string( use_pulses ), PHOENIX::CLIO::Control::Info ) << std::endl;
    std::cout << PHOENIX::CLIO::prettyPrint( "Using Potentials: " + std::to_string( use_potentials ), PHOENIX::CLIO::Control::Info ) << std::endl;
    std::cout << PHOENIX::CLIO::prettyPrint( "Using Stochastic: " + std::to_string( use_stochastic ), PHOENIX::CLIO::Control::Info ) << std::endl;

    ///////////////////////////////////////
    // Custom Envelope Read-Ins go here! //
    ///////////////////////////////////////
}