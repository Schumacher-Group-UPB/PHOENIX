#include <omp.h>
#include "cuda/typedef.cuh"
#include "kernel/kernel_compute.cuh"
#include "kernel/kernel_summation.cuh"
#include "kernel/kernel_halo.cuh"
#include "system/system_parameters.hpp"
#include "cuda/cuda_matrix.cuh"
#include "solver/iterator/fehlberg.cuh"
#include "solver/solver_factory.hpp"

namespace PHOENIX {

// MARK: Fehlberg2
// ----------------------------------------------------------------------------------------------------- //
// ------------------------------------------ Fehlberg2 ------------------------------------------------ //
// ----------------------------------------------------------------------------------------------------- //

Fehlberg2::Fehlberg2( SystemParameters& system ) : Solver( system ) {
    k_max_ = 3;
    halo_size_ = 3;
    is_adaptive_ = true;
    name_ = "Fehlberg 2(1)";
    description_ = "Fehlberg 2(1) order method for time integration.";
    butcher_tableau_ =
        "     0.0     | 0.0     0.0         0.0\n"
        "     1.0/2.0 | 1.0/2.0 0.0         0.0\n"
        "     1.0     | 1.0/256 255.0/256.0 0.0\n"
        "     ---------------------------------------\n"
        "             | 1.0/512 255.0/256   1.0/512.0\n"
        "             | 1.0/256 255.0/256   0.0      ";
}

void Fehlberg2::step( bool variable_time_step ) {
    bool cuda_graph = !variable_time_step;
    bool accept = !variable_time_step; // If we are not using variable time step, we can accept the solution right away.

    do {
        SOLVER_SEQUENCE(
            cuda_graph /*Capture CUDA Graph*/,

            CALCULATE_K( 1, Type::real( 0.0 ), wavefunction, reservoir );

            INTERMEDIATE_SUM_K( 1, Type::real( 1.0 / 2.0 ) );

            CALCULATE_K( 2, Type::real( 1.0 / 2.0 ), buffer_wavefunction, buffer_reservoir );

            INTERMEDIATE_SUM_K( 2, Type::real( 1.0 / 256.0 ), Type::real( 255.0 / 256.0 ) );

            CALCULATE_K( 3, Type::real( 1.0 ), buffer_wavefunction, buffer_reservoir );

            if ( !variable_time_step ) { 
                
                FINAL_SUM_K( 3, Type::real( 1.0 / 512.0 ), Type::real( 255.0 / 256.0 ), Type::real( 1.0 / 512.0 ) ); 
            
            } else {
                
                INTERMEDIATE_SUM_K( 3, Type::real( 1.0 / 512.0 ), Type::real( 255.0 / 256.0 ), Type::real( 1.0 / 512.0 ) );

                ERROR_K( 3, Type::real( 1.0 / 512.0 - 1.0 / 256.0 ), Type::real( 0.0 ), Type::real( 1.0 / 512.0 ) );
            } 
        );

        if ( !variable_time_step )
            return;

        accept = adaptTimeStep( 1.0 / 4.0, false );

        if ( accept ) {
            swapBuffers();
        }

    } while ( !accept );
}

REGISTER_SOLVER( "Fehlberg2", Fehlberg2, true, "Fehlberg 2(1) order method for time integration." );

// MARK: Fehlberg5
// ----------------------------------------------------------------------------------------------------- //
// ------------------------------------------ Fehlberg5 ------------------------------------------------ //
// ----------------------------------------------------------------------------------------------------- //

Fehlberg5::Fehlberg5( SystemParameters& system ) : Solver( system ) {
    k_max_ = 6;
    halo_size_ = 6;
    is_adaptive_ = true;
    name_ = "Fehlberg 2(1)";
    description_ = "Fehlberg 2(1) order method for time integration.";
    butcher_tableau_ =
        "     0.0      |  0.0          0.0            0.0            0.0           0.0       0.0     \n"
        "     1.0/4.0  |  1.0/4.0      0.0            0.0            0.0           0.0       0.0     \n"
        "     3.0/8.0  |  3.0/32.0     9.0/32.0       0.0            0.0           0.0       0.0     \n"
        "     12./13   |  1932.0/2197 -7200.0/2197.0 -7296.0/2197.0  0.0           0.0       0.0     \n"
        "     1.0      |  439.0/216.0 -8.0            3680.0/513.0  -845./4104.0   0.0       0.0     \n"
        "     1.0/2.0  | -8.0/27.0     2.0           -3544.0/2565.0  1859./4104.0 -11.0/40.0 0.0     \n"
        "     ---------------------------------------------------------------------------------------\n"
        "              |  16.0/135.0   0.0            6656./12825    28561./56430 -9.0/50.0  2.0/55.0\n"
        "              |  25.0/216.0   0.0            1408./2565.0   2197./4104.0 -1.0/5.0   0.0     ";
}

void Fehlberg5::step( bool variable_time_step ) {
    bool cuda_graph = !variable_time_step;
    bool accept = !variable_time_step; // If we are not using variable time step, we can accept the solution right away.

    do {
        SOLVER_SEQUENCE(
            cuda_graph /*Capture CUDA Graph*/,

            CALCULATE_K( 1, Type::real( 0.0 ), wavefunction, reservoir );

            INTERMEDIATE_SUM_K( 1, Type::real( 1.0 / 4.0 ) );

            CALCULATE_K( 2, Type::real( 1.0 / 4.0 ), buffer_wavefunction, buffer_reservoir );

            INTERMEDIATE_SUM_K( 2, Type::real( 3.0 / 32.0 ), Type::real( 9.0 / 32.0 ) );

            CALCULATE_K( 3, Type::real( 3.0 / 8.0 ), buffer_wavefunction, buffer_reservoir );

            INTERMEDIATE_SUM_K( 3, Type::real( 1932.0 / 2197.0 ), Type::real( -7200.0 / 2197.0 ), Type::real( 7296.0 / 2197.0 ) );

            CALCULATE_K( 4, Type::real( 12.0 / 13.0 ), buffer_wavefunction, buffer_reservoir );

            INTERMEDIATE_SUM_K( 4, Type::real( 439.0 / 216.0 ), Type::real( -8.0 ), Type::real( 3680.0 / 513.0 ), Type::real( -845.0 / 4104.0 ) );

            CALCULATE_K( 5, Type::real( 1.0 ), buffer_wavefunction, buffer_reservoir );

            INTERMEDIATE_SUM_K( 5, Type::real( -8.0 / 27.0 ), Type::real( 2.0 ), Type::real( -3544.0 / 2565.0 ), Type::real( 1859.0 / 4104.0 ), Type::real( -11.0 / 40.0 ) );

            CALCULATE_K( 6, Type::real( 1.0 / 2.0 ), buffer_wavefunction, buffer_reservoir );

            if ( !variable_time_step ) { 
                
                FINAL_SUM_K( 6, Type::real( 16.0 / 135.0 ), Type::real( 0.0 ), Type::real( 6656.0 / 12825.0 ), Type::real( 28561.0 / 56430.0 ), Type::real( -9.0 / 50.0 ), Type::real( 2.0 / 55.0 ) ); 
            
            } else {
                
                INTERMEDIATE_SUM_K( 6, Type::real( 16.0 / 135.0 ), Type::real( 0.0 ), Type::real( 6656.0 / 12825.0 ), Type::real( 28561.0 / 56430.0 ), Type::real( -9.0 / 50.0 ), Type::real( 2.0 / 55.0 ) );

                ERROR_K( 6, Type::real( 16.0 / 135.0 - 25.0 / 216.0 ), Type::real( 0.0 ), Type::real( 6656.0 / 12825.0 - 1408.0 / 2565.0 ), Type::real( 28561.0 / 56430.0 - 2197.0 / 4104.0 ), Type::real( -9.0 / 50.0 - 1.0 / 5.0 ), Type::real( 2.0 / 55.0 ) );
            }

        );

        if ( !variable_time_step )
            return;

        accept = adaptTimeStep( 1.0 / 4.0, false );

        if ( accept ) {
            swapBuffers();
        }

    } while ( !accept );
}

REGISTER_SOLVER( "Fehlberg5", Fehlberg5, true, "Fehlberg 5(4) order method for time integration." );

} // namespace PHOENIX