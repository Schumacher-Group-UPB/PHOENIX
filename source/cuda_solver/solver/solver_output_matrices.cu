#include <vector>
#include <string>
#include <future>
#include <mutex>
#include "cuda/typedef.cuh"
#include "solver/solver.hpp"

// TODO: to ensure the async call outputs the correct matrices, we need to make sure the lambda takes a *copy* of the host arrays.
// This will be fine, because copying 100MB in memory is much faster than writing to disk.
// For now, use mutex, making the async call not really async if the matrices are too large.
//std::mutex mtx;

// TODO: little code debt, because toFull().fullMatrixPointer() is not thread safe. This is because the toFull() method writes to a static buffer that is shared between the matrices
// to circumvent this, we would add a toFullCopy() method that returns a new matrix with a new buffer. Then async write that vector to disk. For multithreaded output, just give each thread its own fullcopy buffer.

// Also, we really need a better way to output the matrices. This is a bit of a mess. And we need an output queue that doesnt stall the main thread.

// TODO: Should the arguments be shared ptrs?

void PHOENIX::Solver::outputMatrices( const Type::uint32 start_x, const Type::uint32 end_x, const Type::uint32 start_y, const Type::uint32 end_y, const Type::uint32 increment, const std::string& suffix, const std::string& prefix ) {
    const static std::vector<std::string> fileoutputkeys = { "wavefunction_plus", "wavefunction_minus", "reservoir_plus", "reservoir_minus", "fft_plus", "fft_minus" };
    auto header_information = PHOENIX::FileHandler::Header( system.p.L_x * ( end_x - start_x ) / system.p.N_c, system.p.L_y * ( end_y - start_y ) / system.p.N_r, system.p.dx, system.p.dy, system.p.t );
    auto fft_header_information = PHOENIX::FileHandler::Header( -1.0 * ( end_x - start_x ) / system.p.N_c, -1.0 * ( end_y - start_y ) / system.p.N_r, 2.0 / system.p.N_c, 2.0 / system.p.N_r, system.p.t );
    //auto res = std::async( std::launch::async, [&]() {
    //std::lock_guard<std::mutex> lock( mtx );
    //#pragma omp parallel for
    for ( int i = 0; i < fileoutputkeys.size(); i++ ) {
        auto key = fileoutputkeys[i];
        if ( key == "wavefunction_plus" and system.doOutput( "wavefunction", "psi", "wavefunction_plus", "psi_plus", "plus", "wf", "mat", "all", "initial", "initial_plus" ) ) {
            Type::host_vector<Type::complex> buffer = matrix.wavefunction_plus.getFullMatrix( true );
            filehandler.queueComplexMatrix( buffer, start_x, end_x, start_y, end_y, system.p.N_c, system.p.N_r, increment, header_information, prefix + key + suffix );
            //auto future = std::async( std::launch::async, [buffer, header_information, start_x, end_x, start_y, end_y, increment, this, key, suffix, prefix]() { this->system.filehandler.outputMatrixToFile( buffer.data(), start_x, end_x, start_y, end_y, this->system.p.N_c, this->system.p.N_r, increment, header_information, prefix + key + suffix ); } );
            //filehandler.outputMatrixToFile( buffer.data(), start_x, end_x, start_y, end_y, system.p.N_c, system.p.N_r, increment, header_information, prefix + key + suffix );
        }
        if ( key == "reservoir_plus" and system.use_reservoir and system.doOutput( "mat", "reservoir", "n", "reservoir_plus", "n_plus", "plus", "rv", "mat", "all" ) ) {
            Type::host_vector<Type::complex> buffer = matrix.reservoir_plus.getFullMatrix( true );
            filehandler.queueComplexMatrix( buffer, start_x, end_x, start_y, end_y, system.p.N_c, system.p.N_r, increment, header_information, prefix + key + suffix );
            //auto future = std::async( std::launch::async, [buffer, header_information, start_x, end_x, start_y, end_y, increment, this, key, suffix, prefix]() { this->system.filehandler.outputMatrixToFile( buffer.data(), start_x, end_x, start_y, end_y, this->system.p.N_c, this->system.p.N_r, increment, header_information, prefix + key + suffix ); } );
            //filehandler.outputMatrixToFile( buffer.data(), start_x, end_x, start_y, end_y, system.p.N_c, system.p.N_r, increment, header_information, prefix + key + suffix );
        }
        if ( system.fft_every < system.t_max and key == "fft_plus" and system.doOutput( "fft_mask", "fft", "fft_plus", "plus", "mat", "all" ) ) {
            Type::host_vector<Type::complex> buffer = matrix.fft_plus;
            filehandler.queueComplexMatrix( buffer, start_x, end_x, start_y, end_y, system.p.N_c, system.p.N_r, increment, fft_header_information, prefix + key + suffix );
            //auto future = std::async( std::launch::async, [buffer, fft_header_information, start_x, end_x, start_y, end_y, increment, this, key, suffix, prefix]() { this->system.filehandler.outputMatrixToFile( buffer.data(), start_x, end_x, start_y, end_y, this->system.p.N_c, this->system.p.N_r, increment, fft_header_information, prefix + key + suffix ); } );
            //filehandler.outputMatrixToFile( buffer.data(), start_x, end_x, start_y, end_y, system.p.N_c, system.p.N_r, increment, fft_header_information, prefix + key + suffix );
        }
        // Guard when not useing TE/TM splitting
        if ( not system.use_twin_mode )
            continue;
        if ( key == "wavefunction_minus" and system.doOutput( "wavefunction", "psi", "wavefunction_minus", "psi_minus", "plus", "wf", "mat", "all", "initial", "initial_minus" ) ) {
            Type::host_vector<Type::complex> buffer = matrix.wavefunction_minus.getFullMatrix( true );
            filehandler.queueComplexMatrix( buffer, start_x, end_x, start_y, end_y, system.p.N_c, system.p.N_r, increment, header_information, prefix + key + suffix );
            //auto future = std::async( std::launch::async, [buffer, header_information, start_x, end_x, start_y, end_y, increment, this, key, suffix, prefix]() { this->system.filehandler.outputMatrixToFile( buffer.data(), start_x, end_x, start_y, end_y, this->system.p.N_c, this->system.p.N_r, increment, header_information, prefix + key + suffix ); } );
            //filehandler.outputMatrixToFile( buffer.data(), start_x, end_x, start_y, end_y, system.p.N_c, system.p.N_r, increment, header_information, prefix + key + suffix );
        }
        if ( key == "reservoir_minus" and system.use_reservoir and system.doOutput( "reservoir", "n", "reservoir_minus", "n_minus", "plus", "rv", "mat", "all" ) ) {
            filehandler.queueComplexMatrix( matrix.reservoir_minus.getFullMatrix( true ), start_x, end_x, start_y, end_y, system.p.N_c, system.p.N_r, increment, header_information, prefix + key + suffix );
            Type::host_vector<Type::complex> buffer = matrix.reservoir_minus.getFullMatrix( true );
            //auto future = std::async( std::launch::async, [buffer, header_information, start_x, end_x, start_y, end_y, increment, this, key, suffix, prefix]() { this->system.filehandler.outputMatrixToFile( buffer.data(), start_x, end_x, start_y, end_y, this->system.p.N_c, this->system.p.N_r, increment, header_information, prefix + key + suffix ); } );
            //filehandler.outputMatrixToFile( buffer.data(), start_x, end_x, start_y, end_y, system.p.N_c, system.p.N_r, increment, header_information, prefix + key + suffix );
        }
        if ( system.fft_every < system.t_max and key == "fft_minus" and system.doOutput( "fft_mask", "fft", "fft_minus", "plus", "mat", "all" ) ) {
            Type::host_vector<Type::complex> buffer = matrix.fft_minus;
            filehandler.queueComplexMatrix( buffer, start_x, end_x, start_y, end_y, system.p.N_c, system.p.N_r, increment, fft_header_information, prefix + key + suffix );
            //auto future = std::async( std::launch::async, [buffer, fft_header_information, start_x, end_x, start_y, end_y, increment, this, key, suffix, prefix]() { this->system.filehandler.outputMatrixToFile( buffer.data(), start_x, end_x, start_y, end_y, this->system.p.N_c, this->system.p.N_r, increment, fft_header_information, prefix + key + suffix ); } );
            //filehandler.outputMatrixToFile( buffer.data(), start_x, end_x, start_y, end_y, system.p.N_c, system.p.N_r, increment, fft_header_information, prefix + key + suffix );
        }
    }
    //} );
}

