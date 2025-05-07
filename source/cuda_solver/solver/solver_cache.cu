#include <vector>
#include <string>

#include "cuda/typedef.cuh"
#include "solver/solver.hpp"

void PHOENIX::Solver::cacheValues() {
    // System Time
    cache_map_scalar["t"].emplace_back( system.p.t );

    // Min and Max
    auto [min_plus, max_plus] = matrix.wavefunction_plus.extrema();
    cache_map_scalar["min_plus"].emplace_back( CUDA::abs( min_plus ) );
    cache_map_scalar["max_plus"].emplace_back( CUDA::abs( max_plus ) );

    // Output Pulse, Pump and Potential Envelope functions to cache_map_scalar
    for ( int g = 0; g < system.pulse.groupSize(); g++ ) {
        if ( system.pulse.temporal[g] & PHOENIX::Envelope::Temporal::Constant )
            continue;
        Type::complex pulse = system.pulse.temporal_envelope[g];
        cache_map_scalar["pulse_" + std::to_string( g ) + "_real"].push_back( PHOENIX::CUDA::real( pulse ) );
        cache_map_scalar["pulse_" + std::to_string( g ) + "_imag"].push_back( PHOENIX::CUDA::imag( pulse ) );
    }
    for ( int g = 0; g < system.pump.groupSize(); g++ ) {
        if ( system.pump.temporal[g] & PHOENIX::Envelope::Temporal::Constant )
            continue;
        Type::real pump = PHOENIX::CUDA::real( system.pump.temporal_envelope[g] );
        cache_map_scalar["pump_" + std::to_string( g )].push_back( PHOENIX::CUDA::real( pump ) );
    }
    for ( int g = 0; g < system.potential.groupSize(); g++ ) {
        if ( system.potential.temporal[g] & PHOENIX::Envelope::Temporal::Constant )
            continue;
        Type::real potential = PHOENIX::CUDA::real( system.potential.temporal_envelope[g] );
        cache_map_scalar["potential_" + std::to_string( g )].push_back( PHOENIX::CUDA::real( potential ) );
    }

    // TE/TM Guard
    if ( not system.use_twin_mode )
        return;

    // Same for _minus component if use_twin_mode is true
    const auto [min_minus, max_minus] = matrix.wavefunction_minus.extrema();
    cache_map_scalar["min_minus"].emplace_back( CUDA::abs( min_minus ) );
    cache_map_scalar["max_minus"].emplace_back( CUDA::abs( max_minus ) );
}

void PHOENIX::Solver::cacheToFiles() {
    if ( not system.doOutput( "all", "max", "scalar" ) )
        return;

    auto& file_max = filehandler.getFile( "scalar", "txt" );
    file_max << "index ";
    for ( const auto& [key, _] : cache_map_scalar ) file_max << key << " ";
    file_max << "\n";
    for ( int i = 0; i < cache_map_scalar["t"].size(); i++ ) {
        file_max << i << " ";
        for ( const auto& [_, vec] : cache_map_scalar ) file_max << vec[i] << " ";
        file_max << "\n";
    }
    file_max.close();
}

// TODO: Support Multiple History Outputs, and also support piping them into a single file.
// something like "append" mode, that doesnt open a new file but instead appends to the existing one.
PHOENIX::Type::uint32 _local_history_output_counter = 1; // output_history_matrix_every
void PHOENIX::Solver::cacheMatrices() {
    if ( not system.do_output_history_matrix ) // Don't output history matrix
        return;
    if ( system.p.t < system.output_history_start_time ) // Start time not reached
        return;
    if ( _local_history_output_counter < system.output_history_matrix_every ) { // Not yet time to output
        _local_history_output_counter++;
        return;
    }
    std::string suffix = "_" + std::to_string( system.p.t );
    _local_history_output_counter = 1;
    outputMatrices( system.history_matrix_start_x, system.history_matrix_end_x, system.history_matrix_start_y, system.history_matrix_end_y, system.history_matrix_output_increment, suffix, "timeoutput/" );
}
