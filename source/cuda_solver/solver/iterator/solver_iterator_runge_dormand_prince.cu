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

void PHOENIX::Solver::iterateFixedTimestepDOP5() {
    SOLVER_SEQUENCE( true /*Capture CUDA Graph*/,

                     CALCULATE_K( 1, wavefunction, reservoir );

                     INTERMEDIATE_SUM_K( 1, Type::real( 1.0 / 5.0 ) );

                     CALCULATE_K( 2, buffer_wavefunction, buffer_reservoir );

                     INTERMEDIATE_SUM_K( 2, Type::real( 3.0 / 40.0 ), Type::real( 9.0 / 40.0 ) );

                     CALCULATE_K( 3, buffer_wavefunction, buffer_reservoir );

                     INTERMEDIATE_SUM_K( 3, Type::real( 44.0 / 45.0 ), Type::real( -56.0 / 15.0 ), Type::real( 32.0 / 9.0 ) );

                     CALCULATE_K( 4, buffer_wavefunction, buffer_reservoir );

                     INTERMEDIATE_SUM_K( 4, Type::real( 19372.0 / 6561.0 ), Type::real( -25360.0 / 2187.0 ), Type::real( 64448.0 / 6561.0 ), Type::real( -212.0 / 729.0 ) );

                     CALCULATE_K( 5, buffer_wavefunction, buffer_reservoir );

                     INTERMEDIATE_SUM_K( 5, Type::real( 9017.0 / 3168.0 ), Type::real( -355.0 / 33.0 ), Type::real( 46732.0 / 5247.0 ), Type::real( 49.0 / 176.0 ), Type::real( -5103.0 / 18656.0 ) );

                     CALCULATE_K( 6, buffer_wavefunction, buffer_reservoir );

                     FINAL_SUM_K( 6, Type::real( 35.0 / 384.0 ), Type::real( 0.0 ), Type::real( 500.0 / 1113.0 ), Type::real( 125.0 / 192.0 ), Type::real( -2187.0 / 6784.0 ), Type::real( 11.0 / 84.0 ) );

    );
}

