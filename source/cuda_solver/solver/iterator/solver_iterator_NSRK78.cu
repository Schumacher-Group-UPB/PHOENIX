#pragma once
#include <cmath>
#include <omp.h>

// Include Cuda Kernel headers
#include "cuda/typedef.cuh"
#include "kernel/kernel_compute.cuh"
#include "kernel/kernel_summation.cuh"
#include "kernel/kernel_halo.cuh"
#include "system/system_parameters.hpp"
#include "cuda/cuda_matrix.cuh"
#include "solver/gpu_solver.hpp"
#include "misc/commandline_io.hpp"

void PHOENIX::Solver::iterateFixedTimestepNSRK78() {
    SOLVER_SEQUENCE( true /* capture CUDA graph */,

                     CALCULATE_K( 1, Type::real( 0.0 ), wavefunction, reservoir );

                     INTERMEDIATE_SUM_K( 1, Type::real( 1.0 / 1000.0 ) );

                     CALCULATE_K( 2, Type::real( 0.001 ), buffer_wavefunction, buffer_reservoir );

                     INTERMEDIATE_SUM_K( 2, Type::real( -491.0 / 81.0 ), Type::real( 500.0 / 81.0 ) );

                     CALCULATE_K( 3, Type::real( 0.1111111111 ), buffer_wavefunction, buffer_reservoir );

                     INTERMEDIATE_SUM_K( 3, Type::real( 1.0 / 24.0 ), Type::real( 0.0 ), Type::real( 1.0 / 8.0 ) );

                     CALCULATE_K( 4, Type::real( 0.1666666667 ), buffer_wavefunction, buffer_reservoir );

                     INTERMEDIATE_SUM_K( 4, Type::real( 5.0 / 12.0 ), Type::real( 0.0 ), Type::real( -25.0 / 16.0 ), Type::real( 25.0 / 16.0 ) );

                     CALCULATE_K( 5, Type::real( 0.4166666667 ), buffer_wavefunction, buffer_reservoir );

                     INTERMEDIATE_SUM_K( 5, Type::real( 1.0 / 20.0 ), Type::real( 0.0 ), Type::real( 0.0 ), Type::real( 1.0 / 4.0 ), Type::real( 1.0 / 5.0 ) );

                     CALCULATE_K( 6, Type::real( 0.5 ), buffer_wavefunction, buffer_reservoir );

                     INTERMEDIATE_SUM_K( 6, Type::real( -43.0 / 180.0 ), Type::real( 0.0 ), Type::real( 0.0 ), Type::real( 127.0 / 108.0 ), Type::real( -329.0 / 135.0 ), Type::real( 7.0 / 3.0 ) );

                     CALCULATE_K( 7, Type::real( 0.8333333333 ), buffer_wavefunction, buffer_reservoir );

                     INTERMEDIATE_SUM_K( 7, Type::real( 27931.0 / 240300.0 ), Type::real( 0.0 ), Type::real( 0.0 ), Type::real( -631.0 / 16020.0 ), Type::real( 2459.0 / 6675.0 ), Type::real( -3572.0 / 12015.0 ), Type::real( 5.0 / 267.0 ) );

                     CALCULATE_K( 8, Type::real( 0.1666666667 ), buffer_wavefunction, buffer_reservoir );

                     INTERMEDIATE_SUM_K( 8, Type::real( 26114.0 / 12015.0 ), Type::real( 0.0 ), Type::real( 0.0 ), Type::real( -7480.0 / 801.0 ), Type::real( 67264.0 / 4005.0 ), Type::real( -30640.0 / 2403.0 ), Type::real( 1051.0 / 1335.0 ), Type::real( 3.0 ) );

                     CALCULATE_K( 9, Type::real( 0.6666666667 ), buffer_wavefunction, buffer_reservoir );

                     INTERMEDIATE_SUM_K( 9, Type::real( 33096587331.0 / 17382812500.0 ), Type::real( 0.0 ), Type::real( 0.0 ), Type::real( -1828977848.0 / 173828125.0 ), Type::real( 62801809904.0 / 4345703125.0 ), Type::real( -9389764774.0 / 869140625.0 ), Type::real( 6380757669.0 / 8691406250.0 ), Type::real( 98417891.0 / 19531250.0 ), Type::real( -1692691.0 / 39062500.0 ) );

                     CALCULATE_K( 10, Type::real( 0.76 ), buffer_wavefunction, buffer_reservoir );

                     INTERMEDIATE_SUM_K( 10, Type::real( -1456295425347.0 / 2642187500000.0 ), Type::real( 0.0 ), Type::real( 0.0 ), Type::real( 110740056.0 / 34765625.0 ), Type::real( -21221682384.0 / 4345703125.0 ), Type::real( 58859060169.0 / 13906250000.0 ), Type::real( -177381525069.0 / 1529687500000.0 ), Type::real( -28942485159.0 / 27812500000.0 ), Type::real( -1272297.0 / 312500000.0 ), Type::real( 5151.0 / 297616.0 ) );

                     CALCULATE_K( 11, Type::real( 0.84 ), buffer_wavefunction, buffer_reservoir );

                     INTERMEDIATE_SUM_K( 11, Type::real( 844300798.0 / 137013275.0 ), Type::real( 0.0 ), Type::real( 0.0 ), Type::real( -9997568.0 / 206035.0 ), Type::real( 49636624.0 / 1030175.0 ), Type::real( -3358834871.0 / 91067470.0 ), Type::real( -40456983.0 / 1813108.0 ), Type::real( 495817135.0 / 16647628.0 ), Type::real( -149375.0 / 84266.0 ), Type::real( 7470703125.0 / 1567431866.0 ), Type::real( 1562500000.0 / 72342361.0 ) );

                     CALCULATE_K( 12, Type::real( 1.0 ), buffer_wavefunction, buffer_reservoir );

                     INTERMEDIATE_SUM_K( 12, Type::real( -26225423.0 / 37371100.0 ), Type::real( 0.0 ), Type::real( 0.0 ), Type::real( 807744.0 / 98345.0 ), Type::real( -205584.0 / 37825.0 ), Type::real( 5882202.0 / 1278485.0 ), Type::real( -84543.0 / 432718.0 ), Type::real( -223415.0 / 39338.0 ), Type::real( -3625.0 / 6188.0 ), Type::real( 292968750.0 / 374084711.0 ), Type::real( 0.0 ), Type::real( 0.0 ) );

                     CALCULATE_K( 13, Type::real( 1.0 ), buffer_wavefunction, buffer_reservoir );

                     FINAL_SUM_K( 13, Type::real( 4241.0 / 88200.0 ), Type::real( 0.0 ), Type::real( 0.0 ), Type::real( 0.0 ), Type::real( 0.0 ), Type::real( 9946.0 / 23205.0 ), Type::real( -10449.0 / 1925.0 ), Type::real( 415449.0 / 1573075.0 ), Type::real( -2025.0 / 5096.0 ), Type::real( 48828125.0 / 44900856.0 ), Type::real( 48828125.0 / 9843561.0 ), Type::real( 463.0 / 12600.0 ), Type::real( 0.0 ) ); );
}

