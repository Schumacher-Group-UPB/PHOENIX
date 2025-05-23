#include <ctime>
#include <iomanip> // std::setprecision, std::setw, std::setfill
#include <algorithm>
#include <ranges> // std::views::split
#include <any>
#include <map>
#include "system/system_parameters.hpp"
#include "cuda/cuda_matrix_base.hpp"
#include "misc/commandline_io.hpp"
#include "misc/escape_sequences.hpp"
#include "misc/timeit.hpp"
#include "solver/solver_factory.hpp"
#include "omp.h"

#ifndef PHOENIX_VERSION
    #define PHOENIX_VERSION "unknown"
#endif

// Automatically determine console width depending on windows or linux
#ifdef _WIN32
    #include <windows.h>
static size_t getConsoleWidth() {
    CONSOLE_SCREEN_BUFFER_INFO csbi;
    GetConsoleScreenBufferInfo( GetStdHandle( STD_OUTPUT_HANDLE ), &csbi );
    return csbi.srWindow.Right - csbi.srWindow.Left + 1;
}
#else
    #include <sys/ioctl.h>
static size_t getConsoleWidth() {
    struct winsize w;
    ioctl( 0, TIOCGWINSZ, &w );
    return w.ws_col;
}
#endif
static size_t console_width = std::min<size_t>( std::max<size_t>( getConsoleWidth(), 100 ), 500 );

// File-Local Configuration
static char major_seperator = '=';
static char minor_seperator = '-';
static char seperator = '.';

/*
Prints PHOENIX. Font is CyberLarge
 _____    _     _    _____    _______   __   _   _____   _     _  
|_____]   |_____|   |     |   |______   | \  |     |      \___/   
|       . |     | . |_____| . |______ . |  \_| . __|__ . _/   \_ .

*/
void print_name() {
    std::cout << PHOENIX::CLIO::fillLine( console_width, major_seperator ) << "\n\n"; // Horizontal Separator
    std::cout << EscapeSequence::ORANGE << EscapeSequence::BOLD;                      // Make Text Bold

    // Print Phoenix LOGO
    std::cout << PHOENIX::CLIO::centerString( " _____    _     _    _____    _______   __   _   _____   _     _  ", console_width ) << "\n";
    std::cout << PHOENIX::CLIO::centerString( "|_____]   |_____|   |     |   |______   | \\  |     |      \\___/   ", console_width ) << "\n";
    std::cout << PHOENIX::CLIO::centerString( "|       . |     | . |_____| . |______ . |  \\_| . __|__ . _/   \\_ .", console_width ) << "\n\n";

    std::stringstream ss;

    // Program Description
    ss << EscapeSequence::RESET << EscapeSequence::UNDERLINE << EscapeSequence::BOLD << EscapeSequence::BLUE << "P" << EscapeSequence::GRAY << "aderborn " << EscapeSequence::BLUE << "H" << EscapeSequence::GRAY << "ighly " << EscapeSequence::BLUE << "O" << EscapeSequence::GRAY << "ptimized and " << EscapeSequence::BLUE << "E" << EscapeSequence::GRAY << "nergy efficient solver for two-dimensional" << EscapeSequence::RESET;
    std::cout << PHOENIX::CLIO::centerStringRaw( ss.str(), console_width, "Paderborn Highly Optimized and Energy efficient solver for two-dimensional" ) << std::endl;
    ss.str( "" );
    ss.clear();

    ss << EscapeSequence::RESET << EscapeSequence::UNDERLINE << EscapeSequence::BLUE << "N" << EscapeSequence::GRAY << "onlinear Schroedinger equations with " << EscapeSequence::BLUE << "I" << EscapeSequence::GRAY << "ntegrated e" << EscapeSequence::BLUE << "X" << EscapeSequence::GRAY << "tensions" << EscapeSequence::RESET;
    std::cout << PHOENIX::CLIO::centerStringRaw( ss.str(), console_width, "Nonlinear Schroedinger equations with Integrated Xtensions" ) << std::endl;
    ss.str( "" );
    ss.clear();

    // Version Information
    ss << "Version: " << EscapeSequence::BOLD << EscapeSequence::BLUE << PHOENIX_VERSION << EscapeSequence::RESET;
    std::cout << PHOENIX::CLIO::centerStringRaw( ss.str(), console_width, "Version: " + std::string(PHOENIX_VERSION) ) << std::endl;
    //std::cout << PHOENIX::CLIO::centerString( "https://github.com/Schumacher-Group-UPB/PHOENIX", console_width ) << std::endl;

    // Citation Information
    std::cout << "\n" << PHOENIX::CLIO::fillLine( console_width, minor_seperator ) << "\n"; // Horizontal Separator
    ss.str( "" );
    ss.clear();

    // Citation Message
    ss << "If you use this program, please cite the repository using: " << EscapeSequence::RESET;
    std::cout << EscapeSequence::BOLD << EscapeSequence::GRAY << PHOENIX::CLIO::centerStringRaw( ss.str(), console_width ) << std::endl;
    ss.str( "" );
    ss.clear();

    ss << "Bauch, D., Schade, R., Wingenbach, J., and Schumacher, S.";
    std::cout << EscapeSequence::ORANGE << PHOENIX::CLIO::centerStringRaw( ss.str(), console_width ) << EscapeSequence::RESET << std::endl;
    ss.str( "" );
    ss.clear();
    ss << "PHOENIX: A High-Performance Solver for the Gross-Pitaevskii Equation [Computer software].";
    std::cout << EscapeSequence::ORANGE << PHOENIX::CLIO::centerStringRaw( ss.str(), console_width ) << EscapeSequence::RESET << std::endl;
    ss.str( "" );
    ss.clear();
    ss << "https://github.com/Schumacher-Group-UPB/PHOENIX";
    std::cout << EscapeSequence::ORANGE << PHOENIX::CLIO::centerStringRaw( ss.str(), console_width ) << EscapeSequence::RESET << std::endl;
}

// We use a semi-automated approach to generate the help, documentation and final output.
// We use a custom struct for this that includes the name, key, description, use case examples and so on.
// We can then add new parameters to the struct. Outputting is required to be added manually, but this way we define everything
// relevant to the variable in a single scruct, allowing for easy access, modification and expansions.
// We use a std::map<std::string, ArgInfo> to store the parameters and their information, which unfortunately cannot be made constexpr.
// This also gives us the ability to print expecptions to the ArgInfo in different ways if we want that.

struct ArgInfo {
    std::string name = "";
    std::string key = "";
    std::string unit = "";
    std::string short_description = "";
    std::string long_description = "";
    std::string short_usecase = "";
    std::string long_usecase = "";

