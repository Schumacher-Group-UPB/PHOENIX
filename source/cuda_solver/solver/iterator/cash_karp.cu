#include <omp.h>
#include "cuda/typedef.cuh"
#include "kernel/kernel_compute.cuh"
#include "kernel/kernel_summation.cuh"
#include "kernel/kernel_halo.cuh"
#include "system/system_parameters.hpp"
#include "cuda/cuda_matrix.cuh"
#include "solver/iterator/cash_karp.cuh"
#include "solver/solver_factory.hpp"

namespace PHOENIX {

CashKarp::CashKarp( SystemParameters& system ) : Solver( system ) {
    k_max_ = 6;
    halo_size_ = 6;
    is_adaptive_ = true;
    name_ = "Cash-Karp 5(4)";
    description_ = "Cash-Karp 5(4) order method for time integration.";
    butcher_tableau_ =
        "     0.0      | 0.0          0.0         0.0          0.0            0.0         0.0   \n"
        "     1.0/5.0  | 1.0/5.0      0.0         0.0          0.0            0.0         0.0   \n"
        "     3.0/10.0 | 3.0/40.0     9.0/40.0    0.0          0.0            0.0         0.0   \n"
        "     3.0/5.0  | 3.0/10.0    -9.0/10.0    6.0/5.0      0.0            0.0         0.0   \n"
        "     1.0      | -11.0/54.0   5.0/2.0    -70.0/27.0    35.0/27.0      0.0         0.0   \n"
        "     7.0/8.0  | 1631./55296  175./512    575./13824   44275./110592  253./4096   0.0   \n"
        "     ----------------------------------------------------------------------------------\n"
        "              | 37.0/378     0.0         250./621     125./594       -11./84     0.0   \n"
        "              | 2825./27648  0.0         18575./48384 135./384       -2187./6784 11./84";
}

void CashKarp::step( bool variable_time_step ) {
    bool cuda_graph = !variable_time_step;
    bool accept = !variable_time_step; // If we are not using variable time step, we can accept the solution right away.

    do {
        SOLVER_SEQUENCE(
            cuda_graph /*Capture CUDA Graph*/,

            CALCULATE_K( 1, Type::real( 0.0 ), wavefunction, reservoir );

            INTERMEDIATE_SUM_K( 1, Type::real( 1.0 / 5.0 ) );

            CALCULATE_K( 2, Type::real( 1.0 / 5.0 ), buffer_wavefunction, buffer_reservoir );

            INTERMEDIATE_SUM_K( 2, Type::real( 3.0 / 40.0 ), Type::real( 9.0 / 40.0 ) );

            CALCULATE_K( 3, Type::real( 3.0 / 10.0 ), buffer_wavefunction, buffer_reservoir );

            INTERMEDIATE_SUM_K( 3, Type::real( 3.0 / 1.0 ), Type::real( -9.0 / 10.0 ), Type::real( 6.0 / 5.0 ) );

            CALCULATE_K( 4, Type::real( 3.0 / 5.0 ), buffer_wavefunction, buffer_reservoir );

            INTERMEDIATE_SUM_K( 4, Type::real( -11.0 / 54.0 ), Type::real( 5.0 / 2.0 ), Type::real( -70.0 / 27.0 ), Type::real( 35.0 / 27.0 ) );

            CALCULATE_K( 5, Type::real( 1.0 ), buffer_wavefunction, buffer_reservoir );

            INTERMEDIATE_SUM_K( 5, Type::real( 1631.0 / 55296.0 ), Type::real( 175.0 / 512.0 ), Type::real( 575.0 / 13824.0 ), Type::real( 44275.0 / 110592.0 ), Type::real( 253.0 / 4096.0 ) );

            CALCULATE_K( 6, Type::real( 7.0 / 8.0 ), buffer_wavefunction, buffer_reservoir );

            if ( !variable_time_step ) { 

                FINAL_SUM_K( 6, Type::real( 37.0 / 378.0 ), Type::real( 0.0 ), Type::real( 250.0 / 621.0 ), Type::real( 125.0 / 594.0 ), Type::real( 0.0 ), Type::real( 512.0 / 1771.0 ) ); 
            
            } else {

                INTERMEDIATE_SUM_K( 6, Type::real( 37.0 / 378.0 ), Type::real( 0.0 ), Type::real( 250.0 / 621.0 ), Type::real( 125.0 / 594.0 ), Type::real( 0.0 ), Type::real( 512.0 / 1771.0 ) );
               
                ERROR_K( 6, Type::real( 37.0 / 378.0 - 2825.0 / 27648.0 ), Type::real( 0.0 ), Type::real( 250.0 / 621.0 - 18575.0 / 48384.0 ), Type::real( 125.0 / 594.0 - 13525.0 / 55296.0 ), Type::real( 0.0 - 2187.0 / 6784.0 ), Type::real( 512.0 / 1771.0 - 1.0 / 4.0 ) );
           
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

REGISTER_SOLVER( "CashKarp", CashKarp, true, "Cash-Karp 5(4)" );

} // namespace PHOENIX