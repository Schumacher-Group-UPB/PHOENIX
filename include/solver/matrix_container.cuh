#pragma once
#include "cuda/typedef.cuh"
#include "cuda/cuda_matrix.cuh"

namespace PC3 {

// #define MATRIX_LIST \ // <--- Backslash at the end of every but the last line!
// DEFINE_MATRIX(Type::complex, custom_matrix ) // \  <--- Backslash at the end of every but the last line!
/////////////////////////////
// Add your matrices here. //
// Make sure to end each   //
// but the last line with  //
// a backslash!            //
/////////////////////////////

struct MatrixContainer {
    // Cache triggers
    bool use_twin_mode, use_fft, use_stochastic;

    // Wavefunction and Reservoir Matrices.
    PC3::CUDAMatrix<Type::complex> wavefunction_plus, wavefunction_minus, reservoir_plus, reservoir_minus;
    // Corresponding Buffer Matrices
    PC3::CUDAMatrix<Type::complex> buffer_wavefunction_plus, buffer_wavefunction_minus, buffer_reservoir_plus, buffer_reservoir_minus;
    // Corresponding initial States. These are simple host vectors, not CUDAMatrices.
    PC3::Type::host_vector<Type::complex> initial_state_plus, initial_state_minus, initial_reservoir_plus, initial_reservoir_minus;

    // Pump, Pulse and Potential Matrices. These are vectors of CUDAMatrices.
    PC3::CUDAMatrix<Type::complex> pulse_plus, pulse_minus;
    PC3::CUDAMatrix<Type::real> pump_plus, pump_minus, potential_plus, potential_minus;

    // FFT Matrices. These are simple device vectors, not CUDAMatrices.
    PC3::Type::device_vector<Type::complex> fft_plus, fft_minus;
    PC3::Type::device_vector<Type::real> fft_mask_plus, fft_mask_minus;

    // Random Number generator and buffer. We only need a single random number matrix of size subgrid_x*subgrid_y
    // These can also be simple device vectors, as subgridding is not required here
    PC3::Type::device_vector<Type::complex> random_number;
    PC3::Type::device_vector<Type::cuda_random_state> random_state;

    // RK45 Style Error Matrix.
    PC3::CUDAMatrix<Type::complex> rk_error;

    // K Matrices. These are vectors of CUDAMatrices.
    PC3::CUDAMatrix<Type::complex> k_wavefunction_plus, k_wavefunction_minus, k_reservoir_plus, k_reservoir_minus;

    // Halo Map
    PC3::Type::device_vector<int> halo_map;

// User Defined Matrices
#ifdef MATRIX_LIST
    #define DEFINE_MATRIX( type, name ) PC3::CUDAMatrix<type> name;
    MATRIX_LIST
    #undef X
#endif

    // Empty Constructor
    MatrixContainer() = default;

