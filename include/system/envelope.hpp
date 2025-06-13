#pragma once

#include <vector>
#include <string>
#include <map>
#include <memory>
#include <bit>

#include "cuda/typedef.cuh"
#include "misc/commandline_io.hpp"

namespace PHOENIX {

// TODO: Because the envelope calculation is now fully cpu sided, use a vector of structs instead of a struct of vectors to store the envelope parameters
class Envelope {
   public:
    // Parameters to Construct the Envelope from
    std::vector<PHOENIX::Type::real> amp, width_x, width_y, x, y, exponent;
    std::vector<int> m;
    std::vector<PHOENIX::Type::real> freq, sigma, t0;
    std::vector<std::string> s_type, s_pol, s_behavior, s_temp;
    // Or path to load the matrix from
    std::vector<std::string> load_path, load_path_temporal;
    // Either way, all of these vectors should have the same length

    // Identifier for temporal grouping
    // Same length as amp, width, ... and maps the spatial envelope to the temporal envelopes
    std::vector<int> group_identifier;
    // Helper map to map the temporal group identifier to an index in group_identifier
    std::map<std::string, int> str_to_group_identifier;
    // Helper to load cache matrices from paths
    std::vector<std::unique_ptr<PHOENIX::Type::complex[]>> cache;
    // Temporal Envelope. This will be recalculated every timestep
    PHOENIX::Type::host_vector<PHOENIX::Type::complex> temporal_envelope;
    // Points for interpolation
    std::vector<std::vector<std::vector<Type::real>>> temporal_time_points; // TODO: Read Points and interpolate between them

    enum class EnvType : Type::uint32 {
        Gauss = 1,              // Gaussian Envelope
        OuterExponent = 1 << 1, // Exponent is applied to the total envelope and not just the function argument
        Ring = 1 << 2,          // Ring shape is enabled
        NoDivide = 1 << 3,      // The Amplitude is NOT devided by sqrt(2*pi)*w
        Local = 1 << 4          // The grid is treated from -1 to 1 instead of from -xmax to xmax
    };
    std::vector<EnvType> type;

    enum class Polarization : Type::uint32 {
        Plus = 1,
        Minus = 1 << 1,
        Both = 3 // Set to three explicitly such that Plus,Minus = Both
    };
    std::vector<Polarization> pol;

    enum class Behavior : Type::uint32 {
        Add = 1,
        Multiply = 1 << 1,
        Replace = 1 << 2,
        Adaptive = 1 << 3,
        Complex = 1 << 4,
    };
    std::vector<Behavior> behavior;

    enum class Temporal : Type::uint32 {
        IExp = 1,
        Cos = 1 << 1,
        Gauss = 1 << 2,
        Constant = 1 << 3,
        Loaded = 1 << 4,
    };
    std::vector<Temporal> temporal;

    static inline std::map<std::string, Behavior> BehaviorFromString = {
        { "add", Behavior::Add }, { "multiply", Behavior::Multiply }, { "replace", Behavior::Replace }, { "adaptive", Behavior::Adaptive }, { "complex", Behavior::Complex },
    };
    static inline std::map<std::string, Polarization> PolarizationFromString = {
        { "plus", Polarization::Plus },
        { "minus", Polarization::Minus },
        { "both", Polarization::Both },
    };
    static inline std::map<std::string, EnvType> TypeFromString = {
        { "gauss", EnvType::Gauss }, { "outerExponent", EnvType::OuterExponent }, { "ring", EnvType::Ring }, { "noDivide", EnvType::NoDivide }, { "local", EnvType::Local },
    };
    static inline std::map<std::string, Temporal> TemporalFromString = {
        { "gauss", Temporal::Gauss }, { "iexp", Temporal::IExp }, { "osc", Temporal::IExp }, { "cos", Temporal::Cos }, { "constant", Temporal::Constant },
    };

    static inline int AllGroups = -1;

    void addSpacial( PHOENIX::Type::real amp, PHOENIX::Type::real width_x, PHOENIX::Type::real width_y, PHOENIX::Type::real x, PHOENIX::Type::real y, PHOENIX::Type::real exponent, const std::string& s_type, const std::string& s_pol, const std::string& s_behavior, const std::string& s_m );
    void addSpacial( const std::string& path, PHOENIX::Type::real amp, const std::string& s_behaviour, const std::string& s_pol );
    void addTemporal( PHOENIX::Type::real t0, PHOENIX::Type::real sigma, PHOENIX::Type::real freq, const std::string& s_temp );
    void addTemporal( const std::string& path );
    int size() const;
    int groupSize() const;
    int sizeOfGroup( int g ) const;

    struct Dimensions {
        Type::uint32 N_c, N_r;
        PHOENIX::Type::real L_x, L_y, dx, dy;
        Dimensions( Type::uint32 N_c, Type::uint32 N_r, PHOENIX::Type::real L_x, PHOENIX::Type::real L_y, PHOENIX::Type::real dx, PHOENIX::Type::real dy ) : N_c( N_c ), N_r( N_r ), L_x( L_x ), L_y( L_y ), dx( dx ), dy( dy ) {
        }
    };

