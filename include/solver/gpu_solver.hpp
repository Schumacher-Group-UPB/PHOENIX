#pragma once

#include <iostream>
#include <map>
#include <functional>
#include "cuda/typedef.cuh"
#include "cuda/cuda_matrix.cuh"
#include "cuda/cuda_macro.cuh"
#include "kernel/kernel_fft.cuh"
#include "system/system_parameters.hpp"
#include "system/filehandler.hpp"
#include "solver/matrix_container.cuh"
#include "solver/iterator_config.hpp"
#include "misc/escape_sequences.hpp"

namespace PHOENIX {

/** 
 * @brief GPU Solver class providing the interface for the GPU solver.
 * Implements RK4, RK45, FFT calculations.
 *
 */
class Solver {
   public:
    // References to system and filehandler so we dont need to pass them around all the time
    PHOENIX::SystemParameters& system;
    PHOENIX::FileHandler& filehandler;

    struct TemporalEvelope {
        Type::device_vector<Type::complex> amp;
        Type::device_vector<Type::complex> amp_next;

        struct Pointers {
            Type::complex* amp;
            Type::complex* amp_next;
            Type::uint32 n;
        };

        Pointers pointers() {
            return Pointers{ GET_RAW_PTR( amp ), GET_RAW_PTR( amp_next ), Type::uint32( amp.size() ) };
        }
    } dev_pulse_oscillation, dev_pump_oscillation, dev_potential_oscillation;

    // Host/Device Matrices
    MatrixContainer matrix;

    struct InputOutput {
        Type::complex* PHOENIX_RESTRICT in_wf_plus = nullptr;
        Type::complex* PHOENIX_RESTRICT in_wf_minus = nullptr;
#ifdef BENCH
        Type::complex* PHOENIX_RESTRICT in_wf_plus_i = nullptr;
        Type::complex* PHOENIX_RESTRICT in_wf_minus_i = nullptr;
#endif
        Type::complex* PHOENIX_RESTRICT in_rv_plus = nullptr;
        Type::complex* PHOENIX_RESTRICT in_rv_minus = nullptr;
        Type::complex* PHOENIX_RESTRICT out_wf_plus = nullptr;
        Type::complex* PHOENIX_RESTRICT out_wf_minus = nullptr;
        Type::complex* PHOENIX_RESTRICT out_rv_plus = nullptr;
        Type::complex* PHOENIX_RESTRICT out_rv_minus = nullptr;
    };

    Type::device_vector<Type::real> time; // [0] is t, [1] is dt

    // The parameters are all pointers so that the cuda compute graph uses the updated values
    struct KernelArguments {
        TemporalEvelope::Pointers pulse_pointers;     // The pointers to the envelopes. These are obtained by calling the .pointers() method on the envelopes.
        TemporalEvelope::Pointers pump_pointers;      // The pointers to the envelopes. These are obtained by calling the .pointers() method on the envelopes.
        TemporalEvelope::Pointers potential_pointers; // The pointers to the envelopes. These are obtained by calling the .pointers() method on the envelopes.
        Type::real* time;                             // Pointer to Device Memory of the time array. [0] is t, [1] is dt
        MatrixContainer::Pointers dev_ptrs;           // All the pointers to the matrices. These are obtained by calling the .pointers() method on the matrices.
        SystemParameters::KernelParameters p;         // The kernel parameters. These are obtained by copying the kernel_parameters object of the system.
    };

    // Fixed Kernel Arguments. Every Compute Kernel will take one of these.
    KernelArguments generateKernelArguments( const Type::uint32 subgrid = 0 ) {
        auto kernel_arguments = KernelArguments();
        kernel_arguments.pulse_pointers = dev_pulse_oscillation.pointers();
        kernel_arguments.pump_pointers = dev_pump_oscillation.pointers();
        kernel_arguments.potential_pointers = dev_potential_oscillation.pointers();
        kernel_arguments.dev_ptrs = matrix.pointers( subgrid );
        kernel_arguments.p = system.kernel_parameters;
        kernel_arguments.time = GET_RAW_PTR( time );
        return kernel_arguments;
    }

    // Cache Maps
    std::map<std::string, std::vector<Type::real>> cache_map_scalar;