void PHOENIX::Solver::outputInitialMatrices() {
    std::cout << "--------------------------- Outputting Initial Matrices ---------------------------" << std::endl;
    auto header_information = PHOENIX::FileHandler::Header( system.p.L_x, system.p.L_y, system.p.dx, system.p.dy, system.p.t );
    // Output Matrices to file
    // Output Matrices to file
    if ( system.doOutput( "all", "mat", "initial_plus", "initial" ) ) {
        Type::host_vector<Type::complex> buffer1 = matrix.initial_state_plus;
        Type::host_vector<Type::complex> buffer2 = matrix.initial_reservoir_plus;

        auto future = std::async( std::launch::async, [buffer1, buffer2, header_information, this]() {
            this->system.filehandler.outputMatrixToFile( buffer1.data(), this->system.p.N_c, this->system.p.N_r, header_information, "initial_wavefunction_plus" );
            if ( system.use_reservoir )
                this->system.filehandler.outputMatrixToFile( buffer2.data(), this->system.p.N_c, this->system.p.N_r, header_information, "initial_reservoir_plus" );
        } );
    }
    if ( system.use_reservoir and system.doOutput( "all", "mat", "pump_plus", "pump" ) )
        for ( int i = 0; i < system.pump.groupSize(); i++ ) {
            auto osc_header_information = PHOENIX::FileHandler::Header( system.p.L_x, system.p.L_y, system.p.dx, system.p.dy, system.p.t, system.pump.t0[i], system.pump.freq[i], system.pump.sigma[i] );
            std::string suffix = i > 0 ? "_" + std::to_string( i ) : "";
            Type::host_vector<Type::real> buffer = matrix.pump_plus.getFullMatrix( true, i );
            auto future = std::async( std::launch::async, [buffer, osc_header_information, this, suffix]() { this->system.filehandler.outputMatrixToFile( buffer.data(), this->system.p.N_c, this->system.p.N_r, osc_header_information, "pump_plus" + suffix ); } );
            //system.filehandler.outputMatrixToFile( buffer.data(), system.p.N_c, system.p.N_r, osc_header_information, "pump_plus" + suffix );
        }
    if ( system.pulse.size() > 0 and system.doOutput( "all", "mat", "pulse_plus", "pulse" ) )
        for ( int i = 0; i < system.pulse.groupSize(); i++ ) {
            auto osc_header_information = PHOENIX::FileHandler::Header( system.p.L_x, system.p.L_y, system.p.dx, system.p.dy, system.p.t, system.pulse.t0[i], system.pulse.freq[i], system.pulse.sigma[i] );
            std::string suffix = i > 0 ? "_" + std::to_string( i ) : "";
            Type::host_vector<Type::complex> buffer = matrix.pulse_plus.getFullMatrix( true, i );
            auto future = std::async( std::launch::async, [buffer, osc_header_information, this, suffix]() { this->system.filehandler.outputMatrixToFile( buffer.data(), this->system.p.N_c, this->system.p.N_r, osc_header_information, "pulse_plus" + suffix ); } );
            //system.filehandler.outputMatrixToFile( buffer.data(), system.p.N_c, system.p.N_r, osc_header_information, "pulse_plus" + suffix );
        }
    if ( system.potential.size() > 0 and system.doOutput( "all", "mat", "potential_plus", "potential" ) )
        for ( int i = 0; i < system.potential.groupSize(); i++ ) {
            auto osc_header_information = PHOENIX::FileHandler::Header( system.p.L_x, system.p.L_y, system.p.dx, system.p.dy, system.p.t, system.potential.t0[i], system.potential.freq[i], system.potential.sigma[i] );
            std::string suffix = i > 0 ? "_" + std::to_string( i ) : "";
            Type::host_vector<Type::real> buffer = matrix.potential_plus.getFullMatrix( true, i );
            auto future = std::async( std::launch::async, [buffer, osc_header_information, this, suffix]() { this->system.filehandler.outputMatrixToFile( buffer.data(), this->system.p.N_c, this->system.p.N_r, osc_header_information, "potential_plus" + suffix ); } );
            //system.filehandler.outputMatrixToFile( buffer.data(), system.p.N_c, system.p.N_r, osc_header_information, "potential_plus" + suffix );
        }
    if ( system.fft_every < system.t_max and system.fft_mask.size() > 0 and system.doOutput( "all", "mat", "fft_plus", "fft" ) ) {
        Type::host_vector<Type::real> buffer = matrix.fft_mask_plus;
        system.filehandler.outputMatrixToFile( buffer.data(), system.p.N_c, system.p.N_r, header_information, "fft_mask_plus" );
    }

    /////////////////////////////
    // Custom Outputs go here! //
    /////////////////////////////

    if ( not system.use_twin_mode )
        return;

    if ( system.doOutput( "all", "mat", "initial_minus", "initial" ) ) {
        Type::host_vector<Type::complex> buffer1 = matrix.initial_state_plus;
        Type::host_vector<Type::complex> buffer2 = matrix.initial_reservoir_plus;
        //system.filehandler.outputMatrixToFile( matrix.initial_state_minus.data(), system.p.N_c, system.p.N_r, header_information, "initial_wavefunctions_minus" );
        //system.filehandler.outputMatrixToFile( matrix.initial_reservoir_minus.data(), system.p.N_c, system.p.N_r, header_information, "initial_reservoir_minus" );
        auto future = std::async( std::launch::async, [buffer1, buffer2, header_information, this]() {
            this->system.filehandler.outputMatrixToFile( buffer1.data(), this->system.p.N_c, this->system.p.N_r, header_information, "initial_wavefunction_minus" );
            if ( system.use_reservoir )
                this->system.filehandler.outputMatrixToFile( buffer2.data(), this->system.p.N_c, this->system.p.N_r, header_information, "initial_reservoir_minus" );
        } );
    }
    if ( system.use_reservoir and system.doOutput( "all", "mat", "pump_minus", "pump" ) )
        for ( int i = 0; i < system.pump.groupSize(); i++ ) {
            auto osc_header_information = PHOENIX::FileHandler::Header( system.p.L_x, system.p.L_y, system.p.dx, system.p.dy, system.p.t, system.pump.t0[i], system.pump.freq[i], system.pump.sigma[i] );
            std::string suffix = i > 0 ? "_" + std::to_string( i ) : "";
            Type::host_vector<Type::real> buffer = matrix.pump_minus.getFullMatrix( true, i );
            auto future = std::async( std::launch::async, [buffer, osc_header_information, this, suffix]() { this->system.filehandler.outputMatrixToFile( buffer.data(), this->system.p.N_c, this->system.p.N_r, osc_header_information, "pump_minus" + suffix ); } );
            //system.filehandler.outputMatrixToFile( buffer.data(), system.p.N_c, system.p.N_r, osc_header_information, "pump_minus" + suffix );
        }
    if ( system.doOutput( "all", "mat", "pulse_minus", "pulse" ) )
        for ( int i = 0; i < system.pulse.groupSize(); i++ ) {
            auto osc_header_information = PHOENIX::FileHandler::Header( system.p.L_x, system.p.L_y, system.p.dx, system.p.dy, system.p.t, system.pulse.t0[i], system.pulse.freq[i], system.pulse.sigma[i] );
            std::string suffix = i > 0 ? "_" + std::to_string( i ) : "";
            Type::host_vector<Type::complex> buffer = matrix.pulse_minus.getFullMatrix( true, i );
            auto future = std::async( std::launch::async, [buffer, osc_header_information, this, suffix]() { this->system.filehandler.outputMatrixToFile( buffer.data(), this->system.p.N_c, this->system.p.N_r, osc_header_information, "pulse_minus" + suffix ); } );
            //system.filehandler.outputMatrixToFile( buffer.data(), system.p.N_c, system.p.N_r, osc_header_information, "pulse_minus" + suffix );
        }
    if ( system.doOutput( "all", "mat", "potential_minus", "potential" ) )
        for ( int i = 0; i < system.potential.groupSize(); i++ ) {
            auto osc_header_information = PHOENIX::FileHandler::Header( system.p.L_x, system.p.L_y, system.p.dx, system.p.dy, system.p.t, system.potential.t0[i], system.potential.freq[i], system.potential.sigma[i] );
            std::string suffix = i > 0 ? "_" + std::to_string( i ) : "";
            Type::host_vector<Type::real> buffer = matrix.potential_minus.getFullMatrix( true, i );
            auto future = std::async( std::launch::async, [buffer, osc_header_information, this, suffix]() { this->system.filehandler.outputMatrixToFile( buffer.data(), this->system.p.N_c, this->system.p.N_r, osc_header_information, "potential_minus" + suffix ); } );
            //system.filehandler.outputMatrixToFile( buffer.data(), system.p.N_c, system.p.N_r, osc_header_information, "potential_minus" + suffix );
        }
    if ( system.fft_every < system.t_max and system.doOutput( "all", "mat", "fft_minus", "fft" ) ) {
        Type::host_vector<Type::real> buffer = matrix.fft_mask_minus;
        system.filehandler.outputMatrixToFile( buffer.data(), system.p.N_c, system.p.N_r, header_information, "fft_mask_minus" );
    }
}