    // Construction Chain. The Host Matrix is always constructed (who carese about RAM right?) and the device matrix is constructed if the condition is met.
    void constructAll( const int N_c, const int N_r, bool use_twin_mode, bool use_fft, bool use_stochastic, int k_max, const int n_pulses_plus, const int n_pumps_plus,
                       const int n_potentials_plus, const int n_pulses_minus, const int n_pumps_minus, const int n_potentials_minus, const int subgrids_columns, const int subgrids_rows,
                       const int halo_size ) {
        // Cache triggers
        this->use_twin_mode = use_twin_mode;
        this->use_fft = use_fft;
        this->use_stochastic = use_stochastic;

        // MARK: Plus Components
        // ======================================================================================================== //
        // =------------------------- Construct Plus Components of the matrices ----------------------------------= //
        // ======================================================================================================== //

        // Wavefunction and Reservoir Matrices
        wavefunction_plus.construct( N_r, N_c, subgrids_columns, subgrids_rows, halo_size, "wavefunction_plus" );
        reservoir_plus.construct( N_r, N_c, subgrids_columns, subgrids_rows, halo_size, "reservoir_plus" );
        buffer_wavefunction_plus.construct( N_r, N_c, subgrids_columns, subgrids_rows, halo_size, "buffer_wavefunction_plus" );
        buffer_reservoir_plus.construct( N_r, N_c, subgrids_columns, subgrids_rows, halo_size, "buffer_reservoir_plus" );
        initial_state_plus = PC3::Type::device_vector<Type::complex>( N_c * N_r );
        initial_reservoir_plus = PC3::Type::device_vector<Type::complex>( N_c * N_r );

        // Pump, Pulse and Potential Matrices
        pump_plus.construct( N_r, N_c, subgrids_columns, subgrids_rows, halo_size, "pump_plus", n_pumps_plus );
        pulse_plus.construct( N_r, N_c, subgrids_columns, subgrids_rows, halo_size, "pulse_plus", n_pulses_plus );
        potential_plus.construct( N_r, N_c, subgrids_columns, subgrids_rows, halo_size, "potential_plus", n_potentials_plus );

        k_wavefunction_plus.construct( N_r, N_c, subgrids_columns, subgrids_rows, halo_size, "k_wavefunction_plus_" + std::to_string( k_max ), k_max );
        k_reservoir_plus.construct( N_r, N_c, subgrids_columns, subgrids_rows, halo_size, "k_reservoir_plus_" + std::to_string( k_max ), k_max );

        // FFT Matrices
        if ( use_fft ) {
            fft_plus = PC3::Type::device_vector<Type::complex>( N_c * N_r );
            fft_mask_plus = PC3::Type::device_vector<Type::real>( N_c * N_r );
        }

        // MARK: Independent Components
        // ======================================================================================================== //
        // =------------------------------------ Independent Components ------------------------------------------= //
        // ======================================================================================================== //

        // Random Number generator and buffer
        if ( use_stochastic ) {
            const Type::uint32 subgrid_N = N_c * N_r / subgrids_columns / subgrids_rows;
            random_number = PC3::Type::device_vector<Type::complex>( subgrid_N );
            random_state = PC3::Type::device_vector<Type::cuda_random_state>( subgrid_N );
        }

        // RK Error Matrix. For now, use k_max > 4 as a construction condition.
        if (k_max > 4)
            rk_error.construct( N_r, N_c, subgrids_columns, subgrids_rows, halo_size, "rk_error" );

        // Construct the halo map. 6*total halo points because we have 6 coordinates for each point
        const Type::uint32 total_halo_points = ( N_c + 2 * halo_size ) * ( N_r + 2 * halo_size ) - N_c * N_r;
        halo_map = PC3::Type::device_vector<int>( total_halo_points * 6 );

        // User defined matrices
#ifdef MATRIX_LIST
    #define DEFINE_MATRIX( type, name ) name.construct( N_r, N_c, subgrids_columns, subgrids_rows, halo_size, #name );
        MATRIX_LIST
    #undef X
#endif
        if ( not use_twin_mode )
            return;

        // MARK: Minus Components
        // ======================================================================================================== //
        // =------------------------- Construct Minus Components of the matrices ---------------------------------= //
        // ======================================================================================================== //

        // Wavefunction and Reservoir Matrices
        wavefunction_minus.construct( N_r, N_c, subgrids_columns, subgrids_rows, halo_size, "wavefunction_minus" );
        reservoir_minus.construct( N_r, N_c, subgrids_columns, subgrids_rows, halo_size, "reservoir_minus" );
        buffer_wavefunction_minus.construct( N_r, N_c, subgrids_columns, subgrids_rows, halo_size, "buffer_wavefunction_minus" );
        buffer_reservoir_minus.construct( N_r, N_c, subgrids_columns, subgrids_rows, halo_size, "buffer_reservoir_minus" );
        initial_state_minus = PC3::Type::device_vector<Type::complex>( N_c * N_r );
        initial_reservoir_minus = PC3::Type::device_vector<Type::complex>( N_c * N_r );

        // Pump, Pulse and Potential Matrices
        pump_minus.construct( N_r, N_c, subgrids_columns, subgrids_rows, halo_size, "pump_minus", n_pumps_minus );
        pulse_minus.construct( N_r, N_c, subgrids_columns, subgrids_rows, halo_size, "pulse_minus", n_pulses_minus );
        potential_minus.construct( N_r, N_c, subgrids_columns, subgrids_rows, halo_size, "potential_minus", n_potentials_minus );

        // K Matrices
        k_wavefunction_minus.construct( N_r, N_c, subgrids_columns, subgrids_rows, halo_size, "k_wavefunction_minus_" + std::to_string( k_max ), k_max );
        k_reservoir_minus.construct( N_r, N_c, subgrids_columns, subgrids_rows, halo_size, "k_reservoir_minus_" + std::to_string( k_max ), k_max );

        // FFT Matrices
        if ( use_fft ) {
            fft_minus = PC3::Type::device_vector<Type::complex>( N_c * N_r );
            fft_mask_minus = PC3::Type::device_vector<Type::real>( N_c * N_r );
        }
    }

    struct Pointers {
        // Wavefunction and Reservoir Matrices
        Type::complex* wavefunction_plus PULSE_ALIGNED(Type::complex) = nullptr;
        Type::complex* wavefunction_minus PULSE_ALIGNED(Type::complex) = nullptr;
        Type::complex* reservoir_plus PULSE_ALIGNED(Type::complex) = nullptr;
        Type::complex* reservoir_minus PULSE_ALIGNED(Type::complex) = nullptr;
        // Corresponding Buffer Matrices
        Type::complex* buffer_wavefunction_plus PULSE_ALIGNED(Type::complex) = nullptr;
        Type::complex* buffer_wavefunction_minus PULSE_ALIGNED(Type::complex) = nullptr;
        Type::complex* buffer_reservoir_plus PULSE_ALIGNED(Type::complex) = nullptr;
        Type::complex* buffer_reservoir_minus PULSE_ALIGNED(Type::complex) = nullptr;

