#include <omp.h>
#include "cuda/typedef.cuh"
#include "kernel/kernel_compute.cuh"
#include "kernel/kernel_summation.cuh"
#include "kernel/kernel_halo.cuh"
#include "system/system_parameters.hpp"
#include "cuda/cuda_matrix.cuh"
#include "solver/iterator/newton.cuh"
#include "solver/solver_factory.hpp"

namespace PHOENIX {

Newton::Newton( SystemParameters& system ) : Solver( system ) {
    k_max_ = 1;
    halo_size_ = 1;
    is_adaptive_ = false;
    name_ = "Newton";
    description_ = "Newton's method";
    butcher_tableau_ =
        "     0.0 | 0.0\n"
        "     -------------\n"
        "         | 1.0";
}
void Newton::step(bool variable_time_step) {
    SOLVER_SEQUENCE( true /*Capture CUDA Graph*/,

                     CALCULATE_K( 1, Type::real(0.0), wavefunction, reservoir );

                     FINAL_SUM_K( 1, Type::real(1.0) );

    )

    return;
}

REGISTER_SOLVER( "Newton", Newton, false, "Newton" );

} // namespace PHOENIX