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

    Solver( PHOENIX::SystemParameters& system ) : system( system ), filehandler( system.filehandler ) {}

    void initialize();
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

    void applyFFTFilter( bool apply_mask = true );

    enum class FFT { inverse, forward };
    void calculateFFT( Type::complex* device_ptr_in, Type::complex* device_ptr_out, FFT dir );

    void cacheValues();
    void cacheMatrices();

    void normalizeImaginaryTimePropagation();

        /**
    adjusts timestep for adaptive methods
    discrete time steps = use t_delta for adjustments of dt between dt_min, dt_max
    power = error scaling
     */
        bool
        adaptTimeStep( const Type::real power, bool use_discrete_update_steps = true );

    void swapBuffers();

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

   public:
    // Virtual functions for the solvers
    virtual void step( bool variable_time_step ) = 0;
    virtual ~Solver() = default;

    bool iterate( bool force_fixed_time_step = false);

    std::string name() const {
        return name_;
    }
    std::string description() const {
        return description_;
    }
    std::string butcher_tableau_string() const {
        return butcher_tableau_;
    }
    uint32_t maximum_k_used() const {
        return k_max_;
    }
    uint32_t halo_size() const {
        return halo_size_;
    }

   protected:
    // If true, the solver .iterate() function provides adaptive time stepping.
    bool is_adaptive_{ false };
    std::string name_;
    std::string description_;
    std::string butcher_tableau_;
    uint32_t k_max_{ 0 };     // The maximum order of the solver. This is used to determine the size of the halo map.
    uint32_t halo_size_{ 0 }; // The size of the halo map. This is used to determine the size of the halo map.
};

} // namespace PHOENIX
