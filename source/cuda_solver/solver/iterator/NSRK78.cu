#include <omp.h>
#include "cuda/typedef.cuh"
#include "kernel/kernel_compute.cuh"
#include "kernel/kernel_summation.cuh"
#include "kernel/kernel_halo.cuh"
#include "system/system_parameters.hpp"
#include "cuda/cuda_matrix.cuh"
#include "solver/iterator/nsrk78.cuh"
#include "solver/solver_factory.hpp"

namespace PHOENIX {

NSRK78::NSRK78( SystemParameters& system ) : Solver( system ) {
    k_max_ = 13;
    halo_size_ = 13;
    is_adaptive_ = true;
    name_ = "NSRK78";
    description_ = "Nullspace RK 13-stage 8th order";
    butcher_tableau_ =
        "     0.0000000000 |  0.0000000000   0.0000000000   0.0000000000   0.0000000000   0.0000000000   0.0000000000   0.0000000000   0.0000000000   0.0000000000   0.0000000000   0.0000000000   0.0000000000   0.0000000000\n"
        "     0.0010000000 |  0.0010000000   0.0000000000   0.0000000000   0.0000000000   0.0000000000   0.0000000000   0.0000000000   0.0000000000   0.0000000000   0.0000000000   0.0000000000   0.0000000000   0.0000000000\n"
        "     0.1111111111 | -6.0617283951   6.1728395062   0.0000000000   0.0000000000   0.0000000000   0.0000000000   0.0000000000   0.0000000000   0.0000000000   0.0000000000   0.0000000000   0.0000000000   0.0000000000\n"
        "     0.1666666667 |  0.0416666667   0.0000000000   0.1250000000   0.0000000000   0.0000000000   0.0000000000   0.0000000000   0.0000000000   0.0000000000   0.0000000000   0.0000000000   0.0000000000   0.0000000000\n"
        "     0.4166666667 |  0.4166666667   0.0000000000  -1.5625000000   1.5625000000   0.0000000000   0.0000000000   0.0000000000   0.0000000000   0.0000000000   0.0000000000   0.0000000000   0.0000000000   0.0000000000\n"
        "     0.5000000000 |  0.0500000000   0.0000000000   0.0000000000   0.2500000000   0.2000000000   0.0000000000   0.0000000000   0.0000000000   0.0000000000   0.0000000000   0.0000000000   0.0000000000   0.0000000000\n"
        "     0.8333333333 | -0.2388888889   0.0000000000   0.0000000000   1.1759259259  -2.4370370370   2.3333333333   0.0000000000   0.0000000000   0.0000000000   0.0000000000   0.0000000000   0.0000000000   0.0000000000\n"
        "     0.1666666667 |  0.1162338743   0.0000000000   0.0000000000  -0.0393757809   0.3685158355  -0.2975124289   0.0187245206   0.0000000000   0.0000000000   0.0000000000   0.0000000000   0.0000000000   0.0000000000\n"
        "     0.6666666667 |  2.1734498543   0.0000000000   0.0000000000  -9.3383270911  16.797003740   -12.745269926   0.7872659176   3.0000000000   0.0000000000   0.0000000000   0.0000000000   0.0000000000   0.0000000000\n"
        "     0.7600000000 |  1.9039834510   0.0000000000   0.0000000000 -17.571184052   16.652296555   -1.7433454667   0.0000000000   0.0000000000   0.0000000000   0.0000000000   0.0000000000   0.0000000000   0.0000000000\n"
        "     0.8400000000 | -0.5511703561   0.0000000000   0.0000000000   3.185331936   -0.2855556672   0.0171531722   0.0000000000   0.0000000000   0.0000000000   0.0000000000   0.0000000000   0.0000000000   0.0000000000\n"
        "     1.0000000000 |  6.1621824455   0.0000000000   0.0000000000 -48.523639644   43.594126382   -8.7726603850   4.7662059749  21.5986868330   0.0000000000   0.0000000000   0.0000000000   0.0000000000   0.0000000000\n"
        "     1.0000000000 | -0.7017567853   0.0000000000   0.0000000000   8.213371203   -5.0177318283   4.2147151770   0.7831613949   0.0000000000   0.0000000000   0.0000000000   0.0000000000   0.0000000000   0.0000000000\n"
        "     ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------\n"
        "     0.0000000000 |  0.0480839002   0.0000000000   0.0000000000   0.0000000000   0.0000000000   0.2244210495  -0.5351902593   0.0019833607  -0.4089591837   1.0874653481   4.9604127002   0.0367460317   0.0000000000";
}

void NSRK78::step( bool variable_time_step ) {
    bool cuda_graph = !variable_time_step;
    bool accept = !variable_time_step; // If we are not using variable time step, we can accept the solution right away.

    do {
        SOLVER_SEQUENCE(
            cuda_graph /*Capture CUDA Graph*/,

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
            if ( !variable_time_step ) { 
                
                FINAL_SUM_K( 13, Type::real( 4241.0 / 88200.0 ), Type::real( 0.0 ), Type::real( 0.0 ), Type::real( 0.0 ), Type::real( 0.0 ), Type::real( 9946.0 / 23205.0 ), Type::real( -10449.0 / 1925.0 ), Type::real( 415449.0 / 1573075.0 ), Type::real( -2025.0 / 5096.0 ), Type::real( 48828125.0 / 44900856.0 ), Type::real( 48828125.0 / 9843561.0 ), Type::real( 463.0 / 12600.0 ), Type::real( 0.0 ) );
            
            } else {
                
                    INTERMEDIATE_SUM_K( 13, Type::real( 4241.0 / 88200.0 ), Type::real( 0.0 ), Type::real( 0.0 ), Type::real( 0.0 ), Type::real( 0.0 ), Type::real( 9946.0 / 23205.0 ), Type::real( -10449.0 / 1925.0 ), Type::real( 415449.0 / 1573075.0 ), Type::real( -2025.0 / 5096.0 ), Type::real( 48828125.0 / 44900856.0 ), Type::real( 48828125.0 / 9843561.0 ), Type::real( 463.0 / 12600.0 ), Type::real( 0.0 ) );

                ERROR_K( 13, Type::real( 4241.0 / 88200.0 - 3799.0 / 79800.0 ), Type::real( 0.0 ), Type::real( 0.0 ), Type::real( 0.0 ), Type::real( 0.0 ), Type::real( 9946.0 / 23205.0 - 538.0 / 1365.0 ), Type::real( -10449.0 / 1925.0 - 351.0 / 1925.0 ), Type::real( 415449.0 / 1573075.0 - 4149.0 / 15575.0 ), Type::real( -2025.0 / 5096.0 - ( -45.0 / 392.0 ) ), Type::real( 48828125.0 / 44900856.0 - 48828125.0 / 284372088.0 ), Type::real( 48828125.0 / 9843561.0 - 0.0 ), Type::real( 463.0 / 12600.0 - 0.0 ), Type::real( 0.0 - 221.0 / 4200.0 ) );
            
            } 
        );
        
        if ( !variable_time_step )
            return;

        accept = adaptTimeStep( 1.0 / 8.0, false );

        if ( accept ) {
            swapBuffers();
        }

    } while ( !accept );
}

REGISTER_SOLVER( "NSRK78", NSRK78, true, "Nullspace RK 13-stage 8th order" );

} // namespace PHOENIX