    void print( const std::any& default_value, bool verbose = true ) const {
        const size_t L1 = std::min<size_t>( 0.3 * console_width - 1, 50 );
        const size_t L2 = std::min<size_t>( 0.3 * console_width - 1, 50 );
        const size_t L3 = console_width - 15 - L2 - L1;

        std::string default_str = "";

        if ( default_value.type() == typeid( int ) ) {
            default_str = "Default is " + std::to_string( std::any_cast<int>( default_value ) ) + unit;
        } else if ( default_value.type() == typeid( PHOENIX::Type::real ) ) {
            default_str = "Default is " + std::to_string( std::any_cast<PHOENIX::Type::real>( default_value ) ) + unit;
        } else if ( default_value.type() == typeid( PHOENIX::Type::complex ) ) {
            default_str = "Default is " + std::to_string( PHOENIX::CUDA::real( std::any_cast<PHOENIX::Type::complex>( default_value ) ) ) + "+i" + std::to_string( PHOENIX::CUDA::imag( std::any_cast<PHOENIX::Type::complex>( default_value ) ) ) + unit;
        } else if ( default_value.type() == typeid( std::string ) ) {
            default_str = "Default is '" + std::any_cast<std::string>( default_value ) + "'" + unit;
        }

        bool include_dot = ( verbose ? long_description : short_description ).back() != '.';
        bool first = false;
        for ( auto description : ( verbose ? long_description : short_description ) | std::views::split( '\n' ) ) {
            if ( !first ) {
                std::cout << PHOENIX::CLIO::unifyLength( name, key, std::string{ std::ranges::begin( description ), std::ranges::end( description ) } + ( include_dot ? ". " : " " ) + default_str, L1, L2, L3 ) << std::endl;
                first = true;
            } else {
                std::cout << PHOENIX::CLIO::unifyLength( "", "", std::string{ std::ranges::begin( description ), std::ranges::end( description ) }, L1, L2, L3 ) << std::endl;
            }
        }
        for ( auto usecase : ( verbose ? long_usecase : short_usecase ) | std::views::split( '\n' ) ) {
            std::cout << EscapeSequence::GRAY << PHOENIX::CLIO::unifyLength( "", "", "Example: " + std::string{ std::ranges::begin( usecase ), std::ranges::end( usecase ) }, L1, L2, L3 ) << EscapeSequence::RESET << std::endl;
        }
    }

    void print_markdown( const std::any& default_value ) const {
    }

    void print_usecase( const std::any& default_value, bool verbose = true, bool markdown = false ) const {
        if ( markdown )
            print_markdown( default_value );
        else
            print( default_value, verbose );
    }
};

