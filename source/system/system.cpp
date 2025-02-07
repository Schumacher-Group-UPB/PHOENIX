#include <memory>
#include <algorithm>
#include <ranges>
#include <random>
#include "system/system_parameters.hpp"
#include "system/filehandler.hpp"
#include "misc/commandline_io.hpp"
#include "misc/escape_sequences.hpp"
#include "system/envelope.hpp"
#include "omp.h"

/**
 * @brief Default Constructor for the System Class
 * Defaul-initializes system parameters, which are
 * overwritten by the user cmd input.
 *
 */
PHOENIX::SystemParameters::SystemParameters() {
    // SI Rescaling Units
    p.m_e = 9.10938356E-31;
    p.h_bar = 1.0545718E-34;
    p.e_e = 1.60217662E-19;
    // h_bar_scaled will be calculated in the calculateAuto() function
    p.h_bar_s = -1; // = hbar*e*1E12 == 6.582119514E-4;

    // System Variables
    p.m_eff = -1; // = 1E-4 * m_e / e * 1E12  = 0.00056856;
    p.m_eff_scaled = 0;
    p.gamma_c = 0.15;            // ps^-1
    p.gamma_r = 1.5 * p.gamma_c; // ps^-1
    p.g_c = 3.E-6;               // meV mum^2
    p.g_r = 2. * p.g_c;          // meV mum^2
    p.R = 0.01;                  // ps^-1 mum^2
    p.L_x = 100.;                // mum
    p.L_y = 100.;                // mum
    p.g_pm = -p.g_c / 5;         // meV mum^2
    p.delta_LT = 0.025E-3;       // meV

    // Numerics
    p.N_c = 400;
    p.N_r = 400;
    p.subgrids_columns = 0;
    p.subgrids_rows = 0;
    t_max = 1000;
    iteration = 0;
    // RK Solver Variables
    p.t = 1000;
    output_every = 1;
    dt_max = 3;
    dt_min = 0.0001; // also dt_delta
    tolerance = 1E-1;
    do_overwrite_dt = true;

    // FFT Mask every x ps
    fft_every = 1; // ps

    // Kernel Block Size
    block_size = 256;
    omp_max_threads = omp_get_max_threads();

    // Default Solver is RK4
    iterator = "rk4";

    // Output of Variables
    output_keys = { "mat", "scalar" };

    // By Default, no stochstic noise is added
    p.stochastic_amplitude = 0.0;

    randomly_initialize_system = false;
    random_system_amplitude = 1.0;
}

std::tuple<size_t, size_t> find_auto_subgridsize( size_t total_rows, size_t total_cols ) {
    size_t row_divisor = 1;
    size_t col_divisor = 1;
#ifdef USE_CPU
    // Use predefined subgrid sizes if divisible, otherwise try division by 2, 4, 6, 8, 10, or use 1.
    // 2 should never fail, as the number of points should always be even.
    for ( size_t try_size : { 32, 64, 50, 25, 100 } ) {
        if ( total_cols % try_size == 0 && col_divisor == 1 ) {
            col_divisor = total_cols / try_size;
        }
        if ( total_rows % try_size == 0 && row_divisor == 1 ) {
            row_divisor = total_rows / try_size;
        }
    }
    for ( size_t try_size : { 10, 8, 6, 4, 2 } ) {
        if ( total_cols % try_size == 0 && col_divisor == 1 ) {
            col_divisor = total_cols / try_size;
        }
        if ( total_rows % try_size == 0 && row_divisor == 1 ) {
            row_divisor = total_rows / try_size;
        }
    }
#else
    // Determine Size of Iteration
    // Subdivide grid into subgrids of approximately 500x500 cells for optimal GPU performance.
    // To make sure we have a good balance between the number of subgrids and the number of cells in each subgrid, we use 750 as a divisor.

    row_divisor = total_rows / 750 + 1;
    col_divisor = total_cols / 750 + 1;
    // Subdivide further if the grid is not divisible by the current divisor
    // We also know that more than 3-5 subgrids are not beneficial, as the overhead from calling the kernel is too high.
    while ( total_rows % row_divisor != 0 && row_divisor < 5 ) {
        row_divisor++;
    }
    while ( total_cols % col_divisor != 0 && col_divisor < 5 ) {
        col_divisor++;
    }
    return { col_divisor, row_divisor };
#endif
    return { col_divisor, row_divisor };
}

