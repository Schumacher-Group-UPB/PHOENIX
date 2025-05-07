#include <omp.h>
#include "cuda/typedef.cuh"
#include "kernel/kernel_compute.cuh"
#include "kernel/kernel_summation.cuh"
#include "kernel/kernel_halo.cuh"
#include "system/system_parameters.hpp"
#include "cuda/cuda_matrix.cuh"
#include "solver/iterator/ssprk3.cuh"
#include "solver/solver_factory.hpp"

namespace PHOENIX {

SSPRK3::SSPRK3( SystemParameters& system ) : Solver( system ) {
    k_max_ = 3;
    halo_size_ = 3;
    is_adaptive_ = false;
    name_ = "SSPRK3";
    description_ = "Strong Stability Preserving Runge Kutta 3";
    butcher_tableau_ =
        "     0.0 |  0.0     0.0     0.0    \n"
        "     1.0 |  1.0     0.0     0.0    \n"
        "     1.0 |  1.0/4.0 1.0/4.0 0.0    \n"
        "     ------------------------------\n"
        "         |  1.0/6.0 1.0/6.0 2.0/3.0";
}

void SSPRK3::step( bool variable_time_step ) {
    SOLVER_SEQUENCE( true /*Capture CUDA Graph*/,

                     CALCULATE_K( 1, Type::real( 0.0 ), wavefunction, reservoir );

                     INTERMEDIATE_SUM_K( 1, Type::real( 1.0 ) );

                     CALCULATE_K( 2, Type::real( 1.0 ), buffer_wavefunction, buffer_reservoir );

                     INTERMEDIATE_SUM_K( 2, Type::real( 1.0 / 4.0 ), Type::real( 1.0 / 4.0 ) );

                     CALCULATE_K( 3, Type::real( 1.0 ), buffer_wavefunction, buffer_reservoir );

                     FINAL_SUM_K( 3, Type::real( 1.0 / 6.0 ), Type::real( 1.0 / 6.0 ), Type::real( 2.0 / 3.0 ) );

    );
}

REGISTER_SOLVER( "SSPRK3", SSPRK3, false, "Strong Stability Preserving Runge Kutta 3" );

} // namespace PHOENIX