void PHOENIX::Solver::iterateVariableTimestepDOP45() {
    bool accept = false;
    do {
        SOLVER_SEQUENCE( false /*Capture CUDA Graph*/,

                         CALCULATE_K( 1, wavefunction, reservoir );

                         INTERMEDIATE_SUM_K( 1, Type::real( 1.0 / 5.0 ) );

                         CALCULATE_K( 2, buffer_wavefunction, buffer_reservoir );

                         INTERMEDIATE_SUM_K( 2, Type::real( 3.0 / 40.0 ), Type::real( 9.0 / 40.0 ) );

                         CALCULATE_K( 3, buffer_wavefunction, buffer_reservoir );

                         INTERMEDIATE_SUM_K( 3, Type::real( 44.0 / 45.0 ), Type::real( -56.0 / 15.0 ), Type::real( 32.0 / 9.0 ) );

                         CALCULATE_K( 4, buffer_wavefunction, buffer_reservoir );

                         INTERMEDIATE_SUM_K( 4, Type::real( 19372.0 / 6561.0 ), Type::real( -25360.0 / 2187.0 ), Type::real( 64448.0 / 6561.0 ), Type::real( -212.0 / 729.0 ) );

                         CALCULATE_K( 5, buffer_wavefunction, buffer_reservoir );

                         INTERMEDIATE_SUM_K( 5, Type::real( 9017.0 / 3168.0 ), Type::real( -355.0 / 33.0 ), Type::real( 46732.0 / 5247.0 ), Type::real( 49.0 / 176.0 ), Type::real( -5103.0 / 18656.0 ) );

                         CALCULATE_K( 6, buffer_wavefunction, buffer_reservoir );

                         INTERMEDIATE_SUM_K( 6, Type::real( 35.0 / 384.0 ), Type::real( 0.0 ), Type::real( 500.0 / 1113.0 ), Type::real( 125.0 / 192.0 ), Type::real( -2187.0 / 6784.0 ), Type::real( 11.0 / 84.0 ) );

                         // For DP, we need the 7th k
                         CALCULATE_K( 7, buffer_wavefunction, buffer_reservoir );

                         ERROR_K( 7, Type::real( 35.0 / 384.0 - 5179.0 / 57600.0 ), Type::real( 0.0 ), Type::real( 500.0 / 1113.0 - 7571.0 / 16695.0 ), Type::real( 125.0 / 192.0 - 393.0 / 640.0 ), Type::real( -2187.0 / 6784.0 + 92097.0 / 339200.0 ), Type::real( 11.0 / 84.0 - 187.0 / 2100.0 ), Type::real( -1.0 / 40.0 ) );

                         // Redo this sum so we get the correct solution in buffer_...
                         INTERMEDIATE_SUM_K( 6, Type::real( 35.0 / 384.0 ), Type::real( 0.0 ), Type::real( 500.0 / 1113.0 ), Type::real( 125.0 / 192.0 ), Type::real( -2187.0 / 6784.0 ), Type::real( 11.0 / 84.0 ) );

        );
        auto msum = matrix.k_wavefunction_plus.transformReduce( Type::complex( 0.0 ), CUDAMatrix<Type::complex>::transform_abs2(), CUDAMatrix<Type::complex>::transform_sum(), 5 /*matrix k6*/ );
        Type::real normalization_factor = CUDA::sqrt( CUDA::real( msum ) );
        Type::real integrated_error = std::sqrt( matrix.rk_error.sum() );

        Type::real final_error = std::abs( integrated_error / normalization_factor );
        Type::real dh_arg = system.tolerance / 2.0 / CUDA::max( std::numeric_limits<Type::real>::min(), final_error );
        Type::real dh = std::pow<Type::real>( dh_arg, Type::real( 1.0 / 5.0 ) );

        if ( std::isnan( dh ) ) {
            dh = 0.9;
            final_error = std::numeric_limits<Type::real>::max();
        }
        if ( std::isnan( final_error ) ) {
            dh = 0.9;
            final_error = std::numeric_limits<Type::real>::max();
        }

        //  Set new timestep
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

void PHOENIX::Solver::iterateFixedTimestepDOP853() {
    SOLVER_SEQUENCE( true /*Capture CUDA Graph*/,

                     // ——— Dormand–Prince 8(5,3) (w) ———
                     // Coefficients taken verbatim from your dop853.f snippet.

                     // Stage 1 (t + 0)
                     CALCULATE_K( 1, wavefunction, reservoir );

                     // Stage 2 (t + c₂·h),   c₂ =  5.260015195876773e-2
                     INTERMEDIATE_SUM_K( 1, Type::real( 5.260015195876773e-2 ) ); CALCULATE_K( 2, buffer_wavefunction, buffer_reservoir );

                     // Stage 3 (t + c₃·h),   c₃ =  7.8900227938151598e-2
                     INTERMEDIATE_SUM_K( 2,
                                         Type::real( 1.9725056984537899e-2 ), // a₃₁
                                         Type::real( 5.9175170953613698e-2 )  // a₃₂
                     );
                     CALCULATE_K( 3, buffer_wavefunction, buffer_reservoir );

                     // Stage 4 (t + c₄·h),   c₄ =  1.1835034190722739e-1
                     INTERMEDIATE_SUM_K( 3,
                                         Type::real( 2.9587585476806849e-2 ), // a₄₁
                                         Type::real( 0.0 ),                   // a₄₂
                                         Type::real( 8.8762756430420548e-2 )  // a₄₃
                     );
                     CALCULATE_K( 4, buffer_wavefunction, buffer_reservoir );

                     // Stage 5 (t + c₅·h),   c₅ =  2.8164965809277260e-1
                     INTERMEDIATE_SUM_K( 4,
                                         Type::real( 2.4136513415926669e-1 ),  // a₅₁
                                         Type::real( 0.0 ),                    // a₅₂
                                         Type::real( -8.8454947932828610e-1 ), // a₅₃
                                         Type::real( 9.2483400326179200e-1 )   // a₅₄
                     );
                     CALCULATE_K( 5, buffer_wavefunction, buffer_reservoir );

                     // Stage 6 (t + c₆·h),   c₆ =  3.3333333333333333e-1
                     INTERMEDIATE_SUM_K( 5,
                                         Type::real( 3.7037037037037037e-2 ), // a₆₁
                                         Type::real( 0.0 ),                   // a₆₂
                                         Type::real( 0.0 ),                   // a₆₃
                                         Type::real( 1.7082860872947387e-1 ), // a₆₄
                                         Type::real( 1.2546768756682243e-1 )  // a₆₅
                     );
                     CALCULATE_K( 6, buffer_wavefunction, buffer_reservoir );

                     // Stage 7 (t + c₇·h),   c₇ =  2.5e-1
                     INTERMEDIATE_SUM_K( 6,
                                         Type::real( 3.7109375e-2 ),          // a₇₁
                                         Type::real( 0.0 ),                   // a₇₂
                                         Type::real( 0.0 ),                   // a₇₃
                                         Type::real( 1.7025221101954404e-1 ), // a₇₄
                                         Type::real( 6.0216538980455961e-2 ), // a₇₅
                                         Type::real( -1.7578125e-2 )          // a₇₆
                     );
                     CALCULATE_K( 7, buffer_wavefunction, buffer_reservoir );

                     // Stage 8 (t + c₈·h),   c₈ =  0.3076923076923077
                     INTERMEDIATE_SUM_K( 7,
                                         Type::real( 3.7092000118504793e-2 ),  // a₈₁
                                         Type::real( 0.0 ),                    // a₈₂
                                         Type::real( 0.0 ),                    // a₈₃
                                         Type::real( 1.7038392571223999e-1 ),  // a₈₄
                                         Type::real( 1.0726203044637328e-1 ),  // a₈₅
                                         Type::real( -1.5319437748624402e-2 ), // a₈₆
                                         Type::real( 8.2737891638140229e-3 )   // a₈₇
                     );
                     CALCULATE_K( 8, buffer_wavefunction, buffer_reservoir );

                     // Stage 9 (t + c₉·h),   c₉ =  0.6512820512820513
                     INTERMEDIATE_SUM_K( 8,
                                         Type::real( 6.2411095871607572e-1 ),  // a₉₁
                                         Type::real( 0.0 ),                    // a₉₂
                                         Type::real( 0.0 ),                    // a₉₃
                                         Type::real( -3.3608926294469413e+0 ), // a₉₄
                                         Type::real( -8.6821934684172601e-1 ), // a₉₅
                                         Type::real( 2.7592099699446708e+1 ),  // a₉₆
                                         Type::real( 2.0154067550477893e+1 ),  // a₉₇
                                         Type::real( -4.3489884181069959e+1 )  // a₉₈
                     );
                     CALCULATE_K( 9, buffer_wavefunction, buffer_reservoir );

                     // Stage 10 (t + c₁₀·h), c₁₀ =  0.6
                     INTERMEDIATE_SUM_K( 9,
                                         Type::real( 4.7766253643826437e-1 ),  // a₁₀,₁
                                         Type::real( 0.0 ),                    // a₁₀,₂
                                         Type::real( 0.0 ),                    // a₁₀,₃
                                         Type::real( -2.4881146199716676e+0 ), // a₁₀,₄
                                         Type::real( -5.9029082683684300e-1 ), // a₁₀,₅
                                         Type::real( 2.1230051448181194e+1 ),  // a₁₀,₆
                                         Type::real( 1.5279233632882424e+1 ),  // a₁₀,₇
                                         Type::real( -3.3288210968984863e+1 ), // a₁₀,₈
                                         Type::real( -2.0331201708508626e-2 )  // a₁₀,₉
                     );
                     CALCULATE_K( 10, buffer_wavefunction, buffer_reservoir );

                     // Stage 11 (t + c₁₁·h), c₁₁ =  6/7
                     INTERMEDIATE_SUM_K( 10,
                                         Type::real( -9.3714243008598733e-1 ), // a₁₁,₁
                                         Type::real( 0.0 ),                    // a₁₁,₂
                                         Type::real( 0.0 ),                    // a₁₁,₃
                                         Type::real( 5.1863724288440637e+0 ),  // a₁₁,₄
                                         Type::real( 1.0914373489967296e+0 ),  // a₁₁,₅
                                         Type::real( -8.1497870107469261e+0 ), // a₁₁,₆
                                         Type::real( -1.8520065659996960e+1 ), // a₁₁,₇
                                         Type::real( 2.2739487099350504e+1 ),  // a₁₁,₈
                                         Type::real( 2.4936055526796524e+0 ),  // a₁₁,₉
                                         Type::real( -3.0467644718982195e+0 )  // a₁₁,₁₀
                     );
                     CALCULATE_K( 11, buffer_wavefunction, buffer_reservoir );

                     // Stage 12 (t + c₁₂·h), c₁₂ =  1.0
                     INTERMEDIATE_SUM_K( 11,
                                         Type::real( 2.2733101475165382e+0 ),  // a₁₂,₁
                                         Type::real( 0.0 ),                    // a₁₂,₂
                                         Type::real( 0.0 ),                    // a₁₂,₃
                                         Type::real( -1.0534495466737250e+1 ), // a₁₂,₄
                                         Type::real( -2.0008720582248625e+0 ), // a₁₂,₅
                                         Type::real( -1.7958931863118799e+1 ), // a₁₂,₆
                                         Type::real( 2.7948884529419960e+1 ),  // a₁₂,₇
                                         Type::real( -2.8589982771350237e+0 ), // a₁₂,₈
                                         Type::real( -8.8728569335306295e+0 ), // a₁₂,₉
                                         Type::real( 1.2360567175794303e+1 ),  // a₁₂,₁₀
                                         Type::real( 6.4339274601576353e-1 )   // a₁₂,₁₁
                     );
                     CALCULATE_K( 12, buffer_wavefunction, buffer_reservoir );

                     // Final 8th‑order combination (b₁…b₁₂)
                     // b₂=b₃=b₄=b₅=0
                     FINAL_SUM_K( 12,
                                  Type::real( 5.4293734116568762e-2 ),  // b₁
                                  Type::real( 0.0 ),                    // b₂
                                  Type::real( 0.0 ),                    // b₃
                                  Type::real( 0.0 ),                    // b₄
                                  Type::real( 0.0 ),                    // b₅
                                  Type::real( 4.4503128927524089e+0 ),  // b₆
                                  Type::real( 1.8915178993145004e+0 ),  // b₇
                                  Type::real( -5.8012039600105848e+0 ), // b₈
                                  Type::real( 3.1116436695781989e-1 ),  // b₉
                                  Type::real( -1.5216094966251608e-1 ), // b₁₀
                                  Type::real( 2.0136540080403035e-1 ),  // b₁₁
                                  Type::real( 4.4710615727772591e-2 )   // b₁₂
                     );

    );
}

void PHOENIX::Solver::iterateVariableTimestepDOP853() {
    bool accept = false;
    do {
        SOLVER_SEQUENCE( false /*Capture CUDA Graph*/,
                         // ——— Dormand–Prince 8(5,3) (w) ———
                         // Coefficients taken verbatim from your dop853.f snippet.

                         // Stage 1 (t + 0)
                         CALCULATE_K( 1, wavefunction, reservoir );

                         // Stage 2 (t + c₂·h),   c₂ =  5.260015195876773e-2
                         INTERMEDIATE_SUM_K( 1, Type::real( 5.260015195876773e-2 ) ); CALCULATE_K( 2, buffer_wavefunction, buffer_reservoir );

                         // Stage 3 (t + c₃·h),   c₃ =  7.8900227938151598e-2
                         INTERMEDIATE_SUM_K( 2,
                                             Type::real( 1.9725056984537899e-2 ), // a₃₁
                                             Type::real( 5.9175170953613698e-2 )  // a₃₂
                         );
                         CALCULATE_K( 3, buffer_wavefunction, buffer_reservoir );

                         // Stage 4 (t + c₄·h),   c₄ =  1.1835034190722739e-1
                         INTERMEDIATE_SUM_K( 3,
                                             Type::real( 2.9587585476806849e-2 ), // a₄₁
                                             Type::real( 0.0 ),                   // a₄₂
                                             Type::real( 8.8762756430420548e-2 )  // a₄₃
                         );
                         CALCULATE_K( 4, buffer_wavefunction, buffer_reservoir );

                         // Stage 5 (t + c₅·h),   c₅ =  2.8164965809277260e-1
                         INTERMEDIATE_SUM_K( 4,
                                             Type::real( 2.4136513415926669e-1 ),  // a₅₁
                                             Type::real( 0.0 ),                    // a₅₂
                                             Type::real( -8.8454947932828610e-1 ), // a₅₃
                                             Type::real( 9.2483400326179200e-1 )   // a₅₄
                         );
                         CALCULATE_K( 5, buffer_wavefunction, buffer_reservoir );

                         // Stage 6 (t + c₆·h),   c₆ =  3.3333333333333333e-1
                         INTERMEDIATE_SUM_K( 5,
                                             Type::real( 3.7037037037037037e-2 ), // a₆₁
                                             Type::real( 0.0 ),                   // a₆₂
                                             Type::real( 0.0 ),                   // a₆₃
                                             Type::real( 1.7082860872947387e-1 ), // a₆₄
                                             Type::real( 1.2546768756682243e-1 )  // a₆₅
                         );
                         CALCULATE_K( 6, buffer_wavefunction, buffer_reservoir );

                         // Stage 7 (t + c₇·h),   c₇ =  2.5e-1
                         INTERMEDIATE_SUM_K( 6,
                                             Type::real( 3.7109375e-2 ),          // a₇₁
                                             Type::real( 0.0 ),                   // a₇₂
                                             Type::real( 0.0 ),                   // a₇₃
                                             Type::real( 1.7025221101954404e-1 ), // a₇₄
                                             Type::real( 6.0216538980455961e-2 ), // a₇₅
                                             Type::real( -1.7578125e-2 )          // a₇₆
                         );
                         CALCULATE_K( 7, buffer_wavefunction, buffer_reservoir );

                         // Stage 8 (t + c₈·h),   c₈ =  0.3076923076923077
                         INTERMEDIATE_SUM_K( 7,
                                             Type::real( 3.7092000118504793e-2 ),  // a₈₁
                                             Type::real( 0.0 ),                    // a₈₂
                                             Type::real( 0.0 ),                    // a₈₃
                                             Type::real( 1.7038392571223999e-1 ),  // a₈₄
                                             Type::real( 1.0726203044637328e-1 ),  // a₈₅
                                             Type::real( -1.5319437748624402e-2 ), // a₈₆
                                             Type::real( 8.2737891638140229e-3 )   // a₈₇
                         );
                         CALCULATE_K( 8, buffer_wavefunction, buffer_reservoir );

                         // Stage 9 (t + c₉·h),   c₉ =  0.6512820512820513
                         INTERMEDIATE_SUM_K( 8,
                                             Type::real( 6.2411095871607572e-1 ),  // a₉₁
                                             Type::real( 0.0 ),                    // a₉₂
                                             Type::real( 0.0 ),                    // a₉₃
                                             Type::real( -3.3608926294469413e+0 ), // a₉₄
                                             Type::real( -8.6821934684172601e-1 ), // a₉₅
                                             Type::real( 2.7592099699446708e+1 ),  // a₉₆
                                             Type::real( 2.0154067550477893e+1 ),  // a₉₇
                                             Type::real( -4.3489884181069959e+1 )  // a₉₈
                         );
                         CALCULATE_K( 9, buffer_wavefunction, buffer_reservoir );

                         // Stage 10 (t + c₁₀·h), c₁₀ =  0.6
                         INTERMEDIATE_SUM_K( 9,
                                             Type::real( 4.7766253643826437e-1 ),  // a₁₀,₁
                                             Type::real( 0.0 ),                    // a₁₀,₂
                                             Type::real( 0.0 ),                    // a₁₀,₃
                                             Type::real( -2.4881146199716676e+0 ), // a₁₀,₄
                                             Type::real( -5.9029082683684300e-1 ), // a₁₀,₅
                                             Type::real( 2.1230051448181194e+1 ),  // a₁₀,₆
                                             Type::real( 1.5279233632882424e+1 ),  // a₁₀,₇
                                             Type::real( -3.3288210968984863e+1 ), // a₁₀,₈
                                             Type::real( -2.0331201708508626e-2 )  // a₁₀,₉
                         );
                         CALCULATE_K( 10, buffer_wavefunction, buffer_reservoir );

                         // Stage 11 (t + c₁₁·h), c₁₁ =  6/7
                         INTERMEDIATE_SUM_K( 10,
                                             Type::real( -9.3714243008598733e-1 ), // a₁₁,₁
                                             Type::real( 0.0 ),                    // a₁₁,₂
                                             Type::real( 0.0 ),                    // a₁₁,₃
                                             Type::real( 5.1863724288440637e+0 ),  // a₁₁,₄
                                             Type::real( 1.0914373489967296e+0 ),  // a₁₁,₅
                                             Type::real( -8.1497870107469261e+0 ), // a₁₁,₆
                                             Type::real( -1.8520065659996960e+1 ), // a₁₁,₇
                                             Type::real( 2.2739487099350504e+1 ),  // a₁₁,₈
                                             Type::real( 2.4936055526796524e+0 ),  // a₁₁,₉
                                             Type::real( -3.0467644718982195e+0 )  // a₁₁,₁₀
                         );
                         CALCULATE_K( 11, buffer_wavefunction, buffer_reservoir );

                         // Stage 12 (t + c₁₂·h), c₁₂ =  1.0
                         INTERMEDIATE_SUM_K( 11,
                                             Type::real( 2.2733101475165382e+0 ),  // a₁₂,₁
                                             Type::real( 0.0 ),                    // a₁₂,₂
                                             Type::real( 0.0 ),                    // a₁₂,₃
                                             Type::real( -1.0534495466737250e+1 ), // a₁₂,₄
                                             Type::real( -2.0008720582248625e+0 ), // a₁₂,₅
                                             Type::real( -1.7958931863118799e+1 ), // a₁₂,₆
                                             Type::real( 2.7948884529419960e+1 ),  // a₁₂,₇
                                             Type::real( -2.8589982771350237e+0 ), // a₁₂,₈
                                             Type::real( -8.8728569335306295e+0 ), // a₁₂,₉
                                             Type::real( 1.2360567175794303e+1 ),  // a₁₂,₁₀
                                             Type::real( 6.4339274601576353e-1 )   // a₁₂,₁₁
                         );
                         CALCULATE_K( 12, buffer_wavefunction, buffer_reservoir );

                         // Final 8th‑order combination (b₁…b₁₂)
                         // b₂=b₃=b₄=b₅=0
                         INTERMEDIATE_SUM_K( 12,
                                             Type::real( 5.4293734116568762e-2 ),  // b₁
                                             Type::real( 0.0 ),                    // b₂
                                             Type::real( 0.0 ),                    // b₃
                                             Type::real( 0.0 ),                    // b₄
                                             Type::real( 0.0 ),                    // b₅
                                             Type::real( 4.4503128927524089e+0 ),  // b₆
                                             Type::real( 1.8915178993145004e+0 ),  // b₇
                                             Type::real( -5.8012039600105848e+0 ), // b₈
                                             Type::real( 3.1116436695781989e-1 ),  // b₉
                                             Type::real( -1.5216094966251608e-1 ), // b₁₀
                                             Type::real( 2.0136540080403035e-1 ),  // b₁₁
                                             Type::real( 4.4710615727772591e-2 )   // b₁₂
                         );

                         ERROR_K( 12,
                                  Type::real( 4.1173689122373888e-2 ),  // = 0.05429373411656876 − 0.01312004499419488
                                  Type::real( 0.0 ),                    // b2*
                                  Type::real( 0.0 ),                    // b3*
                                  Type::real( 0.0 ),                    // b4*
                                  Type::real( 0.0 ),                    // b5*
                                  Type::real( 5.6754693391286133e+0 ),  // = 4.450312892752409 + 1.2251564463762044
                                  Type::real( 2.3872768489717506e+0 ),  // = 1.8915178993145004 + 0.4957589496572502
                                  Type::real( -7.4655811424655713e+0 ), // = −5.801203960010585 − 1.6643771824549865
                                  Type::real( 6.6149321570779360e-1 ),  // = 0.3111643669578194 + 0.3503288487499737
                                  Type::real( -4.8634006837553356e-1 ), // = −0.1521609496625161 − 0.3341791187130175
                                  Type::real( 1.1944219431891464e-1 ),  // = 0.2013654008040304 − 0.0819232064851157
                                  Type::real( 6.7065923591658886e-2 )   // = 0.04471061572777259 + 0.02235530786388630
                         );

        );
        //auto [min, max] = matrix.buffer_wavefunction_plus.extrema();
        auto msum = matrix.buffer_wavefunction_plus.transformReduce( Type::complex( 0.0 ), CUDAMatrix<Type::complex>::transform_abs2(), CUDAMatrix<Type::complex>::transform_sum() );
        Type::real normalization_factor = CUDA::sqrt( CUDA::real( msum ) );
        Type::real integrated_error = std::sqrt( matrix.rk_error.sum() );

        Type::real final_error = std::abs( integrated_error / normalization_factor );
        Type::real dh_arg = system.tolerance / 2.0 / CUDA::max( std::numeric_limits<Type::real>::min(), final_error );
        Type::real dh = std::pow<Type::real>( dh_arg, Type::real( 0.16 ) );

        if ( std::isnan( dh ) ) {
            dh = 0.9;
            final_error = std::numeric_limits<Type::real>::max();
        }
        if ( std::isnan( final_error ) ) {
            dh = 0.9;
            final_error = std::numeric_limits<Type::real>::max();
        }

        //  Set new timestep
        Type::real new_dt = std::min( system.p.dt * dh, system.dt_max );
        //if ( dh < 1.0 )
        //new_dt = std::max( system.p.dt - system.dt_min * std::floor( 1.0 / dh ), system.dt_min );
        //else
        //new_dt = std::min( system.p.dt + system.dt_min * std::floor( dh ), system.dt_max );
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
            //std::cout << "ACCEPTED " << final_error << ", norm = " << normalization_factor << ", dh = " << dh << " --> new dt = " << new_dt << " (old: " << system.p.dt << ")" << std::endl;
        }

        //std::cout << final_error << ", norm = " << normalization_factor << ", dh = " << dh << " --> new dt = " << new_dt << " (old: " << system.p.dt << ")" << std::endl;
    } while ( !accept );
}