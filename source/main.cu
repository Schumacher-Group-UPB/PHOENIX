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
#include <thread>
#include "cuda/typedef.cuh"
#include "system/system_parameters.hpp"
#include "system/filehandler.hpp"
#include "misc/timeit.hpp"
#include "misc/gui.hpp"
#include "misc/solver_thread.hpp"
#include "solver/solver.hpp"
#include "solver/solver_factory.hpp"

#ifdef BENCH
    #ifdef LIKWID
        #include <likwid.h>
    #endif
#endif

static void solverThreadFunc( PHOENIX::Solver& solver, PHOENIX::SystemParameters& system, PHOENIX::SolverThreadState& st, int cuda_device ) {
    // Initialize the CUDA context on this thread. Each std::thread starts with
    // no current CUDA context; cudaSetDevice() activates the primary context
    // for the given device, enabling all CUDA and thrust calls from this thread.
    cudaSetDevice( cuda_device );

    double complete_duration = 0.0;
    PHOENIX::Type::uint32 out_every_iterations = 1;

    while ( system.p.t < system.t_max && !st.stop.load() ) {
        // Block while paused
        {
            std::unique_lock<std::mutex> lk( st.pause_mutex );
            st.pause_cv.wait( lk, [&] { return !st.paused.load() || st.stop.load(); } );
        }
        if ( st.stop.load() ) break;

        TimeThis(
            auto start = system.p.t;
            bool force_fixed_time_step = false;
            bool interrupted_by_pause = false;

            while ( ( !system.disableRender && system.p.t < start + system.output_every ) ||
                    (  system.disableRender  && system.p.t < out_every_iterations * system.output_every ) ) {
                if ( st.paused.load() ) { interrupted_by_pause = true; break; }

                auto dt = system.p.dt;
                if ( system.p.t + system.p.dt > out_every_iterations * system.output_every ) {
                    auto next_dt = out_every_iterations * system.output_every - system.p.t;
                    if ( next_dt > 0 ) { system.p.dt = next_dt; force_fixed_time_step = true; }
                }
                auto result = solver.iterate( force_fixed_time_step );
                if ( force_fixed_time_step ) { force_fixed_time_step = false; system.p.dt = dt; }
                if ( !result ) break;
            }

            // Skip all post-processing when paused so the displayed time freezes
            // immediately and out_every_iterations is not advanced.
            if ( !interrupted_by_pause ) {
                out_every_iterations++;

                // GPU→CPU sync + cache under display_mutex so GUI reads consistent data
                {
                    std::lock_guard<std::mutex> lk( st.display_mutex );
                    solver.syncDisplayMatrices();
                    solver.cacheValues();
                    solver.cacheMatrices();
                }

                // Publish display scalars
                st.display_t.store( system.p.t );
                st.display_iteration.store( system.iteration );
                complete_duration = PHOENIX::TimeIt::totalRuntime();
                st.display_elapsed.store( complete_duration );
                system.printCMD( complete_duration, system.iteration );
            }
            , "Main-Loop" );
    }
}

int main( int argc, char* argv[] ) {
    // Try and read-in any config file
    auto config = PHOENIX::readConfigFromFile( argc, argv );

    // Convert input arguments to system and handler variables
    auto system = PHOENIX::SystemParameters( config.size(), config.data() );

    // Create Solver Class
    auto solver = PHOENIX::SolverFactory::create( system );
    solver->initialize();

    // Create Main Plotwindow. Needs to be compiled with -DSFML_RENDER
    auto gui_window = PHOENIX::PhoenixGUI(*solver.get());

    // Some Helper Variables
    bool running = true;
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
    // Capture the current CUDA device so the solver thread can activate the
    // same context (cudaSetDevice is required on every new std::thread).
    int cuda_device = 0;
    cudaGetDevice( &cuda_device );

    PHOENIX::SolverThreadState st;
    std::thread solver_thread( solverThreadFunc, std::ref( *solver ), std::ref( system ), std::ref( st ), cuda_device );

    while ( system.p.t < system.t_max and running ) {
        running = gui_window.update( st.display_t.load(), st.display_elapsed.load(), st.display_iteration.load(), st );
    }

    st.stop.store( true );
    st.pause_cv.notify_all();
    solver_thread.join();
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
