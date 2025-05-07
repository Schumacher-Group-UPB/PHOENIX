#include <omp.h>
#include "cuda/typedef.cuh"
#include "kernel/kernel_compute.cuh"
#include "kernel/kernel_summation.cuh"
#include "kernel/kernel_halo.cuh"
#include "system/system_parameters.hpp"
#include "cuda/cuda_matrix.cuh"
#include "solver/iterator/bogacki.cuh"
#include "solver/solver_factory.hpp"

namespace PHOENIX {

BogackiShampine::BogackiShampine( SystemParameters& system ) : Solver( system ) {
    k_max_ = 4;
    halo_size_ = 4;
    is_adaptive_ = true;
    name_ = "Bogacki-Shampine 3(2)";
    description_ = "Bogacki-Shampine 3(2) method for time integration.";
    butcher_tableau_ =
        "     0.0     | 0.0     0.0     0.0      0.0    \n"
        "     1.0/2.0 | 1.0/2.0 0.0     0.0      0.0    \n"
        "     3.0/4.0 | 0.0     3.0/4.0 0.0      0.0    \n"
        "     ------------------------------------------\n"
        "             | 2.0/9.0 1.0/3.0 4.0/9.0  0.0    \n"
        "             | 7.0/24.0 1.0/4.0 1.0/3.0 1.0/8.0";
}

void BogackiShampine::step( bool variable_time_step ) {
    bool cuda_graph = !variable_time_step;
    bool accept = !variable_time_step; // If we are not using variable time step, we can accept the solution right away.

    do {
        SOLVER_SEQUENCE(
            cuda_graph /*Capture CUDA Graph*/,

            CALCULATE_K( 1, Type::real( 0.0 ), wavefunction, reservoir );

            INTERMEDIATE_SUM_K( 1, Type::real( 1.0 / 2.0 ) );

            CALCULATE_K( 2, Type::real( 1.0 / 2.0 ), buffer_wavefunction, buffer_reservoir );

            INTERMEDIATE_SUM_K( 2, Type::real( 0.0 ), Type::real( 3.0 / 9.0 ) );

            CALCULATE_K( 3, Type::real( 3.0 / 4.0 ), buffer_wavefunction, buffer_reservoir );

            if ( !variable_time_step ) { 
                
                FINAL_SUM_K( 3, Type::real( 2.0 / 9.0 ), Type::real( 1.0 / 3.0 ), Type::real( 4.0 / 9.0 ) ); 
            
            } else {
                
                INTERMEDIATE_SUM_K( 3, Type::real( 2.0 / 9.0 ), Type::real( 1.0 / 3.0 ), Type::real( 4.0 / 9.0 ) );

                // We need the 4th K for the error estimate
                CALCULATE_K( 4, Type::real( 1.0 ), buffer_wavefunction, buffer_reservoir );

                ERROR_K( 4, Type::real( 2.0 / 9.0 - 7.0 / 24.0 ), Type::real( 1.0 / 3.0 - 1.0 / 4.0 ), Type::real( 4.0 / 9.0 - 1.0 / 3.0 ), Type::real( 0.0 - 1.0 / 8.0 ) );

                // Redo this sum so we get the correct solution in buffer_...
                INTERMEDIATE_SUM_K( 3, Type::real( 2.0 / 9.0 ), Type::real( 1.0 / 3.0 ), Type::real( 4.0 / 9.0 ) );
                
            }

        );

        if ( !variable_time_step )
            return;

        accept = adaptTimeStep( 1.0 / 3.0, false );

        if ( accept ) {
            swapBuffers();
        }

    } while ( !accept );
}

REGISTER_SOLVER( "BoSha", BogackiShampine, true, "Bogacki-Shampine 3(2)" );

} // namespace PHOENIX