// TODO: arginfo weg, map von map.
// clang-format off
const std::map<std::string_view, ArgInfo> arguments{
    { "path", 
        { 
            .name{ "--path" }, 
            .key{ "<string>" }, 
            .short_description{ "Working folder" }, 
            .long_description{ "Target working folder for PHOENIX generated data. If this folder does not yet exist, PHOENIX will try and create it" }, 
            .short_usecase{ "--path 'path/to/folder'" }, 
            .long_usecase{ "--path 'path/to/folder'" } 
        } 
    },
    { "config",
        { 
            .name{ "--config" },
            .key{ "<string>" },
            .short_description{ "Loads configuration from file" },
            .long_description{ "Loads commandline arguments from a configuration file. Multiple configurations can be superimposed by using multiple config flags. Note: the different configuration files can overwrite previous parameters" },
            .short_usecase{ "--config 'path/to/config.txt'" },
            .long_usecase{ "--config 'path/to/config.txt'\n--config 'path/to/basic_config.txt' --config 'path/to/specific_superimposed_config.txt'" } 
        }
    },
    { "output",
        { 
            .name{ "--output" },
            .key{ "<string...>" },
            .short_description{ "Output Options. Comma-separated list." },
            .long_description{ "Comma-separated list of things to output. Available: mat, scalar, fft, pump, mask, psi, n. Options with _plus or _minus are also supported." },
            .short_usecase{ "--output all\n--output wavefunction,scalar,fft" },
            .long_usecase{ "--output all (outputs all matrices and scalar data)\n--output wavefunction,fft (outputs wavefunctions and scalar data for both plus and minus modes)\n--output scalar (only output scalar data, no matrices)\n--output wavefunction_plus,fft_minus (output wavefunction of plus mode and fft matrix if minus mode)" } 
        } 
    },
    { "outEvery", 
        { 
            .name{ "--outEvery" }, 
            .key{ "<float>" }, 
            .unit{ "ps" }, 
            .short_description{ "Output Modulus" }, 
            .long_description{ "Output plots and scalar data every [x] ps. Set this value to be smaller than the timestep dt to output every iteration" }, 
            .short_usecase{ "--outEvery 10.0" }, 
            .long_usecase{ "--outEvery 10.0\n--outEvery 0.001 (output every iteration)" } 
        } 
    },
    { "historyMatrix",
        { 
            .name{ "--historyMatrix" },
            .key{ "<int> <int> <int> <int> <int>" },
            .short_description{ "Output Matrices at different times with startx, endx, starty, endy, and matrix increment. Saved in 'timeoutput' subfolder" },
            .long_description{ "Outputs matrices specified in --output. Matrices are saved in the 'timeoutput' subfolder. The arguments in order include startx, endx, starty, endy, and matrix increment. The increment is used to decrease the matrix size. This feature significantly slows down the execution time due to the constant I/O, so use this carefully." },
            .short_usecase{ "--historyMatrix 0 100 0 100 1" },
            .long_usecase{ "--historyMatrix 0 100 0 100 1 (outputs a 100x100 submatrix)\n--historyMatrix 0 100 0 100 5 (outputs a 20x20 matrix from the 100x100 submatrix)\n--historyMatrix 250 350 250 350 1 (outputs a submatrix from inside the total matrix)" } 
        } 
    },
    { "historyTime",
        { 
            .name{ "--historyTime" },
            .key{ "<float> <int>" },
            .short_description{ "Output Matrices after time, freq with decreased frequency. Saved in 'timeoutput' subfolder." },
            .long_description{ "Outputs matrices specified in --output after starting time, then every multiple*outEvery times. Matrices are saved in the 'timeoutput' subfolder. The increment uses multiples of --outEvery to decrease the output frequency. The increment can NOT be used to increase the output frequency again. Use smaller values for --outEvery instead to increase the output frequency. This parameter doesn't do anything if no --historyMatrix was specified." },
            .short_usecase{ "--historyTime 1000.0 2" },
            .long_usecase{ "--historyTime 1000.0 2 (output matrices after 1000ps every 2*outEvery ps)\n--historyTime 0 1 (output matrices after right from the start every outEvery ps)" } 
        } 
    },
    { "norender", 
        { 
            .name{ "-norender" }, 
            .key{ "no arguments" }, 
            .short_description{ "Disables all live graphical output" }, 
            .long_description{ "Disables all live graphical output if passed" }, 
            .short_usecase{ "-norender" }, .long_usecase{ "-norender" } 
        } 
    },
    { "N", 
        { 
            .name{ "--gridsize, --N" }, 
            .key{ "<int> <int>" }, 
            .short_description{ "Grid Dimensions" }, 
            .long_description{ "Grid Dimensions (N x N). The grid is used for the spatial discretization of the wavefunction." }, 
            .short_usecase{ "--N 100 100" }, 
            .long_usecase{ "--N 100 100 (sets the grid to 100x100)\n--N 500 1000 (sets the grid to 500x1000)" } 
        } 
    },
    { "subgrids",
        { 
            .name{ "--subgrids, --sg" },
            .key{ "<int> <int>" },
            .short_description{ "Subgrid Dimensions" },
            .long_description{ "Subgrid Dimensions (N x N). Need to integer devide Nx,Ny. By default, the subgrids are determined automatically. The subgrids are used for the parallelization of the wavefunction. For GPUs, lower number of subgrids are advised. For CPUs, the number of subgrids should ideally match the number of cores used." },
            .short_usecase{ "--subgrids 2 2" },
            .long_usecase{ "--subgrids 2 2 (results in 2*2 = 4 subgrids)\n--subgrids 1 5 (results in 1*5 = 5 subgrids)" } 
        } 
    },
    { "tstep", 
        { 
            .name{ "--tstep, --dt" }, 
            .key{ "<double>" }, 
            .unit{ "ps" }, 
            .short_description{ "Timestep" }, 
            .long_description{ "Timestep. It's advised to leave this parameter at its magic timestep default." }, 
            .short_usecase{ "--tstep 0.1" }, 
            .long_usecase{ "--tstep 0.1 (sets the timestep to 0.1ps)" } 
        } 
    },
    { "tmax", 
        { 
            .name{ "--tmax, --tend" }, 
            .key{ "<double>" }, 
            .unit{ "ps" }, 
            .short_description{ "Timelimit" }, 
            .long_description{ " Timelimit. " }, 
            .short_usecase{ "--tmax 1000" }, 
            .long_usecase{ "--tmax 1000 (sets the simulation time to 1000ps)" } 
        } 
    },
    {
        "rkvdt",
        {
            .name{ "--rkvdt" },
            .key{ "<double> <double>" },
            .short_description{ "Minimum and maximum timestep for adaptive iterator." },
            .long_description{ "Minimum and maximum timestep for adaptive iterator." },
            .short_usecase{ "--rkvdt 0.1 1.0" },
            .long_usecase{ "--rkvdt 0.01 1.0 (sets the minimum timestep to 0.01ps and the maximum timestep to 1.0ps)" }
        }
    }, 
    {
        "tol",
        {
            .name{ "--tol" },
            .key{ "<double>" },
            .short_description{ "Tolerance for adaptive iterator." },
            .long_description{ "Tolerance for adaptive iterator." },
            .short_usecase{ "--tol 0.1" },
            .long_usecase{ "--tol 0.1 (sets the tolerance to 0.1)" }
        }
    },
    { "iterator", 
        { 
            .name{ "--iterator" }, 
            .key{ "<string>" }, 
            .short_description{ "Iterator to use." }, 
            .long_description{ "Iterator to use." }, 
            .short_usecase{ "--iterator RK4" }, 
            .long_usecase{ "--iterator RK4 (sets the iterator to RK4)\n--iterator SSFM (sets the iterator to SSFM)" } 
        } 
    },
    { "adaptiveTimeStep", 
        { 
            .name{ "-adaptive, -adaptiveTimestep" }, 
            .key{ "" }, 
            .short_description{ "Use adaptive timestepping if available." }, 
            .long_description{ "Use adaptive timestepping if available." }, 
            .short_usecase{ "-adaptive" }, 
            .long_usecase{ "-adaptive" } 
        } 
    },
    { "imagTime", 
        { 
            .name{ "--imagTime" }, 
            .key{ "<double>" }, 
            .short_description{ "Use imaginary time propagation with normalization constant" }, 
            .long_description{ "Use imaginary time propagation with normalization constant." }, 
            .short_usecase{ "--imagTime 1" }, 
            .long_usecase{ "--imagTime 1 (sets the imaginary time amplitude to 1)\n--imagTime 10 (sets the normalization constant to 10)" } 
        } 
    },
    { "boundary", 
        { 
            .name{ "--boundary" }, 
            .key{ "<string> <string>" }, 
            .short_description{ "Boundary conditions for x and y" }, 
            .long_description{ "Boundary conditions for x and y. Can be either 'periodic' or 'zero'." }, 
            .short_usecase{ "--boundary periodic zero" }, 
            .long_usecase{ "--boundary periodic periodic (sets periodic boundary conditions in x and y)\n--boundary periodic zero( sets periodic boundary conditions in x and zero boundary conditions in y ) " } 
        } 
    },
    { "tetm", 
        { 
            .name{ "-tetm" }, 
            .key{ "no arguments" }, 
            .short_description{ "Enables TE/TM splitting" }, 
            .long_description{ "Enables TE/TM splitting. This will split the wavefunction into TE and TM modes." }, 
            .short_usecase{ "-tetm" }, 
            .long_usecase{ "-tetm" } 
        } 
    },
    { "gammaC", 
        { 
            .name{ "--gammaC, --gamma_C, --gamma_c, --gammac" }, 
            .key{ "<double>" }, 
            .unit{ "ps^-1" }, 
            .short_description{ "Damping Coefficient" }, 
            .long_description{ "Damping coefficient for the wavefunction." }, 
            .short_usecase{ "--gammaC 0.1" }, 
            .long_usecase{ "--gammaC 0.1 (sets the damping coefficient to 0.1ps^-1)" } 
        } 
    },
    { "gammaR", 
        { 
            .name{ "--gammaR, --gamma_R, --gamma_r, --gammar" }, 
            .key{ "<double>" }, 
            .unit{ "ps^-1" }, 
            .short_description{ "Reservoir Damping Coefficient" }, 
            .long_description{ "Damping coefficient for the reservoir." }, 
            .short_usecase{ "--gammaR 0.1" }, 
            .long_usecase{ "--gammaR 0.1 (sets the radiative damping coefficient to 0.1 ps^-1)" } 
        } 
    },
    { "gc", 
        { 
            .name{ "--gc, --g_c" }, 
            .key{ "<double>" }, 
            .unit{ "eV mum^2" }, 
            .short_description{ "Nonlinear Coefficient" }, 
            .long_description{ "Nonlinear coefficient for the wavefunction." }, 
            .short_usecase{ "--gc 0.1" }, 
            .long_usecase{ "--gc 0.1 (sets the nonlinear coefficient to 0.1 eV mum^2)" } 
        } 
    },
    { "gr", 
        { 
            .name{ "--gr, --g_r" }, 
            .key{ "<double>" }, 
            .unit{ "eV mum^2" }, 
            .short_description{ "Reservoir Nonlinear Coefficient" }, 
            .long_description{ "Nonlinear coefficient for the reservoir." }, 
            .short_usecase{ "--gr 0.1" }, 
            .long_usecase{ "--gr 0.1 (sets the reservoir nonlinear coefficient to 0.1 eV mum^2)" } 
        } 
    },
    { "R", 
        { 
            .name{ "--R" }, 
            .key{ "<double>" }, 
            .unit{ "ps^-1 mum^2" }, 
            .short_description{ "Relaxation Rate" }, 
            .long_description{ "Relaxation rate for the wavefunction." }, 
            .short_usecase{ "--R 0.1" }, 
            .long_usecase{ "--R 0.1 (sets the relaxation rate to 0.1 ps^-1 mum^2)" } 
        } 
    },
    { "g_pm", 
        { 
            .name{ "--g_pm, --g_PM, --gpm" }, 
            .key{ "<double>" }, 
            .short_description{ "TE/TM Splitting" }, 
            .long_description{ "Nonlinear coefficient for TE/TM splitting." }, 
            .short_usecase{ "--g_pm 0.1" }, 
            .long_usecase{ "--g_pm 0.1 (sets the TE/TM splitting coefficient to 0.1)" } 
        } 
    },
    { "deltaLT", 
        { 
            .name{ "--deltaLT, --delta_LT, --deltalt, --dlt" }, 
            .key{ "<double>" }, 
            .unit{ "eV" }, 
            .short_description{ "TE/TM Splitting Energy" }, 
            .long_description{ "Energy difference for TE/TM splitting." }, 
            .short_usecase{ "--deltaLT 0.1" }, 
            .long_usecase{ "--deltaLT 0.1 (sets the TE/TM splitting energy difference to 0.1 eV)" } 
        } 
    },
    { "L", 
        { 
            .name{ "--L, --gridlength, --xmax" }, 
            .key{ "<double> <double>" }, 
            .unit{ "mum" }, 
            .short_description{ "System Size" }, 
            .long_description{ "System size in x and y direction. For a given L, the grid spans from -L/2:L/2." }, 
            .short_usecase{ "--L 1 1" }, 
            .long_usecase{ "--L 1 1 (sets the system size to 1x1 mum)" } 
        } 
    },
    { "meff", 
        { 
            .name{ "--m_eff, --meff" }, 
            .key{ "<double>" }, 
            .short_description{ "Effective Mass" }, 
            .long_description{ "Effective mass for the wavefunction." }, 
            .short_usecase{ "--meff 0.1" }, 
            .long_usecase{ "--meff 0.1 (sets the effective mass to 0.1)" } 
        } 
    },
    { "hbar_scaled", 
        { 
            .name{ "--hbar_scaled, --hbarscaled, --hbars" }, 
            .key{ "<double>" }, 
            .unit{ "" }, 
            .short_description{ "Scaled hbar" }, 
            .long_description{ "Scaled hbar value. This value is calculated automatically from the effective mass and the hbar value." }, 
            .short_usecase{ "--hbar_scaled 0.1" }, 
            .long_usecase{ "--hbar_scaled 0.1 (sets the scaled hbar value to 0.1)" } 
        } 
    },
    { "hbar", 
        { 
            .name{ "--hbar" }, 
            .key{ "<double>" }, 
            .unit{ "" }, 
            .short_description{ "SI hbar" }, 
            .long_description{ "SI hbar value." }, 
            .short_usecase{ "--hbar 1" }, 
            .long_usecase{ "--hbar 1 (sets the SI hbar value to 1)" } 
        } 
    },
    { "m_e", 
        { 
            .name{ "--m_e, --me, --electron_mass" }, 
            .key{ "<double>" }, 
            .unit{ "" }, 
            .short_description{ "Electron mass" }, 
            .long_description{ "Electron mass value." }, 
            .short_usecase{ "--m_e 1" }, 
            .long_usecase{ "--m_e 1 (sets the electron mass to 1)" } 
        } 
    },
    { "e", 
        { 
            .name{ "--e, --electron_charge" }, 
            .key{ "<double>" }, 
            .unit{ "" }, 
            .short_description{ "Electron charge" }, 
            .long_description{ "Electron charge value." }, 
            .short_usecase{ "--e 1" }, 
            .long_usecase{ "--e 1 (sets the electron charge to 1)" } 
        } 
    },
    { "envelope",
        { 
            .name{ "--[envelope]" },
            .key{ "<double> <string> <double> <double> <double> <double> <string> <double> <double> <string>" },
            .short_description{ "Time INdependent Envelope Syntax. Envelopes can be --pump, --pulse, --fftMask, --initialWavefunction, --initialReservoir, --potential. Keys are amplitude, behaviour (add, multiply, replace, adaptive, complex), widthX, widthY, posX, posY, pol (plus, minus, both), exponent, charge, type (gauss, ring)" },
            .long_description{ "Time INdependent Envelope Syntax. This is the general syntax for any of the available envelopes, which includes: --pump, --pulse, --fftMask, --initialWavefunction, --initialReservoir, --potential. Each Envelope is defined by a set of spatial parameters:\namplitude: numerical value\nbehaviour: Method to apply this envelope to its group. Envelopes that have the same temporal properties (see later) are grouped together and are superimposed upon running PHOENIX. The "
                            "methods here include:\n- add - Adds the envelope to its group\n- multiply - Multiplies the current group matrix with this envelope\n- replace - Replaces "
                            "the current group matrix with this envelope\n- adaptive - Sets the amplitude of each cell to the current value of the group matrix. This is usefull to e.g.cut out parts of the matrix.\n- complex - Multiply this envelope with i\nwidthX: With in X direction\nwidthY: Width in Y direction\nposX: Position in X direction\nposY: Position in Y direction\npol: Polarization of this envelope. This value can be either 'plus', 'minus' or 'both', applying to the plus or minus "
                            "component, respectively.\nexponent: Gaussian exponent. Larger values result in steeper Gaussians.\ncharge: Topological Charge of this envelope. This value results in a complex phase winding and should only be used for complex envelopes. Can be either int or 'none'\ntype: Type of this envelope. Can be a superposition of the following:\n- gauss: Gaussian envelope\n- ring: Ring envelope\n- noDivide: No renormalization using the width. This prohibits the division of the "
                            "amplitude by its width.\n- local: Use local space (-1:1) instead of (-L/2:L/2). Convinient for e.g. FFT filter envelopes." },
            .short_usecase{ "--[envelope] 15 add 10 10 0 0 both 1 none gauss+noDivide" },
            .long_usecase{ "--[envelope] 15 add 10 10 0 0 both 1 none gauss+noDivide (basic Gaussian envelope)\n--[envelope] 15 add 20 10 50 0 both 3 none ring+noDivide (steeper ring envelope, asymmetrical, shifted to x,y = 50,0)\n--[envelope] 1 add 0.3 0.3 0 0 plus 1 none local+noDivide (local mapped envelope from -1:1 instead of -L/2:L/2, plus component only)" } 
        } 
    },
    { "envelope_time",
        {
             .name{ "--[envelope]" },
            .key{ "<double> <string> <double> <double> <double> <double> <string> <double> <double> <string> time <double> <double> <double>" },
            .short_description{ "Time Dependent Envelope Syntax. Additional keys are t0, sigma, freq." },
            .long_description{ "Time Dependent Envelope Syntax. The spatial parameters are equivalent to the previous envelope and temporal parameters are indicated with the additional 'time' keyword. The available keys include:\nkind: Type of oscillator. Can be either of iexp ~exp(iwt/sigma), cos ~ cos(wt/sigma) or gauss ~ exp(-t/sigma)^w. In the latter, frequency becomes the power of the function instead.\nt0: Center time.\nfreq: Frequency (w) of the oscillator or power of the function." },
            .short_usecase{ "--[envelope] 15 add 10 10 0 0 both 1 none gauss+noDivide time iexp 200 50 0.1" },
            .long_usecase{ "--[envelope] 15 add 10 10 0 0 both 1 none gauss+noDivide time iexp 200 50 0 (Example from before, with complex oscillator, centered at 200ps with width 50ps and f=0 for no oscillator component.\n--[envelope] 15 add 10 10 0 0 both 1 3 gauss+noDivide time iexp 0 1e5 0.1 (Envelope with topological charge = 3, no center with t0 = 0, high sigma for constant temporal envelope, and frequency f=0.1THz. This envelope will be constant of amplitude and oscillate with a given "
                        "frequency)" } 
        } 
    },
    { "envelope_loaded",
        { 
            .name{ "--[envelope]" },
            .key{ "load <string> <double> <string> <string> time load <string>" },
            .short_description{ "Loaded Envelope Syntax. Space and Time can be loaded." },
            .long_description{ "Loaded Envelope Syntax. Both the spatial as well as the temporal components can be loaded from files, indicated by replacing the respective set of parameters with 'load ...'. Loading a spatial matrix requires a matrix input, loading temporal input requires a t:value pair per line in the file. The final temporal envelope is then linearly interpolated from the input points. The remaining parameters are:\nSpatial "
                            "Component:\npath: Path to the spatial envelope.\namp: Scaling amplitude. The loaded envelope will be multiplied by this value.\nBehaviour: Same as before.\npol: Polarization. Same as before.\nTemporal Components:\npath: Parth to the spatial envelope." },
            .short_usecase{ "--[envelope] load 'path/to/spatial/envelope' 1 add both load 'path/to/temporal/envelope'" },
            .long_usecase{ "--[envelope] load 'path/to/spatial/envelope' 1 add both load 'path/to/temporal/envelope' (loads a spatial and temporal envelope from the given paths)" } 
        } 
    },
};
// clang-format on

