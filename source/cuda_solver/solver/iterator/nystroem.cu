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

Nystroem::Nystroem( SystemParameters& system ) : Solver( system ) {
    k_max_ = 6;
    halo_size_ = 6;
    is_adaptive_ = false;
    name_ = "Nystroem";
    description_ = "Nystroem's fifth-order method";
    butcher_tableau_ =
        "     0.0     | 0.0        0.0       0.0         0.0      0.0       0.0        \n"
        "     1.0/3.0 | 1.0/3.0    0.0       0.0         0.0      0.0       0.0        \n"
        "     2.0/5.0 | 4.0/25.0   6.0/25.0  0.0         0.0      0.0       0.0        \n"
        "     1.0     | 1.0/4.0   -3.0       15.0/4.0    0.0      0.0       0.0        \n"
        "     2.0/3.0 | 2.0/27.0   10.0/9.0 -50.0/81.0   8.0/81.0 0.0       0.0        \n"
        "     4.0/5.0 | 2.0/25.0   12.0/25.0 2.0/15.0    8.0/75.0 0.0       0.0        \n"
        "     -------------------------------------------------------------------------\n"
        "             | 23.0/192.0 0.0       125.0/192.0 0.0     -27.0/64.0 125.0/192.0";
}

void Nystroem::step( bool variable_time_step ) {
    SOLVER_SEQUENCE( true /*Capture CUDA Graph*/,

                     CALCULATE_K( 1, Type::real(0.0), wavefunction, reservoir );

                     INTERMEDIATE_SUM_K( 1, Type::real( 1.0 / 3.0 ) );

                     CALCULATE_K( 2, Type::real(1.0/3.0), buffer_wavefunction, buffer_reservoir );

                     INTERMEDIATE_SUM_K( 2, Type::real( 4.0 / 25.0 ), Type::real( 6.0 / 25.0 ) );

                     CALCULATE_K( 3, Type::real(2.0/5.0), buffer_wavefunction, buffer_reservoir );

                     INTERMEDIATE_SUM_K( 3, Type::real( 1.0 / 4.0 ), Type::real( -3.0 ), Type::real( 15.0 / 4.0 ) );

                     CALCULATE_K( 4, Type::real(1.0), buffer_wavefunction, buffer_reservoir );

                     INTERMEDIATE_SUM_K( 4, Type::real( 2.0 / 27.0 ), Type::real( 10.0 / 9.0 ), -Type::real( 50.0 / 81.0 ), Type::real( 8.0 / 81.0 ) );

                     CALCULATE_K( 5, Type::real(2.0/3.0), buffer_wavefunction, buffer_reservoir );

                     INTERMEDIATE_SUM_K( 5, Type::real( 2.0 / 25.0 ), Type::real( 12.0 / 25.0 ), Type::real( 2.0 / 15.0 ), Type::real( 8.0 / 75.0 ) );

                     CALCULATE_K( 6, Type::real(4.0/5.0), buffer_wavefunction, buffer_reservoir );

                     FINAL_SUM_K( 6, Type::real( 23.0 / 192.0 ), Type::real( 0.0 ), Type::real( 125.0 / 192.0 ), Type::real( 0.0 ), -Type::real( 27.0 / 64.0 ), Type::real( 125.0 / 192.0 ) );

    );
}

REGISTER_SOLVER( "Nystroem", Nystroem, false, "Nystroem's fifth-order method" );

} // namespace PHOENIX