        // Pump, Pulse and Potential Matrices
        Type::real* pump_plus PULSE_ALIGNED(Type::real) = nullptr;
        Type::real* pump_minus PULSE_ALIGNED(Type::real) = nullptr;
        Type::complex* pulse_plus PULSE_ALIGNED(Type::complex) = nullptr;
        Type::complex* pulse_minus PULSE_ALIGNED(Type::complex) = nullptr;
        Type::real* potential_plus PULSE_ALIGNED(Type::real) = nullptr;
        Type::real* potential_minus PULSE_ALIGNED(Type::real) = nullptr;

        // K Matrices
        Type::complex* k_wavefunction_plus PULSE_ALIGNED(Type::complex) = nullptr;
        Type::complex* k_wavefunction_minus PULSE_ALIGNED(Type::complex) = nullptr;
        Type::complex* k_reservoir_plus PULSE_ALIGNED(Type::complex) = nullptr;
        Type::complex* k_reservoir_minus PULSE_ALIGNED(Type::complex) = nullptr;

        // FFT Matrices
        Type::complex* fft_plus = nullptr;
        Type::complex* fft_minus = nullptr;
        Type::real* fft_mask_plus = nullptr;
        Type::real* fft_mask_minus = nullptr;

        // Random Number generator and buffer
        Type::complex* random_number = nullptr;
        Type::cuda_random_state* random_state = nullptr;

        // RK Error
        Type::complex* rk_error = nullptr;

        // Halo Map
        int* halo_map = nullptr;

        // Custom Components
#ifdef MATRIX_LIST
    #define DEFINE_MATRIX( type, ptrstruct, name, size_scaling, condition_for_construction ) type* name = nullptr;
        MATRIX_LIST
    #undef X
#endif

        // Nullptr
        std::nullptr_t discard = nullptr;
    };

    Pointers pointers( const Type::uint32 subgrid ) {
        Pointers ptrs;

        // MARK: Plus Component
        // Wavefunction and Reservoir Matrices. Only the Plus components are initialized here. If the twin mode is enabled, the minus components are initialized in the next step.
        // The kernels can then check for nullptr and use the minus components if they are not nullptr.
        ptrs.wavefunction_plus = wavefunction_plus.getDevicePtr( subgrid );
        ptrs.reservoir_plus = reservoir_plus.getDevicePtr( subgrid );
        ptrs.buffer_wavefunction_plus = buffer_wavefunction_plus.getDevicePtr( subgrid );
        ptrs.buffer_reservoir_plus = buffer_reservoir_plus.getDevicePtr( subgrid );

        // Pump, Pulse and Potential Matrices
        ptrs.pump_plus = pump_plus.getDevicePtr( subgrid );
        ptrs.pulse_plus = pulse_plus.getDevicePtr( subgrid );
        ptrs.potential_plus = potential_plus.getDevicePtr( subgrid );

        // K Matrices
        ptrs.k_wavefunction_plus = k_wavefunction_plus.getDevicePtr( subgrid );
        ptrs.k_reservoir_plus = k_reservoir_plus.getDevicePtr( subgrid );

        // FFT Matrices
        ptrs.fft_plus = GET_RAW_PTR( fft_plus );
        if ( use_fft ) {
            ptrs.fft_mask_plus = GET_RAW_PTR( fft_mask_plus );
        }

        // MARK: Independent Components
        if ( use_stochastic ) {
            ptrs.random_number = GET_RAW_PTR( random_number );
            ptrs.random_state = GET_RAW_PTR( random_state );
        }

        ptrs.rk_error = rk_error.getDevicePtr( subgrid );

        // Halo Map
        ptrs.halo_map = GET_RAW_PTR( halo_map );

        // User Defined Matrices
#ifdef MATRIX_LIST
    #define DEFINE_MATRIX( type, ptrstruct, name, size_scaling, condition_for_construction ) ptrs.name = name.getDevicePtr( subgrid );
        MATRIX_LIST
    #undef X
#endif

        // MARK: Minus Component
        if ( not use_twin_mode )
            return ptrs;

        // Wavefunction and Reservoir Matrices
        ptrs.wavefunction_minus = wavefunction_minus.getDevicePtr( subgrid );
        ptrs.reservoir_minus = reservoir_minus.getDevicePtr( subgrid );
        ptrs.buffer_wavefunction_minus = buffer_wavefunction_minus.getDevicePtr( subgrid );
        ptrs.buffer_reservoir_minus = buffer_reservoir_minus.getDevicePtr( subgrid );

        // Pump, Pulse and Potential Matrices
        ptrs.pump_minus = pump_minus.getDevicePtr( subgrid );
        ptrs.pulse_minus = pulse_minus.getDevicePtr( subgrid );
        ptrs.potential_minus = potential_minus.getDevicePtr( subgrid );

        // K Matrices
        ptrs.k_wavefunction_minus = k_wavefunction_minus.getDevicePtr( subgrid );
        ptrs.k_reservoir_minus = k_reservoir_minus.getDevicePtr( subgrid );

        // FFT Matrices
        ptrs.fft_minus = GET_RAW_PTR( fft_minus );
        if ( use_fft ) {
            ptrs.fft_mask_minus = GET_RAW_PTR( fft_mask_minus );
        }

        return ptrs;
    }
};

} // namespace PC3