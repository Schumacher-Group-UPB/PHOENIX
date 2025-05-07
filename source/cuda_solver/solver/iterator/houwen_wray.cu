#include <omp.h>
#include "cuda/typedef.cuh"
#include "kernel/kernel_compute.cuh"
#include "kernel/kernel_summation.cuh"
#include "kernel/kernel_halo.cuh"
#include "system/system_parameters.hpp"
#include "cuda/cuda_matrix.cuh"
#include "solver/iterator/houwen_wray.cuh"
#include "solver/solver_factory.hpp"

namespace PHOENIX {

HouwenWray::HouwenWray( SystemParameters& system ) : Solver( system ) {
    k_max_ = 3;
    halo_size_ = 3;
    is_adaptive_ = false;
    name_ = "HouwenWray";
    description_ = "Van der Houwen's/Wray's third-order method";
    butcher_tableau_ =
        "     0.0      | 0.0      0.0      0.0    \n"
        "     8.0/15.0 | 8.0/15.0 0.0      0.0    \n"
        "     2.0/3.0  | 1.0/4.0  5.0/12.0 0.0    \n"
        "     ------------------------------------\n"
        "     0.0      | 1.0/4.0  0.0      3.0/4.0";
}

void HouwenWray::step(bool variable_time_step) {
    SOLVER_SEQUENCE( true /*Capture CUDA Graph*/,

                     CALCULATE_K( 1, Type::real(0.0), wavefunction, reservoir );

                     INTERMEDIATE_SUM_K( 1, Type::real(8.0/15.0) );

                     CALCULATE_K( 2, Type::real(8.0/15.0), buffer_wavefunction, buffer_reservoir );

                     INTERMEDIATE_SUM_K( 2, Type::real(1.0/4.0), Type::real(5.0/12.0) );

                     CALCULATE_K( 3, Type::real(2.0/3.0), buffer_wavefunction, buffer_reservoir );

                     FINAL_SUM_K( 3, Type::real(1.0/4.0), Type::real(0.0), Type::real(3.0/4.0) );

    );
}

REGISTER_SOLVER( "HW", HouwenWray, false, "Houwen-Wray" );

} // namespace PHOENIX