void PHOENIX::Solver::iterateVariableTimestepNSRK78() {
    bool accept = false;
    do {
        SOLVER_SEQUENCE( false /* no graph capture */,

                         CALCULATE_K( 1, Type::real( 0.0 ), wavefunction, reservoir );

                         INTERMEDIATE_SUM_K( 1, Type::real( 1.0 / 1000.0 ) );

                         CALCULATE_K( 2, Type::real( 0.001 ), buffer_wavefunction, buffer_reservoir );

                         INTERMEDIATE_SUM_K( 2, Type::real( -491.0 / 81.0 ), Type::real( 500.0 / 81.0 ) );

                         CALCULATE_K( 3, Type::real( 0.1111111111 ), buffer_wavefunction, buffer_reservoir );

                         INTERMEDIATE_SUM_K( 3, Type::real( 1.0 / 24.0 ), Type::real( 0.0 ), Type::real( 1.0 / 8.0 ) );

                         CALCULATE_K( 4, Type::real( 0.1666666667 ), buffer_wavefunction, buffer_reservoir );

                         INTERMEDIATE_SUM_K( 4, Type::real( 5.0 / 12.0 ), Type::real( 0.0 ), Type::real( -25.0 / 16.0 ), Type::real( 25.0 / 16.0 ) );

                         CALCULATE_K( 5, Type::real( 0.4166666667 ), buffer_wavefunction, buffer_reservoir );

                         INTERMEDIATE_SUM_K( 5, Type::real( 1.0 / 20.0 ), Type::real( 0.0 ), Type::real( 0.0 ), Type::real( 1.0 / 4.0 ), Type::real( 1.0 / 5.0 ) );

                         CALCULATE_K( 6, Type::real( 0.5 ), buffer_wavefunction, buffer_reservoir );

                         INTERMEDIATE_SUM_K( 6, Type::real( -43.0 / 180.0 ), Type::real( 0.0 ), Type::real( 0.0 ), Type::real( 127.0 / 108.0 ), Type::real( -329.0 / 135.0 ), Type::real( 7.0 / 3.0 ) );

                         CALCULATE_K( 7, Type::real( 0.8333333333 ), buffer_wavefunction, buffer_reservoir );

                         INTERMEDIATE_SUM_K( 7, Type::real( 27931.0 / 240300.0 ), Type::real( 0.0 ), Type::real( 0.0 ), Type::real( -631.0 / 16020.0 ), Type::real( 2459.0 / 6675.0 ), Type::real( -3572.0 / 12015.0 ), Type::real( 5.0 / 267.0 ) );

                         CALCULATE_K( 8, Type::real( 0.1666666667 ), buffer_wavefunction, buffer_reservoir );

                         INTERMEDIATE_SUM_K( 8, Type::real( 26114.0 / 12015.0 ), Type::real( 0.0 ), Type::real( 0.0 ), Type::real( -7480.0 / 801.0 ), Type::real( 67264.0 / 4005.0 ), Type::real( -30640.0 / 2403.0 ), Type::real( 1051.0 / 1335.0 ), Type::real( 3.0 ) );

                         CALCULATE_K( 9, Type::real( 0.6666666667 ), buffer_wavefunction, buffer_reservoir );

                         INTERMEDIATE_SUM_K( 9, Type::real( 33096587331.0 / 17382812500.0 ), Type::real( 0.0 ), Type::real( 0.0 ), Type::real( -1828977848.0 / 173828125.0 ), Type::real( 62801809904.0 / 4345703125.0 ), Type::real( -9389764774.0 / 869140625.0 ), Type::real( 6380757669.0 / 8691406250.0 ), Type::real( 98417891.0 / 19531250.0 ), Type::real( -1692691.0 / 39062500.0 ) );

                         CALCULATE_K( 10, Type::real( 0.76 ), buffer_wavefunction, buffer_reservoir );

                         INTERMEDIATE_SUM_K( 10, Type::real( -1456295425347.0 / 2642187500000.0 ), Type::real( 0.0 ), Type::real( 0.0 ), Type::real( 110740056.0 / 34765625.0 ), Type::real( -21221682384.0 / 4345703125.0 ), Type::real( 58859060169.0 / 13906250000.0 ), Type::real( -177381525069.0 / 1529687500000.0 ), Type::real( -28942485159.0 / 27812500000.0 ), Type::real( -1272297.0 / 312500000.0 ), Type::real( 5151.0 / 297616.0 ) );

                         CALCULATE_K( 11, Type::real( 0.84 ), buffer_wavefunction, buffer_reservoir );

                         INTERMEDIATE_SUM_K( 11, Type::real( 844300798.0 / 137013275.0 ), Type::real( 0.0 ), Type::real( 0.0 ), Type::real( -9997568.0 / 206035.0 ), Type::real( 49636624.0 / 1030175.0 ), Type::real( -3358834871.0 / 91067470.0 ), Type::real( -40456983.0 / 1813108.0 ), Type::real( 495817135.0 / 16647628.0 ), Type::real( -149375.0 / 84266.0 ), Type::real( 7470703125.0 / 1567431866.0 ), Type::real( 1562500000.0 / 72342361.0 ) );

                         CALCULATE_K( 12, Type::real( 1.0 ), buffer_wavefunction, buffer_reservoir );

                         INTERMEDIATE_SUM_K( 12, Type::real( -26225423.0 / 37371100.0 ), Type::real( 0.0 ), Type::real( 0.0 ), Type::real( 807744.0 / 98345.0 ), Type::real( -205584.0 / 37825.0 ), Type::real( 5882202.0 / 1278485.0 ), Type::real( -84543.0 / 432718.0 ), Type::real( -223415.0 / 39338.0 ), Type::real( -3625.0 / 6188.0 ), Type::real( 292968750.0 / 374084711.0 ), Type::real( 0.0 ), Type::real( 0.0 ) );

                         CALCULATE_K( 13, Type::real( 1.0 ), buffer_wavefunction, buffer_reservoir );

                         INTERMEDIATE_SUM_K( 13, Type::real( 4241.0 / 88200.0 ), Type::real( 0.0 ), Type::real( 0.0 ), Type::real( 0.0 ), Type::real( 0.0 ), Type::real( 9946.0 / 23205.0 ), Type::real( -10449.0 / 1925.0 ), Type::real( 415449.0 / 1573075.0 ), Type::real( -2025.0 / 5096.0 ), Type::real( 48828125.0 / 44900856.0 ), Type::real( 48828125.0 / 9843561.0 ), Type::real( 463.0 / 12600.0 ), Type::real( 0.0 ) );

                         ERROR_K( 13, Type::real( 4241.0 / 88200.0 - 3799.0 / 79800.0 ), Type::real( 0.0 ), Type::real( 0.0 ), Type::real( 0.0 ), Type::real( 0.0 ), Type::real( 9946.0 / 23205.0 - 538.0 / 1365.0 ), Type::real( -10449.0 / 1925.0 - 351.0 / 1925.0 ), Type::real( 415449.0 / 1573075.0 - 4149.0 / 15575.0 ), Type::real( -2025.0 / 5096.0 - ( -45.0 / 392.0 ) ), Type::real( 48828125.0 / 44900856.0 - 48828125.0 / 284372088.0 ), Type::real( 48828125.0 / 9843561.0 - 0.0 ),
                                  Type::real( 463.0 / 12600.0 - 0.0 ), Type::real( 0.0 - 221.0 / 4200.0 ) );

        );

        auto msum = matrix.buffer_wavefunction_plus.transformReduce( Type::complex( 0.0 ), CUDAMatrix<Type::complex>::transform_abs2(), CUDAMatrix<Type::complex>::transform_sum() );
        Type::real normalization_factor = CUDA::real( msum );
        Type::real integrated_error = matrix.rk_error.sum();
        Type::real final_error = std::abs( integrated_error / normalization_factor );

        Type::real dh_arg = system.tolerance / 2.0 / CUDA::max( std::numeric_limits<Type::real>::min(), final_error );
        Type::real dh = std::pow( dh_arg, Type::real( 1.0 / 8.0 ) );

        if ( std::isnan( dh ) || std::isnan( final_error ) ) {
            dh = Type::real( 0.9 );
            final_error = std::numeric_limits<Type::real>::max();
        }

        Type::real new_dt = std::min( system.p.dt * dh, system.dt_max );
        if ( new_dt < system.dt_min ) {
            new_dt = system.dt_min;
            accept = true;
        }
        system.p.dt = new_dt;
        updateKernelTime();

        if ( final_error < system.tolerance ) {
            accept = true;
            matrix.wavefunction_plus.swap( matrix.buffer_wavefunction_plus );
            matrix.reservoir_plus.swap( matrix.buffer_reservoir_plus );
            if ( system.use_twin_mode ) {
                matrix.wavefunction_minus.swap( matrix.buffer_wavefunction_minus );
                matrix.reservoir_minus.swap( matrix.buffer_reservoir_minus );
            }
        }
    } while ( !accept );
}