    void calculate( PHOENIX::Type::real* buffer, const int group, Polarization polarization, Dimensions dim, PHOENIX::Type::real default_value_if_no_mask = 0.0 );
    void calculate( PHOENIX::Type::complex* buffer, const int group, Polarization polarization, Dimensions dim, PHOENIX::Type::real default_value_if_no_mask = 0.0 );

    // Evaluates all the current temporal envelopes and stores them in the temporal_envelope vector
    void updateTemporal( const PHOENIX::Type::real t );

    // We use template functions here to avoid circular dependencies. TODO: use forward declaration and move this to envelope.cpp
    template <class FH>
    void prepareCache( FH& filehandler, const Dimensions& dim ) {
        // Load Temporal Components
        temporal_time_points = std::vector<std::vector<std::vector<PHOENIX::Type::real>>>( load_path_temporal.size() );
        for ( int c = 0; c < load_path_temporal.size(); c++ ) {
            if ( load_path_temporal[c] == "" ) {
                continue;
            }
            temporal_time_points[c] = filehandler.loadListFromFile( load_path_temporal[c], "temporal" );
            if ( temporal_time_points[c].size() != 3 ) {
                std::cout << PHOENIX::CLIO::prettyPrint( "Error: Temporal envelope must have 3 columns: time, real, imag. PHOENIX_ will most likely crash!", PHOENIX::CLIO::Control::FullWarning ) << std::endl;
            }
        }
        // Load Spatial Components
        if ( cache.size() > 0 )
            return;
        for ( int c = 0; c < load_path.size(); c++ ) {
            cache.push_back( nullptr );
            if ( load_path[c] == "" )
                continue;
            cache.back() = std::make_unique<PHOENIX::Type::complex[]>( dim.N_c * dim.N_r );
            filehandler.loadMatrixFromFile( load_path[c], cache.back().get() );
        }
    }
    template <class FH, typename T>
    void calculate( FH& filehandler, T* buffer, const int group, Polarization polarization, Dimensions dim, PHOENIX::Type::real default_value_if_no_mask = 0.0 ) {
        prepareCache( filehandler, dim );
        calculate( buffer, group, polarization, dim, default_value_if_no_mask );
    }

    bool readInTemporal( const std::string& key ) {
        return TemporalFromString.find( key ) != TemporalFromString.end();
    }

    static Envelope fromCommandlineArguments( int argc, char** argv, const std::string& key, const bool time );
    static Envelope fromCommandlineArguments( int argc, char** argv, const std::vector<std::string>& all_keys, const bool time );

    std::string toString() const;
};

// Overload the bitwise OR (|) operator
template <typename T>
typename std::enable_if<std::is_enum<T>::value && ( std::is_same<T, Envelope::Behavior>::value || std::is_same<T, Envelope::Polarization>::value || std::is_same<T, Envelope::EnvType>::value || std::is_same<T, Envelope::Temporal>::value ), T>::type operator|( T lhs, T rhs ) {
    using underlying_type = typename std::underlying_type<T>::type;
    return static_cast<T>( static_cast<underlying_type>( lhs ) | static_cast<underlying_type>( rhs ) );
}

// Overload the bitwise AND (&) operator. Return a boolean, because we dont need the '&' operator for enums
template <typename T>
typename std::enable_if<std::is_enum<T>::value && ( std::is_same<T, Envelope::Behavior>::value || std::is_same<T, Envelope::Polarization>::value || std::is_same<T, Envelope::EnvType>::value || std::is_same<T, Envelope::Temporal>::value ), bool>::type operator&( T lhs, T rhs ) {
    using underlying_type = typename std::underlying_type<T>::type;
    return std::has_single_bit<underlying_type>( static_cast<underlying_type>( lhs ) & static_cast<underlying_type>( rhs ) );
}

static inline Type::complex gaussian_complex_oscillator( Type::real t, Type::real t0, Type::real sigma, Type::real freq ) {
    return CUDA::exp( -Type::complex( ( t - t0 ) * ( t - t0 ) / ( Type::real( 2.0 ) * sigma * sigma ), freq * ( t - t0 ) ) );
}
static inline Type::real gaussian_oscillator( Type::real t, Type::real t0, Type::real sigma, Type::real freq ) {
    const auto p = ( t - t0 ) / sigma;
    return std::exp( -0.5 * p * p ) * ( 1.0 + std::cos( freq * ( t - t0 ) ) ) / 2.0;
}
static inline Type::real gaussian_envelope( Type::real t, Type::real t0, Type::real sigma, Type::real power ) {
    const auto p = ( t - t0 ) / sigma;
    return std::exp( -0.5 * std::pow( p * p, power ) );
}
// ...

} // namespace PHOENIX