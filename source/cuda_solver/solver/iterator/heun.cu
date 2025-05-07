#include <omp.h>
#include "cuda/typedef.cuh"
#include "kernel/kernel_compute.cuh"
#include "kernel/kernel_summation.cuh"
#include "kernel/kernel_halo.cuh"
#include "system/system_parameters.hpp"
#include "cuda/cuda_matrix.cuh"
#include "solver/iterator/heun.cuh"
#include "solver/solver_factory.hpp"

namespace PHOENIX {

// MARK: Heun2
// ----------------------------------------------------------------------------------------------------- //
// ------------------------------------------ Heun2 ---------------------------------------------------- //
// ----------------------------------------------------------------------------------------------------- //

Heun2::Heun2( SystemParameters& system ) : Solver( system ) {
    k_max_ = 2;
    halo_size_ = 2;
    is_adaptive_ = false;
    name_ = "Heun2";
    description_ = "Heun's";
    butcher_tableau_ =
        "     0.0 | 0.0 0.0\n"
        "     1.0 | 1.0 0.0\n"
        "     -------------\n"
        "         | 0.5 0.5";
}

void Heun2::step( bool variable_time_step ) {
    SOLVER_SEQUENCE( true /*Capture CUDA Graph*/,

                     CALCULATE_K( 1, Type::real( 0.0 ), wavefunction, reservoir );

                     INTERMEDIATE_SUM_K( 1, Type::real( 1.0 ) );

                     CALCULATE_K( 2, Type::real( 1.0 ), buffer_wavefunction, buffer_reservoir );

                     FINAL_SUM_K( 3, Type::real( 0.5 ), Type::real( 0.5 ) );

    );
}

REGISTER_SOLVER( "Heun2", Heun2, false, "Heun2" );

// MARK: Heun3
// ----------------------------------------------------------------------------------------------------- //
// ------------------------------------------ Heun3 ---------------------------------------------------- //
// ----------------------------------------------------------------------------------------------------- //

Heun3::Heun3( SystemParameters& system ) : Solver( system ) {
    k_max_ = 3;
    halo_size_ = 3;
    is_adaptive_ = false;
    name_ = "Heun3";
    description_ = "Heun's third-order method";
    butcher_tableau_ =
        "     0.0     | 0.0     0.0     0.0\n"
        "     1.0/3.0 | 1.0/3.0 0.0     0.0\n"
        "     2.0/3.0 | 0.0     2.0/3.0 0.0\n"
        "     -----------------------------\n"
        "             | 1.0/4.0 0.0 3.0/4.0";
}

void Heun3::step( bool variable_time_step ) {
    SOLVER_SEQUENCE( true /*Capture CUDA Graph*/,

                     CALCULATE_K( 1, Type::real( 0.0 ), wavefunction, reservoir );

                     INTERMEDIATE_SUM_K( 1, Type::real( 1.0 / 3.0 ) );

                     CALCULATE_K( 2, Type::real( 1.0 / 3.0 ), buffer_wavefunction, buffer_reservoir );

                     INTERMEDIATE_SUM_K( 2, Type::real( 0.0 ), Type::real( 2.0 / 3.0 ) );

                     CALCULATE_K( 3, Type::real( 2.0 / 3.0 ), buffer_wavefunction, buffer_reservoir );

                     FINAL_SUM_K( 3, Type::real( 1.0 / 4.0 ), Type::real( 0.0 ), Type::real( 3.0 / 4.0 ) );

    );
}

REGISTER_SOLVER( "Heun3", Heun3, false, "Heun3" );

} // namespace PHOENIX