void PHOENIX::SystemParameters::printHelp( bool verbose, bool markdown ) {
    print_name();
    const size_t L1 = std::min<size_t>( 0.3 * console_width - 1, 50 );
    const size_t L2 = std::min<size_t>( 0.3 * console_width - 1, 50 );
    const size_t L3 = console_width - 15 - L2 - L1;

    std::cout << PHOENIX::CLIO::fillLine( console_width, major_seperator ) << "\n"; // Horizontal Separator

#ifndef USE_32_BIT_PRECISION
    std::cout << "This program is compiled with " << EscapeSequence::UNDERLINE << EscapeSequence::YELLOW << "double precision" << EscapeSequence::RESET << " numbers.\n";
#else
    std::cout << "This program is compiled with " << EscapeSequence::UNDERLINE << EscapeSequence::YELLOW << "single precision" << EscapeSequence::RESET << " numbers.\n";
#endif

#ifdef USE_CPU
    std::cout << "This program is compiled as a " << EscapeSequence::UNDERLINE << EscapeSequence::YELLOW << "CPU Version" << EscapeSequence::RESET << ".\n";
    std::cout << "Maximum number of CPU cores utilized: " << omp_get_max_threads() << std::endl;
#endif

    std::cout << EscapeSequence::BOLD << PHOENIX::CLIO::fillLine( console_width, major_seperator ) << EscapeSequence::RESET << std::endl;
    std::cout << PHOENIX::CLIO::unifyLength( "Option", "Inputs", "Description\n", L1, L2, L3 ) << std::endl;
    std::cout << EscapeSequence::BOLD << PHOENIX::CLIO::fillLine( console_width, minor_seperator ) << EscapeSequence::RESET << std::endl;

    // Program Options
    arguments.at( "path" ).print_usecase( filehandler.outputPath, verbose, markdown );
    std::cout << PHOENIX::CLIO::fillLine( console_width, seperator ) << std::endl;
    arguments.at( "config" ).print_usecase( "", verbose, markdown );
    std::cout << PHOENIX::CLIO::fillLine( console_width, seperator ) << std::endl;
    arguments.at( "outEvery" ).print_usecase( output_every, verbose, markdown );
    std::cout << PHOENIX::CLIO::fillLine( console_width, minor_seperator ) << std::endl;
    arguments.at( "output" ).print_usecase( "", verbose, markdown );
    std::cout << PHOENIX::CLIO::fillLine( console_width, seperator ) << std::endl;
    arguments.at( "historyMatrix" ).print_usecase( "", verbose, markdown );
    std::cout << PHOENIX::CLIO::fillLine( console_width, seperator ) << std::endl;
    arguments.at( "historyTime" ).print_usecase( "", verbose, markdown );
    std::cout << PHOENIX::CLIO::fillLine( console_width, minor_seperator ) << std::endl;
    std::cout << PHOENIX::CLIO::unifyLength( "Numerical parameters", "", "", L1, L2, L3 ) << std::endl;
    arguments.at( "N" ).print_usecase( std::to_string( p.N_c ) + " " + std::to_string( p.N_r ), verbose, markdown );
    std::cout << PHOENIX::CLIO::fillLine( console_width, seperator ) << std::endl;
    arguments.at( "subgrids" ).print_usecase( std::to_string( p.subgrids_columns ) + " " + std::to_string( p.subgrids_rows ), verbose, markdown );
    std::cout << PHOENIX::CLIO::fillLine( console_width, seperator ) << std::endl;
    arguments.at( "tstep" ).print_usecase( magic_timestep, verbose, markdown );
    std::cout << PHOENIX::CLIO::fillLine( console_width, seperator ) << std::endl;
    arguments.at( "tmax" ).print_usecase( t_max, verbose, markdown );
    std::cout << PHOENIX::CLIO::fillLine( console_width, seperator ) << std::endl;
    arguments.at( "rkvdt" ).print_usecase( std::to_string( dt_min ) + ":" + std::to_string( dt_max ), verbose, markdown );
    std::cout << PHOENIX::CLIO::fillLine( console_width, seperator ) << std::endl;
    arguments.at( "tol" ).print_usecase( tolerance, verbose, markdown );
    std::cout << PHOENIX::CLIO::fillLine( console_width, seperator ) << std::endl;
    arguments.at( "iterator" ).print_usecase( iterator, verbose, markdown );
    std::cout << PHOENIX::CLIO::unifyLength( "", "", "Available:", L1, L2, L3 ) << std::endl;
    auto available_iterators = SolverFactory::available_solvers();
    for ( auto& [key, info] : available_iterators ) {
        std::cout << PHOENIX::CLIO::unifyLength( "", "", key + ": " + std::string( info.description ) + ( !info.is_adaptive ? ( " (" + EscapeSequence::YELLOW + "fixed" + EscapeSequence::RESET + ")" ) : ( " (" + EscapeSequence::ORANGE + "adaptive" + EscapeSequence::RESET +")" ) ), L1, L2, L3 ) << std::endl;
    }
    arguments.at( "adaptiveTimeStep" ).print_usecase( use_adaptive_timestep, verbose, markdown );
    std::cout << PHOENIX::CLIO::fillLine( console_width, seperator ) << std::endl;
    arguments.at( "imagTime" ).print_usecase( imag_time_amplitude, verbose, markdown );
    std::cout << PHOENIX::CLIO::fillLine( console_width, seperator ) << std::endl;
    arguments.at( "boundary" ).print_usecase( std::string( "x: " ) + ( p.periodic_boundary_x ? "periodic" : "zero" ) + " y: " + ( p.periodic_boundary_y ? "periodic" : "zero" ), verbose, markdown );
    std::cout << PHOENIX::CLIO::fillLine( console_width, minor_seperator ) << std::endl;

    std::cout << PHOENIX::CLIO::unifyLength( "System Parameters", "", "", L1, L2, L3 ) << std::endl;
    arguments.at( "gammaC" ).print_usecase( p.gamma_c, verbose, markdown );
    std::cout << PHOENIX::CLIO::fillLine( console_width, seperator ) << std::endl;
    arguments.at( "gammaR" ).print_usecase( p.gamma_r, verbose, markdown );
    std::cout << PHOENIX::CLIO::fillLine( console_width, seperator ) << std::endl;
    arguments.at( "gc" ).print_usecase( p.g_c, verbose, markdown );
    std::cout << PHOENIX::CLIO::fillLine( console_width, seperator ) << std::endl;
    arguments.at( "gr" ).print_usecase( p.g_r, verbose, markdown );
    std::cout << PHOENIX::CLIO::fillLine( console_width, seperator ) << std::endl;
    arguments.at( "R" ).print_usecase( p.R, verbose, markdown );
    std::cout << PHOENIX::CLIO::fillLine( console_width, seperator ) << std::endl;
    arguments.at( "tetm" ).print_usecase( "", verbose, markdown );
    std::cout << PHOENIX::CLIO::fillLine( console_width, seperator ) << std::endl;
    arguments.at( "g_pm" ).print_usecase( p.g_pm, verbose, markdown );
    std::cout << PHOENIX::CLIO::fillLine( console_width, seperator ) << std::endl;
    arguments.at( "deltaLT" ).print_usecase( p.delta_LT, verbose, markdown );
    std::cout << PHOENIX::CLIO::fillLine( console_width, seperator ) << std::endl;
    arguments.at( "L" ).print_usecase( "x: " + std::to_string( p.L_x ) + " y: " + std::to_string( p.L_y ), verbose, markdown );
    std::cout << PHOENIX::CLIO::fillLine( console_width, minor_seperator ) << std::endl;
    std::cout << PHOENIX::CLIO::unifyLength( "SI Scalings", "", "", L1, L2, L3 ) << std::endl;
    arguments.at( "hbar" ).print_usecase( p.h_bar, verbose, markdown );
    std::cout << PHOENIX::CLIO::fillLine( console_width, seperator ) << std::endl;
    arguments.at( "m_e" ).print_usecase( p.m_e, verbose, markdown );
    std::cout << PHOENIX::CLIO::fillLine( console_width, seperator ) << std::endl;
    arguments.at( "e" ).print_usecase( p.e_e, verbose, markdown );
    std::cout << PHOENIX::CLIO::unifyLength( "Alternative Scaled Values", "", "", L1, L2, L3 ) << std::endl;
    arguments.at( "meff" ).print_usecase( p.m_eff, verbose, markdown );
    std::cout << PHOENIX::CLIO::fillLine( console_width, seperator ) << std::endl;
    arguments.at( "hbar_scaled" ).print_usecase( p.h_bar_s, verbose, markdown );
    std::cout << PHOENIX::CLIO::fillLine( console_width, minor_seperator ) << std::endl;

    std::cout << PHOENIX::CLIO::unifyLength( "Envelopes", "", "", L1, L2, L3 ) << std::endl;
    //std::cout << PHOENIX::CLIO::unifyLength( "Syntax for spatial and temporal envelopes or loading external files:", "", "" ) << std::endl;
    arguments.at( "envelope" ).print_usecase( "", verbose, markdown );
    std::cout << PHOENIX::CLIO::fillLine( console_width, minor_seperator ) << std::endl;
    arguments.at( "envelope_time" ).print_usecase( "", verbose, markdown );
    std::cout << PHOENIX::CLIO::fillLine( console_width, minor_seperator ) << std::endl;
    arguments.at( "envelope_loaded" ).print_usecase( "", verbose, markdown );
    std::cout << PHOENIX::CLIO::fillLine( console_width, minor_seperator ) << std::endl;

    std::cout << PHOENIX::CLIO::unifyLength( "Possible Envelopes include", "", "", L1, L2, L3 ) << std::endl;
    std::cout << PHOENIX::CLIO::unifyLength( "--pump", "Spatial and Temporal ~cos(wt)", "", L1, L2, L3 ) << std::endl;
    std::cout << PHOENIX::CLIO::unifyLength( "--potential", "Spatial and Temporal ~cos(wt)", "", L1, L2, L3 ) << std::endl;
    std::cout << PHOENIX::CLIO::unifyLength( "--initialState", "Spatial", "", L1, L2, L3 ) << std::endl;
    std::cout << PHOENIX::CLIO::unifyLength( "--initialReservoir", "Spatial", "", L1, L2, L3 ) << std::endl;
    std::cout << PHOENIX::CLIO::unifyLength( "--pulse", "Spatial and Temporal ~exp(iwt)", "", L1, L2, L3 ) << std::endl;
    std::cout << PHOENIX::CLIO::unifyLength( "--fftMask", "Spatial", "", L1, L2, L3 ) << std::endl;

    // Additional Parameters
    std::cout << "Additional Parameters:" << std::endl;
    std::cout << PHOENIX::CLIO::unifyLength( "--fftEvery", "<int>", "Apply FFT Filter every x ps", L1, L2, L3 ) << std::endl;
    std::cout << PHOENIX::CLIO::unifyLength( "--initRandom", "<double>", "Amplitude. Randomly initialize Psi", L1, L2, L3 ) << std::endl;

#ifdef USE_CPU
    std::cout << PHOENIX::CLIO::unifyLength( "--threads", "<int>", "Default is " + std::to_string( omp_max_threads ) + " Threads", L1, L2, L3 ) << std::endl;
#endif

    std::cout << PHOENIX::CLIO::fillLine( console_width, major_seperator ) << std::endl;
}