    Solver( PHOENIX::SystemParameters& system ) : system( system ), filehandler( system.filehandler ) {
        std::cout << PHOENIX::CLIO::prettyPrint( "Creating Solver...", PHOENIX::CLIO::Control::Info ) << std::endl;
        // Initialize all matrices
        initializeMatricesFromSystem();
        // Then output all matrices to file. If --output was not passed in argv, this method outputs everything.
#ifndef BENCH
        outputInitialMatrices();
#endif
    }

    void initializeMatricesFromSystem(); // Evaluates the envelopes and initializes the matrices
    void initializeHaloMap();            // Initializes the halo map

    // Output (Final) Host Matrices to files
    void outputMatrices( const Type::uint32 start_x, const Type::uint32 end_x, const Type::uint32 start_y, const Type::uint32 end_y, const Type::uint32 increment, const std::string& suffix = "", const std::string& prefix = "" );
    // Output Initial Host Matrices to files
    void outputInitialMatrices();

    // Output the history and max caches to files. should be called from finalize()
    void cacheToFiles();

    void updateKernelTime();

    void finalize();

    void iterateNewton();
    void iterateFixedTimestepHouwenWray();
    void iterateFixedTimestepExplicitMidpoint();
    void iterateFixedTimestepBogacki();
    void iterateFixedTimestepHeun();
    void iterateFixedTimestepHeun3();
    void iterateFixedTimestepRalston();
    void iterateFixedTimestepRalston3();
    void iterateFixedTimestepRalston4();
    void iterateFixedTimestepSSPRK3();
    void iterateFixedTimestepRungeKutta3();
    void iterateFixedTimestepRungeKutta4();
    void iterateFixedTimestepRule38();
    void iterateFixedTimestepNystroem();
    void iterateFixedTimestepCashKarp();
    void iterateFixedTimestepFehlberg2();
    void iterateFixedTimestepFehlberg5();
    void iterateFixedTimestepDOP5();
    void iterateFixedTimestepDOP853();
    void iterateFixedTimestepNSRK78();

    void iterateVariableTimestepFehlberg2();
    void iteratevariableTimestepFehlberg5();
    void iterateVariableTimestepDOP853();
    void iterateVariableTimestepNSRK78();
    void iterateVariableTimestepDOP45();
    void iterateVariableTimestepRungeKutta();
    void iterateSplitStepFourier();
    void normalizeImaginaryTimePropagation();

