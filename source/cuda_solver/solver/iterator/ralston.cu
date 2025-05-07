#include <omp.h>
#include "cuda/typedef.cuh"
#include "kernel/kernel_compute.cuh"
#include "kernel/kernel_summation.cuh"
#include "kernel/kernel_halo.cuh"
#include "system/system_parameters.hpp"
#include "cuda/cuda_matrix.cuh"
#include "solver/iterator/ralston.cuh"
#include "solver/solver_factory.hpp"

namespace PHOENIX {

// MARK: Ralston
// ----------------------------------------------------------------------------------------------------- //
// ------------------------------------------- Ralston ------------------------------------------------- //
// ----------------------------------------------------------------------------------------------------- //

Ralston::Ralston( SystemParameters& system ) : Solver( system ) {
    k_max_ = 2;
    halo_size_ = 2;
    is_adaptive_ = false;
    name_ = "Ralston";
    description_ = "Ralston 2nd order method for time integration.";
    butcher_tableau_ =
        "     0.0     | 0.0     0.0    \n"
        "     2.0/3.0 | 2.0/3.0 0.0    \n"
        "     -------------------------\n"
        "             | 1.0/4.0 3.0/4.0";
}

void Ralston::step( bool variable_time_step ) {
    SOLVER_SEQUENCE( true /*Capture CUDA Graph*/,

                     CALCULATE_K( 1, Type::real( 0.0 ), wavefunction, reservoir );

                     INTERMEDIATE_SUM_K( 1, Type::real( 2.0 / 3.0 ) );

                     CALCULATE_K( 2, Type::real( 2.0 / 3.0 ), buffer_wavefunction, buffer_reservoir );

                     FINAL_SUM_K( 2, Type::real( 1.0 / 4.0 ), Type::real( 3.0 / 4.0 ) );

    );
}

REGISTER_SOLVER( "Ralston", Ralston, false, "Ralston 2nd order method for time integration." );

// MARK: Ralston3
// ----------------------------------------------------------------------------------------------------- //
// ------------------------------------------- Ralston3 ------------------------------------------------ //
// ----------------------------------------------------------------------------------------------------- //

Ralston3::Ralston3( SystemParameters& system ) : Solver( system ) {
    k_max_ = 3;
    halo_size_ = 3;
    is_adaptive_ = false;
    name_ = "Ralston 3";
    description_ = "Ralston 3rd order method for time integration.";
    butcher_tableau_ =
        "     0.0     | 0.0     0.0     0.0    \n"
        "     1.0/2.0 | 1.0/2.0 0.0     0.0    \n"
        "     3.0/4.0 | 0.0     3.0/4.0 0.0    \n"
        "     ---------------------------------\n"
        "             | 2.0/9.0 1.0/3.0 4.0/9.0";
}

void Ralston3::step( bool variable_time_step ) {
    SOLVER_SEQUENCE( true /*Capture CUDA Graph*/,

                     CALCULATE_K( 1, Type::real( 0.0 ), wavefunction, reservoir );

                     INTERMEDIATE_SUM_K( 1, Type::real( 1.0 / 2.0 ) );

                     CALCULATE_K( 2, Type::real( 1.0 / 2.0 ), buffer_wavefunction, buffer_reservoir );

                     INTERMEDIATE_SUM_K( 2, Type::real( 0.0 ), Type::real( 3.0 / 4.0 ) );

                     CALCULATE_K( 3, Type::real( 3.0 / 4.0 ), buffer_wavefunction, buffer_reservoir );

                     FINAL_SUM_K( 3, Type::real( 2.0 / 9.0 ), Type::real( 1.0 / 3.0 ), Type::real( 4.0 / 9.0 ) );

    );
}

REGISTER_SOLVER( "Ralston3", Ralston3, false, "Ralston 3rd order method for time integration." );

// MARK: Ralston4
// ----------------------------------------------------------------------------------------------------- //
// ------------------------------------------- Ralston4 ------------------------------------------------ //
// ----------------------------------------------------------------------------------------------------- //

Ralston4::Ralston4( SystemParameters& system ) : Solver( system ) {
    k_max_ = 3;
    halo_size_ = 3;
    is_adaptive_ = false;
    name_ = "Ralston 3";
    description_ = "Ralston 3rd order method for time integration.";
    butcher_tableau_ =
        "     0.0           | 0.0            0.0           0.0           0.0          \n"
        "     0.4           | 0.4            0.0           0.0           0.0          \n"
        "     0.51823725421 | 0.29697760924  0.15875964497 0.0           0.0          \n"
        "     0.51823725421 | 0.21810038822 -3.05096514869 3.83286476047 0.0          \n"
        "     ------------------------------------------------------------------------\n"
        "                   | 0.17476028226 -0.55148066287 1.2055355994  0.17118478122";
}

void Ralston4::step( bool variable_time_step ) {
    SOLVER_SEQUENCE( true /*Capture CUDA Graph*/,

                     CALCULATE_K( 1, Type::real( 0.0 ), wavefunction, reservoir );

                     INTERMEDIATE_SUM_K( 1, Type::real( 0.4 ) );

                     CALCULATE_K( 2, Type::real( 0.4 ), buffer_wavefunction, buffer_reservoir );

                     INTERMEDIATE_SUM_K( 2, Type::real( 0.29697760924 ), Type::real( 0.15875964497 ) );

                     CALCULATE_K( 3, Type::real( 0.51823725421 ), buffer_wavefunction, buffer_reservoir );

                     INTERMEDIATE_SUM_K( 3, Type::real( 0.21810038822 ), Type::real( -3.05096514869 ), Type::real( 3.83286476047 ) );

                     CALCULATE_K( 4, Type::real( 0.51823725421 ), buffer_wavefunction, buffer_reservoir );

                     FINAL_SUM_K( 4, Type::real( 0.17476028226 ), Type::real( -0.55148066287 ), Type::real( 1.2055355994 ), Type::real( 0.17118478122 ) );

    );
}

REGISTER_SOLVER( "Ralston4", Ralston4, false, "Ralston 4th order method for time integration." );

} // namespace PHOENIX