void PHOENIX::SystemParameters::printSummary( std::map<std::string, std::vector<double>> timeit_times, std::map<std::string, double> timeit_times_total ) {
    print_name();
    const int l = 35;

    // Print Header
    std::cout << EscapeSequence::BOLD << PHOENIX::CLIO::fillLine( console_width, major_seperator ) << EscapeSequence::RESET << std::endl;
    std::cout << EscapeSequence::BOLD << PHOENIX::CLIO::centerString( " Parameters ", console_width, '-' ) << EscapeSequence::RESET << std::endl;

    // Grid Configuration
    std::cout << PHOENIX::CLIO::unifyLength( "Grid Configuration", "---", "---", l, l, l, " " ) << std::endl;
    std::cout << PHOENIX::CLIO::unifyLength( "N", std::to_string( p.N_c ) + ", " + std::to_string( p.N_r ), "", l, l, l, " " ) << std::endl;
    std::cout << PHOENIX::CLIO::unifyLength( "N^2", std::to_string( p.N_c * p.N_r ), "", l, l, l, " " ) << std::endl;
    std::cout << PHOENIX::CLIO::unifyLength( "Subgrids", std::to_string( p.subgrids_columns ) + ", " + std::to_string( p.subgrids_rows ), "", l, l, l, " " ) << std::endl;
    std::cout << PHOENIX::CLIO::unifyLength( "Total Subgrids", std::to_string( p.subgrids_columns * p.subgrids_rows ), "", l, l, l, " " ) << std::endl;

    // Subgrid Overhead
    const double subgrid_overhead = ( ( p.subgrid_N_r + 2.0 * p.halo_size ) * ( p.subgrid_N_c + 2 * p.halo_size ) * ( p.subgrids_columns * p.subgrids_rows ) / ( p.N_r * p.N_c ) - 1.0 ) * 100.0;
    std::cout << PHOENIX::CLIO::unifyLength( "Subgrid Overhead", std::to_string( subgrid_overhead ), "%", l, l, l, " " ) << std::endl;

    // Grid Dimensions
    std::cout << PHOENIX::CLIO::unifyLength( "Lx", PHOENIX::CLIO::to_str( p.L_x ), "mum", l, l, l, " " ) << std::endl;
    std::cout << PHOENIX::CLIO::unifyLength( "Ly", PHOENIX::CLIO::to_str( p.L_y ), "mum", l, l, l, " " ) << std::endl;
    std::cout << PHOENIX::CLIO::unifyLength( "dx", PHOENIX::CLIO::to_str( p.dx ), "mum", l, l, l, " " ) << std::endl;
    std::cout << PHOENIX::CLIO::unifyLength( "dy", PHOENIX::CLIO::to_str( p.dx ), "mum", l, l, l, " " ) << std::endl;

    // System Configuration
    std::cout << PHOENIX::CLIO::unifyLength( "System Configuration", "---", "---", l, l, l, " " ) << std::endl;
    std::cout << PHOENIX::CLIO::unifyLength( "tmax", PHOENIX::CLIO::to_str( t_max ), "ps", l, l, l, " " ) << std::endl;
    std::cout << PHOENIX::CLIO::unifyLength( "dt", PHOENIX::CLIO::to_str( p.dt ), "ps", l, l, l, " " ) << std::endl;
    std::cout << PHOENIX::CLIO::unifyLength( "gamma_c", PHOENIX::CLIO::to_str( p.gamma_c ), "ps^-1", l, l, l, " " ) << std::endl;
    std::cout << PHOENIX::CLIO::unifyLength( "gamma_r", PHOENIX::CLIO::to_str( p.gamma_r ), "ps^-1", l, l, l, " " ) << std::endl;
    std::cout << PHOENIX::CLIO::unifyLength( "g_c", PHOENIX::CLIO::to_str( p.g_c ), "eV mum^2", l, l, l, " " ) << std::endl;
    std::cout << PHOENIX::CLIO::unifyLength( "g_r", PHOENIX::CLIO::to_str( p.g_r ), "eV mum^2", l, l, l, " " ) << std::endl;
    std::cout << PHOENIX::CLIO::unifyLength( "g_pm", PHOENIX::CLIO::to_str( p.g_pm ), "eV mum^2", l, l, l, " " ) << std::endl;
    std::cout << PHOENIX::CLIO::unifyLength( "R", PHOENIX::CLIO::to_str( p.R ), "ps^-1 mum^-2", l, l, l, " " ) << std::endl;
    std::cout << PHOENIX::CLIO::unifyLength( "delta_LT", PHOENIX::CLIO::to_str( p.delta_LT ), "eV", l, l, l, " " ) << std::endl;
    std::cout << PHOENIX::CLIO::unifyLength( "m_eff", PHOENIX::CLIO::to_str( p.m_eff ), "", l, l, l, " " ) << std::endl;
    std::cout << PHOENIX::CLIO::unifyLength( "h_bar_s", PHOENIX::CLIO::to_str( p.h_bar_s ), "", l, l, l, " " ) << std::endl;

    // Boundary Conditions
    std::cout << "Boundary Condition: " << ( p.periodic_boundary_x ? "Periodic" : "Zero" ) << "(x):" << ( p.periodic_boundary_y ? "Periodic" : "Zero" ) << "(y)" << std::endl;

    // Envelopes
    std::cout << PHOENIX::CLIO::centerString( " Envelope Functions ", console_width, '-' ) << std::endl;
    if ( pulse.size() > 0 )
        std::cout << "Pulse Envelopes:\n" << pulse.toString();
    if ( pump.size() > 0 )
        std::cout << "Pump Envelopes:\n" << pump.toString();
    if ( potential.size() > 0 )
        std::cout << "Potential Envelopes:\n" << potential.toString();
    if ( fft_mask.size() > 0 )
        std::cout << "FFT Mask Envelopes:\n" << fft_mask.toString();
    if ( initial_state.size() > 0 )
        std::cout << "Initial State Envelopes:\n" << initial_state.toString();

    // Runtime Statistics
    std::cout << EscapeSequence::BOLD << PHOENIX::CLIO::centerString( " Runtime Statistics ", console_width, '-' ) << EscapeSequence::RESET << std::endl;
    double total = PHOENIX::TimeIt::totalRuntime();
    std::cout << "Total Runtime: " << total << " s --> " << ( total / p.t * 1E3 ) << " ms/ps --> " << ( p.t / total ) << " ps/s --> " << ( total / iteration ) * 1e6 << " mus/it" << std::endl;

    // Additional Information
    std::cout << EscapeSequence::BOLD << PHOENIX::CLIO::centerString( " Infos ", console_width, '-' ) << EscapeSequence::RESET << std::endl;
    auto available_iterators = SolverFactory::available_solvers();
    std::cout << "Calculations done using the '" << iterator << " - " << available_iterators.at( iterator ).description << "' solver" << std::endl;
    if ( use_adaptive_timestep ) {
        std::cout << " = Tolerance used: " << tolerance << std::endl;
        std::cout << " = dt_max used: " << dt_max << std::endl;
        std::cout << " = dt_min used: " << dt_min << std::endl;
    } else {
        std::cout << " = Fixed timestep used: " << p.dt << std::endl;
    }

    std::cout << "Calculated until t = " << p.t << "ps" << std::endl;
    if ( fft_mask.size() > 0 )
        std::cout << "Applying FFT every " << fft_every << " ps" << std::endl;
    std::cout << "Output variables and plots every " << output_every << " ps" << std::endl;
    std::cout << "Total allocated space for Device Matrices: " << CUDAMatrixBase::global_total_device_mb_max << " MB." << std::endl;
    std::cout << "Total allocated space for Host Matrices: " << CUDAMatrixBase::global_total_host_mb_max << " MB." << std::endl;
    std::cout << "Random Seed: " << random_seed << std::endl;

    // Precision and Device Info
#ifdef USE_32_BIT_PRECISION
    std::cout << "This program is compiled using " << EscapeSequence::UNDERLINE << EscapeSequence::BLUE << "single precision" << EscapeSequence::RESET << " numbers.\n";
#else
    std::cout << "This program is compiled using " << EscapeSequence::UNDERLINE << EscapeSequence::BLUE << "double precision" << EscapeSequence::RESET << " numbers.\n";
#endif

#ifdef USE_CPU
    std::cout << "Device Used: " << EscapeSequence::BOLD << EscapeSequence::YELLOW << "CPU" << EscapeSequence::RESET << std::endl;
    std::cout << EscapeSequence::GRAY << "  CPU cores utilized: " << omp_max_threads << EscapeSequence::RESET << std::endl;
#else
    int nDevices;
    cudaGetDeviceCount( &nDevices );
    int device;
    cudaGetDevice( &device );
    cudaDeviceProp prop;
    cudaGetDeviceProperties( &prop, device );

    std::cout << "Device Used: " << EscapeSequence::GREEN << EscapeSequence::BOLD << prop.name << EscapeSequence::RESET << std::endl;
    std::cout << "  Peak Memory Bandwidth (GB/s): " << 2.0 * prop.memoryClockRate * ( prop.memoryBusWidth / 8 ) / 1.0e6 << std::endl;
    std::cout << "  Total Global Memory (GB): " << (float)( prop.totalGlobalMem ) / 1024.0 / 1024.0 / 1024.0 << std::endl;
    std::cout << "  Total L2 Memory (MB): " << (float)( prop.l2CacheSize ) / 1024.0 / 1024.0 << std::endl;
#endif

    // Footer
    std::cout << EscapeSequence::BOLD << PHOENIX::CLIO::fillLine( console_width, '=' ) << EscapeSequence::RESET << std::endl;
}

