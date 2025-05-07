/*
 * MIT License
 * Copyright (c) 2025 Workgroup of Prof. Dr. Stefan Schumacher, University of Paderborn
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS," WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

#include <cmath>
#include <iostream>
#include <fstream>
#include <complex>
#include <vector>
#include <cstdlib>
#include <omp.h>
#include <chrono>
#include "cuda/typedef.cuh"
#include "system/system_parameters.hpp"
#include "system/filehandler.hpp"
#include "misc/timeit.hpp"
#include "misc/sfml_helper.hpp"
#include "solver/solver.hpp"
#include "solver/solver_factory.hpp"

#ifdef BENCH
    #ifdef LIKWID
        #include <likwid.h>
    #endif
#endif

int main( int argc, char* argv[] ) {
    // Try and read-in any config file
    auto config = PHOENIX::readConfigFromFile( argc, argv );

    // Convert input arguments to system and handler variables
    auto system = PHOENIX::SystemParameters( config.size(), config.data() );

    // Create Solver Class
    auto solver = PHOENIX::SolverFactory::create( system );
    solver->initialize();

    // Create Main Plotwindow. Needs to be compiled with -DSFML_RENDER
    initSFMLWindow( *solver.get() );

    // Some Helper Variables
    bool running = true;
    double complete_duration = 0.;
    PHOENIX::Type::uint32 out_every_iterations = 1;
    // Main Loop
#ifdef BENCH
    #ifdef LIKWID
    LIKWID_MARKER_INIT;
        #pragma omp parallel
    { LIKWID_MARKER_START( "iterator" ); }
    #endif
    double tstart = omp_get_wtime();
    TimeThis( while ( omp_get_wtime() - tstart <= BENCH_TIME ) { solver->iterate(); }, "Main-Loop" );
    complete_duration = PHOENIX::TimeIt::totalRuntime();
    system.printCMD( complete_duration, system.iteration );
    #ifdef LIKWID
        #pragma omp parallel
    { LIKWID_MARKER_STOP( "iterator" ); }
    #endif
#else
    while ( system.p.t < system.t_max and running ) {
        TimeThis(
            // Iterate #output_every ps
            auto start = system.p.t; 
            bool force_fixed_time_step = false; 
            
            while ( ( not system.disableRender and system.p.t < start + system.output_every ) or ( system.disableRender and system.p.t < out_every_iterations * system.output_every ) ) {
                // Check if t+dt would overshoot out_every_iterations*output_every, adjust dt accordingly
                auto dt = system.p.dt;
                if ( system.p.t + system.p.dt > out_every_iterations * system.output_every ) {
                    auto next_dt = out_every_iterations * system.output_every - system.p.t;
                    if ( next_dt > 0 ) {
                        system.p.dt = next_dt;
                        force_fixed_time_step = true;
                    }
                }
                auto result = solver->iterate( force_fixed_time_step );

                if ( force_fixed_time_step ) {
                    force_fixed_time_step = false;
                    system.p.dt = dt;
                }
                
                if ( !result ) {
                    break;
                }

            } out_every_iterations++;
            // Cache the history and max values
            solver->cacheValues();
            // Output Matrices if enabled
            solver->cacheMatrices();
            // Plot
            running = plotSFMLWindow( *solver.get(), system.p.t, complete_duration, system.iteration );
            , "Main-Loop" );
        complete_duration = PHOENIX::TimeIt::totalRuntime();
        system.printCMD( complete_duration, system.iteration );
    }
#endif

    system.finishCMD();

    // Fileoutput
    solver->finalize();

    // Print Time statistics and output to file
    system.printSummary( PHOENIX::TimeIt::getTimes(), PHOENIX::TimeIt::getTimesTotal() );
    PHOENIX::TimeIt::toFile( system.filehandler.getFile( "times", "txt" ) );
#ifdef BENCH
    #ifdef LIKWID
    LIKWID_MARKER_CLOSE;
    #endif
#endif

    return 0;
}
