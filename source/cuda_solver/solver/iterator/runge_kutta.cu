#include <omp.h>
#include "cuda/typedef.cuh"
#include "kernel/kernel_compute.cuh"
#include "kernel/kernel_summation.cuh"
#include "kernel/kernel_halo.cuh"
#include "system/system_parameters.hpp"
#include "cuda/cuda_matrix.cuh"
#include "solver/iterator/runge_kutta.cuh"
#include "solver/solver_factory.hpp"

namespace PHOENIX {

// MARK: RK4
// ------------------------------------------------------------------------------------------------------- //
// ------------------------------------------ Runge Kutta 3 ---------------------------------------------- //
// ------------------------------------------------------------------------------------------------------- //

RungeKutta3::RungeKutta3( SystemParameters& system ) : Solver( system ) {
    k_max_ = 3;
    halo_size_ = 3;
    is_adaptive_ = false;
    name_ = "Runge-Kutta 3";
    description_ = "Runge-Kutta 3th order method for time integration.";
    butcher_tableau_ =

        "     0.0     |  0.0     0.0     0.0    \n"
        "     1.0/2.0 |  1.0/2.0 0.0     0.0    \n"
        "     1.0     | -1.0     2.0     0.0    \n"
        "     ----------------------------------\n"
        "             |  1.0/6.0 2.0/3.0 1.0/6.0";
}

void RungeKutta3::step( bool variable_time_step ) {
    SOLVER_SEQUENCE( true /*Capture CUDA Graph*/,

                     CALCULATE_K( 1, Type::real( 0.0 ), wavefunction, reservoir );

                     INTERMEDIATE_SUM_K( 1, Type::real( 0.5 ) );

                     CALCULATE_K( 2, Type::real( 1.0 / 2.0 ), buffer_wavefunction, buffer_reservoir );

                     INTERMEDIATE_SUM_K( 2, Type::real( -1.0 ), Type::real( 2.0 ) );

                     CALCULATE_K( 3, Type::real( 1.0 ), buffer_wavefunction, buffer_reservoir );

                     FINAL_SUM_K( 3, Type::real( 1.0 / 6.0 ), Type::real( 2.0 / 3.0 ), Type::real( 1.0 / 6.0 ), Type::real( 1.0 / 6.0 ) );

    );
}

REGISTER_SOLVER( "RK3", RungeKutta3, false, "Runge-Kutta 3" );

// MARK: RK4
// ------------------------------------------------------------------------------------------------------- //
// ------------------------------------------ Runge Kutta 4 ---------------------------------------------- //
// ------------------------------------------------------------------------------------------------------- //

RungeKutta4::RungeKutta4( SystemParameters& system ) : Solver( system ) {
    k_max_ = 4;
    halo_size_ = 4;
    is_adaptive_ = false;
    name_ = "Runge-Kutta 4";
    description_ = "Runge-Kutta 4th order method for time integration.";
    butcher_tableau_ =

        "     0.0 | 0.0     0.0     0.0     0.0    \n"
        "     0.5 | 0.5     0.0     0.0     0.0    \n"
        "     0.5 | 0.0     0.5     0.0     0.0    \n"
        "     1.0 | 0.0     0.0     1.0     0.0    \n"
        "     -------------------------------------\n"
        "     0.0 | 1.0/6.0 1.0/3.0 1.0/3.0 1.0/6.0";
}

void RungeKutta4::step( bool variable_time_step ) {
    SOLVER_SEQUENCE( true /*Capture CUDA Graph*/,

                     CALCULATE_K( 1, Type::real( 0.0 ), wavefunction, reservoir );

                     INTERMEDIATE_SUM_K( 1, Type::real( 0.5 ) );

                     CALCULATE_K( 2, Type::real( 0.5 ), buffer_wavefunction, buffer_reservoir );

                     INTERMEDIATE_SUM_K( 2, Type::real( 0.5 ) );

                     CALCULATE_K( 3, Type::real( 0.5 ), buffer_wavefunction, buffer_reservoir );

                     INTERMEDIATE_SUM_K( 3, Type::real( 1.0 ) );

                     CALCULATE_K( 4, Type::real( 1.0 ), buffer_wavefunction, buffer_reservoir );

                     FINAL_SUM_K( 4, Type::real( 1.0 / 6.0 ), Type::real( 1.0 / 3.0 ), Type::real( 1.0 / 3.0 ), Type::real( 1.0 / 6.0 ) );

    );
}

REGISTER_SOLVER( "RK4", RungeKutta4, false, "Runge-Kutta 4" );

} // namespace PHOENIX