double _PHOENIX_last_output_time = 0.;

void PHOENIX::SystemParameters::printCMD( double complete_duration, double complete_iterations ) {
    // TODO: non-cmd mode where progress is output in an easily parseable format

    // Limit output frequency to once every 0.25 seconds
    if ( std::time( nullptr ) - _PHOENIX_last_output_time < 0.25 ) {
        return;
    }

    // Hide the cursor during output
    std::cout << EscapeSequence::HIDE_CURSOR;
    std::cout << PHOENIX::CLIO::fillLine( console_width, major_seperator ) << std::endl;

    // Print current simulation time and timestep
    std::cout << "    T = " << int( p.t ) << "ps - dt = " << std::setprecision( 2 ) << p.dt << "ps\n";

    // Display progress bar for p.t/t_max
    std::cout << "    Progress: " << PHOENIX::CLIO::createProgressBar( p.t, t_max, console_width - 30 ) << "\n";

    // Determine if the system uses stochastic evaluation
    bool evaluate_stochastic = evaluateStochastic();
    std::cout << "    Current System: " << ( use_twin_mode ? "TE/TM" : "Scalar" ) << " - " << ( evaluate_stochastic ? "With Stochastic" : "No Stochastic" ) << "\n";

    // Display runtime and estimated time remaining
    std::cout << "    Runtime: " << int( complete_duration ) << "s, remaining: " << int( complete_duration * ( t_max - p.t ) / p.t ) << "s\n";

    // Display time metrics
    std::cout << "    Time per ps: " << complete_duration / p.t << "s/ps-  " << std::setprecision( 3 ) << p.t / complete_duration << "ps/s-  " << complete_iterations / complete_duration << "it/s\n";

    // Print bottom separator line
    std::cout << PHOENIX::CLIO::fillLine( console_width, major_seperator ) << std::endl;

    // Move cursor up to overwrite the previous output
    std::cout << EscapeSequence::LINE_UP << EscapeSequence::LINE_UP << EscapeSequence::LINE_UP << EscapeSequence::LINE_UP << EscapeSequence::LINE_UP << EscapeSequence::LINE_UP << EscapeSequence::LINE_UP;

    // Update the last output time
    _PHOENIX_last_output_time = std::time( nullptr );
}

void PHOENIX::SystemParameters::finishCMD() {
    std::cout << "\n\n\n\n\n\n\n" << EscapeSequence::SHOW_CURSOR;
}
