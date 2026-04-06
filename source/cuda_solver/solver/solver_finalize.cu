#include "solver/solver.hpp"
#include "misc/escape_sequences.hpp"
#include "misc/commandline_io.hpp"

void PHOENIX::Solver::finalize() {
#ifndef USE_CPU
    for ( auto& be : bench_events_ ) {
        if ( be.start ) cudaEventDestroy( be.start );
        if ( be.stop  ) cudaEventDestroy( be.stop );
    }
    bench_events_.clear();
#endif
    // Wait for any asynchronous I/O to complete
    std::cout << PHOENIX::CLIO::prettyPrint( "Outputting asynchronously... ", PHOENIX::CLIO::Control::Info ) << std::endl;
    filehandler.waitForCompletion();
    // Output Matrices
    outputMatrices( 0 /*start*/, system.p.N_c /*end*/, 0 /*start*/, system.p.N_r /*end*/, 1.0 /*increment*/ );
    // Cache to files
    std::cout << PHOENIX::CLIO::prettyPrint( "Caching to Files... ", PHOENIX::CLIO::Control::Info ) << std::endl;
    cacheToFiles();
}