    struct iteratorFunction {
        uint32_t k_max;
        std::function<void()> iterate;
    };
    std::map<std::string, iteratorFunction> iterator = {
        {
            "Newton",
            { Iterator::available.at( "Newton" ).halo_size, std::bind( &Solver::iterateNewton, this ) },
        },
        {
            "MP",
            { Iterator::available.at( "MP" ).halo_size, std::bind( &Solver::iterateFixedTimestepExplicitMidpoint, this ) },
        },
        {
            "Heun",
            { Iterator::available.at( "Heun" ).halo_size, std::bind( &Solver::iterateFixedTimestepHeun, this ) },
        },
        {
            "Heun3",
            { Iterator::available.at( "Heun3" ).halo_size, std::bind( &Solver::iterateFixedTimestepHeun3, this ) },
        },
        {
            "Ralston",
            { Iterator::available.at( "Ralston" ).halo_size, std::bind( &Solver::iterateFixedTimestepRalston, this ) },
        },
        {
            "Ralston3",
            { Iterator::available.at( "Ralston3" ).halo_size, std::bind( &Solver::iterateFixedTimestepRalston3, this ) },
        },
        {
            "Ralston4",
            { Iterator::available.at( "Ralston4" ).halo_size, std::bind( &Solver::iterateFixedTimestepRalston4, this ) },
        },
        {
            "VHW",
            { Iterator::available.at( "VHW" ).halo_size, std::bind( &Solver::iterateFixedTimestepHouwenWray, this ) },
        },
        {
            "SSPRK3",
            { Iterator::available.at( "SSPRK3" ).halo_size, std::bind( &Solver::iterateFixedTimestepSSPRK3, this ) },
        },
        {
            "RK3",
            { Iterator::available.at( "RK3" ).halo_size, std::bind( &Solver::iterateFixedTimestepRungeKutta3, this ) },
        },
        {
            "RK4",
            { Iterator::available.at( "RK4" ).halo_size, std::bind( &Solver::iterateFixedTimestepRungeKutta4, this ) },
        },
        {
            "rule38",
            { Iterator::available.at( "rule38" ).halo_size, std::bind( &Solver::iterateFixedTimestepRule38, this ) },
        },
        {
            "Nystroem",
            { Iterator::available.at( "Nystroem" ).halo_size, std::bind( &Solver::iterateFixedTimestepNystroem, this ) },
        },
        {
            "CashKarp",
            { Iterator::available.at( "CashKarp" ).halo_size, std::bind( &Solver::iterateFixedTimestepCashKarp, this ) },
        },
        {
            "Fehlberg2",
            { Iterator::available.at( "Fehlberg2" ).halo_size, std::bind( &Solver::iterateFixedTimestepFehlberg2, this ) },
        },
        {
            "Fehlberg12",
            { Iterator::available.at( "Fehlberg12" ).halo_size, std::bind( &Solver::iterateVariableTimestepFehlberg2, this ) },
        },
        {
            "Fehlberg5",
            { Iterator::available.at( "Fehlberg5" ).halo_size, std::bind( &Solver::iterateFixedTimestepFehlberg5, this ) },
        },
        {
            "Fehlberg45",
            { Iterator::available.at( "Fehlberg45" ).halo_size, std::bind( &Solver::iteratevariableTimestepFehlberg5, this ) },
        },
        {
            "Bogacki",
            { Iterator::available.at( "Bogacki" ).halo_size, std::bind( &Solver::iterateFixedTimestepBogacki, this ) },
        },
        {
            "DP5",
            { Iterator::available.at( "DP5" ).halo_size, std::bind( &Solver::iterateFixedTimestepDOP5, this ) },
        },
        {
            "DP8",
            { Iterator::available.at( "DP8" ).halo_size, std::bind( &Solver::iterateFixedTimestepDOP853, this ) },
        },
        {
            "DP85",
            { Iterator::available.at( "DP85" ).halo_size, std::bind( &Solver::iterateVariableTimestepDOP853, this ) },
        },
        {
            "NSRK8",
            { Iterator::available.at( "NSRK8" ).halo_size, std::bind( &Solver::iterateFixedTimestepNSRK78, this ) },
        },
        {
            "NSRK78",
            { Iterator::available.at( "NSRK78" ).halo_size, std::bind( &Solver::iterateVariableTimestepNSRK78, this ) },
        },
        {
            "DP45",
            { Iterator::available.at( "DP45" ).halo_size, std::bind( &Solver::iterateVariableTimestepDOP45, this ) },
        },
        {
            "SSFM",
            { 0, std::bind( &Solver::iterateSplitStepFourier, this ) },
        },
    };

    // Main System function. Either gp_scalar or gp_tetm.
    // Both functions have signature void(int i, Type::uint32 current_halo, Solver::VKernelArguments time, Solver::KernelArguments args, Solver::InputOutput io)
    std::function<void( int, Type::uint32, KernelArguments, InputOutput )> runge_function;

    bool iterate();

    void applyFFTFilter( bool apply_mask = true );

    enum class FFT { inverse, forward };
    void calculateFFT( Type::complex* device_ptr_in, Type::complex* device_ptr_out, FFT dir );

    void cacheValues();
    void cacheMatrices();

    // The block size is specified by the user in the system.block_size variable.
    // This solver function the calculates the appropriate grid size for the given execution range.
    std::pair<dim3, dim3> getLaunchParameters( const Type::uint32 N_c, const Type::uint32 N_r = 1 ) {
#ifdef USE_CPU
        dim3 block_size = { N_r, 1, 1 };
        dim3 grid_size = { N_c, 1, 1 };
#else
        dim3 block_size = { system.block_size, 1, 1 };
        dim3 grid_size = { ( N_c * N_r + block_size.x ) / block_size.x, 1, 1 };
#endif
        return { block_size, grid_size };
    }
};

} // namespace PHOENIX
