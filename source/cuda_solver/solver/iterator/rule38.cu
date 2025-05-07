#include <omp.h>
#include "cuda/typedef.cuh"
#include "kernel/kernel_compute.cuh"
#include "kernel/kernel_summation.cuh"
#include "kernel/kernel_halo.cuh"
#include "system/system_parameters.hpp"
#include "cuda/cuda_matrix.cuh"
#include "solver/iterator/rule38.cuh"
#include "solver/solver_factory.hpp"

namespace PHOENIX {

Rule38::Rule38( SystemParameters& system ) : Solver( system ) {
    k_max_ = 4;
    halo_size_ = 4;
    is_adaptive_ = false;
    name_ = "Rule38";
    description_ = "Third-order Runge-Kutta method (3/8 rule)";
    butcher_tableau_ =
        "     0.0     |  0.0      0.0 0.0  0.0 \n"
        "     1.0/3.0 |  1.0/3.0  0.0 0.0  0.0 \n"
        "     2.0/3.0 | -1.0/3.0  1.0 0.0  0.0 \n"
        "     1.0     |  1.0     -1.0 1.0  0.0 \n"
        "     ---------------------------------\n"
        "             |  1/8      3/8 3/8  1/8";
}

void Rule38::step( bool variable_time_step ) {

    SOLVER_SEQUENCE( true /*Capture CUDA Graph*/,

                     CALCULATE_K( 1, Type::real( 0.0 ), wavefunction, reservoir );

                     INTERMEDIATE_SUM_K( 1, Type::real( 1.0 / 3.0 ) );

                     CALCULATE_K( 2, Type::real( 1.0 / 3.0 ), buffer_wavefunction, buffer_reservoir );

                     INTERMEDIATE_SUM_K( 2, Type::real( -1.0 / 3.0 ), Type::real( 1.0 ) );

                     CALCULATE_K( 3, Type::real( 2.0 / 3.0 ), buffer_wavefunction, buffer_reservoir );

                     INTERMEDIATE_SUM_K( 3, Type::real( 1.0 ), Type::real( -1.0 ), Type::real( 1.0 ) );

                     CALCULATE_K( 4, Type::real(1.0), buffer_wavefunction, buffer_reservoir );

                     FINAL_SUM_K( 4, Type::real( 1.0 / 8.0 ), Type::real( 3.0 / 8.0 ), Type::real( 3.0 / 8.0 ), Type::real( 1.0 / 8.0 ) );

    );
}

REGISTER_SOLVER( "Rule38", Rule38, false, "Third-order Runge-Kutta method (3/8 rule)" );

} // namespace PHOENIX