void PHOENIX::SystemParameters::calculateAuto() {
    // If hbar_s is < 0, calculate it
    if ( p.h_bar_s < 0 ) {
        p.h_bar_s = p.h_bar / p.e_e * 1E12;
    }
    // If m_eff is < 0, calculate it
    if ( p.m_eff < 0 ) {
        p.m_eff = p.m_e / p.e_e * 1E8;
    }

    // SI scaling factor for the magic timestep. If the user choses a custom
    // effective mass, the magic timestep will be scaled accordingly.
    const auto dt_scaling_factor = p.m_e / p.e_e * 1E8 / p.m_eff;
    // Spatial steps
    p.dx = p.L_x / ( p.N_c - 1 );
    p.dy = p.L_y / ( p.N_r - 1 );
    p.dV = p.dx * p.dy; // Volume element
    // Inverse squared spatial steps
    p.one_over_dx2 = Type::real( 1.0 ) / ( p.dx * p.dx );
    p.one_over_dy2 = Type::real( 1.0 ) / ( p.dy * p.dy );
    p.m2_over_dx2_p_dy2 = Type::real( -2.0 ) * ( p.one_over_dx2 + p.one_over_dy2 );
    // Number of grid points
    p.N2 = p.N_c * p.N_r;

    auto [suggested_subgrids_columns, suggested_subgrids_rows] = find_auto_subgridsize( p.N_r, p.N_c );
    if ( p.subgrids_rows == 0 ) {
        p.subgrids_rows = suggested_subgrids_rows;
    }
    if ( p.subgrids_columns == 0 ) {
        p.subgrids_columns = suggested_subgrids_columns;
    }

    // Number of subgrid points
    p.subgrid_N_c = p.N_c / p.subgrids_columns;
    p.subgrid_N_r = p.N_r / p.subgrids_rows;
    p.subgrid_N2 = p.subgrid_N_c * p.subgrid_N_r;
    p.subgrid_N2_with_halo = ( p.subgrid_N_c + 2 * p.halo_size ) * ( p.subgrid_N_r + 2 * p.halo_size );
    // Row offset for a subgrid- i +/- row offset is the row above/below
    p.subgrid_row_offset = p.subgrid_N_c + 2 * p.halo_size;
    // Effective mass, scaled with hbar
    p.m_eff_scaled = -0.5 * p.h_bar_s * p.h_bar_s / p.m_eff;
    // Magic timestep
    magic_timestep = 0.5 * p.dx * p.dy / dt_scaling_factor;
    if ( do_overwrite_dt ) {
        p.dt = magic_timestep;
    }
    // Calculate scaled imaginary values
    p.one_over_h_bar_s = 1.0 / p.h_bar_s;
    p.minus_i_over_h_bar_s = Type::complex( 0.0, -Type::real( 1.0 ) / p.h_bar_s );
    p.i_h_bar_s = Type::complex( 0.0, p.h_bar_s );
}

PHOENIX::SystemParameters::SystemParameters( int argc, char** argv ) : SystemParameters() {
    // Check if help is requested
    bool verbose_help = PHOENIX::CLIO::findInArgv( "--helpVerbose", argc, argv ) != -1 || PHOENIX::CLIO::findInArgv( "-hv", argc, argv ) != -1;
    if ( PHOENIX::CLIO::findInArgv( "--help", argc, argv ) != -1 || PHOENIX::CLIO::findInArgv( "-h", argc, argv ) != -1 || verbose_help ) {
        bool generate_markdown = PHOENIX::CLIO::findInArgv( "--markdown", argc, argv ) != -1 || PHOENIX::CLIO::findInArgv( "-mk", argc, argv ) != -1;
        calculateAuto();
        printHelp( verbose_help, generate_markdown );
        exit( 0 );
    }

    std::cout << EscapeSequence::BOLD << "---------------------------- Inputting System Parameters --------------------------" << EscapeSequence::RESET << std::endl;

    // Read-In commandline arguments
    init( argc, argv );

    // Calculate or scale variables
    calculateAuto();

    // Validate them
    validateInputs();

    filehandler.init( argc, argv );
}

bool PHOENIX::SystemParameters::evaluateStochastic() {
    return p.stochastic_amplitude != 0.0;
}