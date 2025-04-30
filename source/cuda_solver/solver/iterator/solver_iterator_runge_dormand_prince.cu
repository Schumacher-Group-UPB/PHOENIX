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

                     CALCULATE_K( 1, Type::real( 0.0 ), wavefunction, reservoir );

                     INTERMEDIATE_SUM_K( 1, Type::real( 1.0 / 5.0 ) );

                     CALCULATE_K( 2, Type::real( 1.0 / 5.0 ), buffer_wavefunction, buffer_reservoir );

                     INTERMEDIATE_SUM_K( 2, Type::real( 3.0 / 40.0 ), Type::real( 9.0 / 40.0 ) );

                     CALCULATE_K( 3, Type::real( 3.0 / 10.0 ), buffer_wavefunction, buffer_reservoir );

                     INTERMEDIATE_SUM_K( 3, Type::real( 44.0 / 45.0 ), Type::real( -56.0 / 15.0 ), Type::real( 32.0 / 9.0 ) );

                     CALCULATE_K( 4, Type::real( 4.0 / 5.0 ), buffer_wavefunction, buffer_reservoir );

                     INTERMEDIATE_SUM_K( 4, Type::real( 19372.0 / 6561.0 ), Type::real( -25360.0 / 2187.0 ), Type::real( 64448.0 / 6561.0 ), Type::real( -212.0 / 729.0 ) );

                     CALCULATE_K( 5, Type::real( 8.0 / 9.0 ), buffer_wavefunction, buffer_reservoir );

                     INTERMEDIATE_SUM_K( 5, Type::real( 9017.0 / 3168.0 ), Type::real( -355.0 / 33.0 ), Type::real( 46732.0 / 5247.0 ), Type::real( 49.0 / 176.0 ), Type::real( -5103.0 / 18656.0 ) );

                     CALCULATE_K( 6, Type::real( 1.0 ), buffer_wavefunction, buffer_reservoir );

                     FINAL_SUM_K( 6, Type::real( 35.0 / 384.0 ), Type::real( 0.0 ), Type::real( 500.0 / 1113.0 ), Type::real( 125.0 / 192.0 ), Type::real( -2187.0 / 6784.0 ), Type::real( 11.0 / 84.0 ) );

    );
}

void PHOENIX::Solver::iterateVariableTimestepDOP45() {
    bool accept = false;
    do {
        SOLVER_SEQUENCE( false /*Capture CUDA Graph*/,

                         CALCULATE_K( 1, Type::real( 0.0 ), wavefunction, reservoir );

                         INTERMEDIATE_SUM_K( 1, Type::real( 1.0 / 5.0 ) );

                         CALCULATE_K( 2, Type::real( 1.0 / 5.0 ), buffer_wavefunction, buffer_reservoir );

                         INTERMEDIATE_SUM_K( 2, Type::real( 3.0 / 40.0 ), Type::real( 9.0 / 40.0 ) );

                         CALCULATE_K( 3, Type::real( 3.0 / 10.0 ), buffer_wavefunction, buffer_reservoir );

                         INTERMEDIATE_SUM_K( 3, Type::real( 44.0 / 45.0 ), Type::real( -56.0 / 15.0 ), Type::real( 32.0 / 9.0 ) );

                         CALCULATE_K( 4, Type::real( 4.0 / 5.0 ), buffer_wavefunction, buffer_reservoir );

                         INTERMEDIATE_SUM_K( 4, Type::real( 19372.0 / 6561.0 ), Type::real( -25360.0 / 2187.0 ), Type::real( 64448.0 / 6561.0 ), Type::real( -212.0 / 729.0 ) );

                         CALCULATE_K( 5, Type::real( 8.0 / 9.0 ), buffer_wavefunction, buffer_reservoir );

                         INTERMEDIATE_SUM_K( 5, Type::real( 9017.0 / 3168.0 ), Type::real( -355.0 / 33.0 ), Type::real( 46732.0 / 5247.0 ), Type::real( 49.0 / 176.0 ), Type::real( -5103.0 / 18656.0 ) );

                         CALCULATE_K( 6, Type::real( 1.0 ), buffer_wavefunction, buffer_reservoir );

                         INTERMEDIATE_SUM_K( 6, Type::real( 35.0 / 384.0 ), Type::real( 0.0 ), Type::real( 500.0 / 1113.0 ), Type::real( 125.0 / 192.0 ), Type::real( -2187.0 / 6784.0 ), Type::real( 11.0 / 84.0 ) );

                         // For DP, we need the 7th k
                         CALCULATE_K( 7, Type::real( 1.0 ), buffer_wavefunction, buffer_reservoir );

                         ERROR_K( 7, Type::real( 35.0 / 384.0 - 5179.0 / 57600.0 ), Type::real( 0.0 ), Type::real( 500.0 / 1113.0 - 7571.0 / 16695.0 ), Type::real( 125.0 / 192.0 - 393.0 / 640.0 ), Type::real( -2187.0 / 6784.0 + 92097.0 / 339200.0 ), Type::real( 11.0 / 84.0 - 187.0 / 2100.0 ), Type::real( -1.0 / 40.0 ) );

                         // Redo this sum so we get the correct solution in buffer_...
                         INTERMEDIATE_SUM_K( 6, Type::real( 35.0 / 384.0 ), Type::real( 0.0 ), Type::real( 500.0 / 1113.0 ), Type::real( 125.0 / 192.0 ), Type::real( -2187.0 / 6784.0 ), Type::real( 11.0 / 84.0 ) );

        );
        auto msum = matrix.k_wavefunction_plus.transformReduce( Type::complex( 0.0 ), CUDAMatrix<Type::complex>::transform_abs2(), CUDAMatrix<Type::complex>::transform_sum(), 5 /*matrix k6*/ );
        Type::real normalization_factor = CUDA::real( msum );
        Type::real integrated_error = matrix.rk_error.sum();

        Type::real final_error = std::abs( integrated_error / normalization_factor );
        Type::real dh_arg = system.tolerance / 2.0 / CUDA::max( std::numeric_limits<Type::real>::min(), final_error );
        Type::real dh = std::pow<Type::real>( dh_arg, Type::real( 0.25 ) );

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

                     // Stage 1 (t + 0)
                     CALCULATE_K( 1, Type::real( 0.0 ), wavefunction, reservoir );

                     INTERMEDIATE_SUM_K( 1, Type::real( 5.260015195876773e-2 ) );

                     CALCULATE_K( 2, Type::real( 0.05260015196 ), buffer_wavefunction, buffer_reservoir );

                     INTERMEDIATE_SUM_K( 2, Type::real( 1.9725056984537899e-2 ), Type::real( 5.9175170953613698e-2 ) );

                     CALCULATE_K( 3, Type::real( 0.07890022794 ), buffer_wavefunction, buffer_reservoir );

                     INTERMEDIATE_SUM_K( 3, Type::real( 2.9587585476806849e-2 ), Type::real( 0.0 ), Type::real( 8.8762756430420548e-2 ) );

                     CALCULATE_K( 4, Type::real( 0.1183503419 ), buffer_wavefunction, buffer_reservoir );

                     INTERMEDIATE_SUM_K( 4, Type::real( 2.4136513415926669e-1 ), Type::real( 0.0 ), Type::real( -8.8454947932828610e-1 ), Type::real( 9.2483400326179200e-1 ) );

                     CALCULATE_K( 5, Type::real( 0.2816496581 ), buffer_wavefunction, buffer_reservoir );

                     INTERMEDIATE_SUM_K( 5, Type::real( 3.7037037037037037e-2 ), Type::real( 0.0 ), Type::real( 0.0 ), Type::real( 1.7082860872947387e-1 ), Type::real( 1.2546768756682243e-1 ) );

                     CALCULATE_K( 6, Type::real( 0.3333333333 ), buffer_wavefunction, buffer_reservoir );

                     INTERMEDIATE_SUM_K( 6, Type::real( 3.7109375e-2 ), Type::real( 0.0 ), Type::real( 0.0 ), Type::real( 1.7025221101954404e-1 ), Type::real( 6.0216538980455961e-2 ), Type::real( -1.7578125e-2 ) );

                     CALCULATE_K( 7, Type::real( 0.25 ), buffer_wavefunction, buffer_reservoir );

                     INTERMEDIATE_SUM_K( 7, Type::real( 3.7092000118504793e-2 ), Type::real( 0.0 ), Type::real( 0.0 ), Type::real( 1.7038392571223999e-1 ), Type::real( 1.0726203044637328e-1 ), Type::real( -1.5319437748624402e-2 ), Type::real( 8.2737891638140229e-3 ) );

                     CALCULATE_K( 8, Type::real( 0.3076923077 ), buffer_wavefunction, buffer_reservoir );

                     INTERMEDIATE_SUM_K( 8, Type::real( 6.2411095871607572e-1 ), Type::real( 0.0 ), Type::real( 0.0 ), Type::real( -3.3608926294469413e+0 ), Type::real( -8.6821934684172601e-1 ), Type::real( 2.7592099699446708e+1 ), Type::real( 2.0154067550477893e+1 ), Type::real( -4.3489884181069959e+1 ) );

                     CALCULATE_K( 9, Type::real( 0.6512820513 ), buffer_wavefunction, buffer_reservoir );

                     INTERMEDIATE_SUM_K( 9, Type::real( 4.7766253643826437e-1 ), Type::real( 0.0 ), Type::real( 0.0 ), Type::real( -2.4881146199716676e+0 ), Type::real( -5.9029082683684300e-1 ), Type::real( 2.1230051448181194e+1 ), Type::real( 1.5279233632882424e+1 ), Type::real( -3.3288210968984863e+1 ), Type::real( -2.0331201708508626e-2 ) );

                     CALCULATE_K( 10, Type::real( 0.6 ), buffer_wavefunction, buffer_reservoir );

                     INTERMEDIATE_SUM_K( 10, Type::real( -9.3714243008598733e-1 ), Type::real( 0.0 ), Type::real( 0.0 ), Type::real( 5.1863724288440637e+0 ), Type::real( 1.0914373489967296e+0 ), Type::real( -8.1497870107469261e+0 ), Type::real( -1.8520065659996960e+1 ), Type::real( 2.2739487099350504e+1 ), Type::real( 2.4936055526796524e+0 ), Type::real( -3.0467644718982195e+0 ) );

                     CALCULATE_K( 11, Type::real( 0.8571428571 ), buffer_wavefunction, buffer_reservoir );

                     INTERMEDIATE_SUM_K( 11, Type::real( 2.2733101475165382e+0 ), Type::real( 0.0 ), Type::real( 0.0 ), Type::real( -1.0534495466737250e+1 ), Type::real( -2.0008720582248625e+0 ), Type::real( -1.7958931863118799e+1 ), Type::real( 2.7948884529419960e+1 ), Type::real( -2.8589982771350237e+0 ), Type::real( -8.8728569335306295e+0 ), Type::real( 1.2360567175794303e+1 ), Type::real( 6.4339274601576353e-1 ) );

                     CALCULATE_K( 12, Type::real( 1.0 ), buffer_wavefunction, buffer_reservoir );

                     FINAL_SUM_K( 12, Type::real( 5.4293734116568762e-2 ), Type::real( 0.0 ), Type::real( 0.0 ), Type::real( 0.0 ), Type::real( 0.0 ), Type::real( 4.4503128927524089e+0 ), Type::real( 1.8915178993145004e+0 ), Type::real( -5.8012039600105848e+0 ), Type::real( 3.1116436695781989e-1 ), Type::real( -1.5216094966251608e-1 ), Type::real( 2.0136540080403035e-1 ), Type::real( 4.4710615727772591e-2 ) );

    );
}

void PHOENIX::Solver::iterateVariableTimestepDOP853() {
    bool accept = false;
    do {
        SOLVER_SEQUENCE( false /*Capture CUDA Graph*/,

                         CALCULATE_K( 1, Type::real( 0.0 ), wavefunction, reservoir );

                         INTERMEDIATE_SUM_K( 1, Type::real( 5.260015195876773e-2 ) );

                         CALCULATE_K( 2, Type::real( 0.05260015196 ), buffer_wavefunction, buffer_reservoir );

                         INTERMEDIATE_SUM_K( 2, Type::real( 1.9725056984537899e-2 ), Type::real( 5.9175170953613698e-2 ) );

                         CALCULATE_K( 3, Type::real( 0.07890022794 ), buffer_wavefunction, buffer_reservoir );

                         INTERMEDIATE_SUM_K( 3, Type::real( 2.9587585476806849e-2 ), Type::real( 0.0 ), Type::real( 8.8762756430420548e-2 ) );

                         CALCULATE_K( 4, Type::real( 0.1183503419 ), buffer_wavefunction, buffer_reservoir );

                         INTERMEDIATE_SUM_K( 4, Type::real( 2.4136513415926669e-1 ), Type::real( 0.0 ), Type::real( -8.8454947932828610e-1 ), Type::real( 9.2483400326179200e-1 ) );

                         CALCULATE_K( 5, Type::real( 0.2816496581 ), buffer_wavefunction, buffer_reservoir );

                         INTERMEDIATE_SUM_K( 5, Type::real( 3.7037037037037037e-2 ), Type::real( 0.0 ), Type::real( 0.0 ), Type::real( 1.7082860872947387e-1 ), Type::real( 1.2546768756682243e-1 ) );

                         CALCULATE_K( 6, Type::real( 0.3333333333 ), buffer_wavefunction, buffer_reservoir );

                         INTERMEDIATE_SUM_K( 6, Type::real( 3.7109375e-2 ), Type::real( 0.0 ), Type::real( 0.0 ), Type::real( 1.7025221101954404e-1 ), Type::real( 6.0216538980455961e-2 ), Type::real( -1.7578125e-2 ) );

                         CALCULATE_K( 7, Type::real( 0.25 ), buffer_wavefunction, buffer_reservoir );

                         INTERMEDIATE_SUM_K( 7, Type::real( 3.7092000118504793e-2 ), Type::real( 0.0 ), Type::real( 0.0 ), Type::real( 1.7038392571223999e-1 ), Type::real( 1.0726203044637328e-1 ), Type::real( -1.5319437748624402e-2 ), Type::real( 8.2737891638140229e-3 ) );

                         CALCULATE_K( 8, Type::real( 0.3076923077 ), buffer_wavefunction, buffer_reservoir );

                         INTERMEDIATE_SUM_K( 8, Type::real( 6.2411095871607572e-1 ), Type::real( 0.0 ), Type::real( 0.0 ), Type::real( -3.3608926294469413e+0 ), Type::real( -8.6821934684172601e-1 ), Type::real( 2.7592099699446708e+1 ), Type::real( 2.0154067550477893e+1 ), Type::real( -4.3489884181069959e+1 ) );

                         CALCULATE_K( 9, Type::real( 0.6512820513 ), buffer_wavefunction, buffer_reservoir );

                         INTERMEDIATE_SUM_K( 9, Type::real( 4.7766253643826437e-1 ), Type::real( 0.0 ), Type::real( 0.0 ), Type::real( -2.4881146199716676e+0 ), Type::real( -5.9029082683684300e-1 ), Type::real( 2.1230051448181194e+1 ), Type::real( 1.5279233632882424e+1 ), Type::real( -3.3288210968984863e+1 ), Type::real( -2.0331201708508626e-2 ) );

                         CALCULATE_K( 10, Type::real( 0.6 ), buffer_wavefunction, buffer_reservoir );

                         INTERMEDIATE_SUM_K( 10, Type::real( -9.3714243008598733e-1 ), Type::real( 0.0 ), Type::real( 0.0 ), Type::real( 5.1863724288440637e+0 ), Type::real( 1.0914373489967296e+0 ), Type::real( -8.1497870107469261e+0 ), Type::real( -1.8520065659996960e+1 ), Type::real( 2.2739487099350504e+1 ), Type::real( 2.4936055526796524e+0 ), Type::real( -3.0467644718982195e+0 ) );

                         CALCULATE_K( 11, Type::real( 0.8571428571 ), buffer_wavefunction, buffer_reservoir );

                         INTERMEDIATE_SUM_K( 11, Type::real( 2.2733101475165382e+0 ), Type::real( 0.0 ), Type::real( 0.0 ), Type::real( -1.0534495466737250e+1 ), Type::real( -2.0008720582248625e+0 ), Type::real( -1.7958931863118799e+1 ), Type::real( 2.7948884529419960e+1 ), Type::real( -2.8589982771350237e+0 ), Type::real( -8.8728569335306295e+0 ), Type::real( 1.2360567175794303e+1 ), Type::real( 6.4339274601576353e-1 ) );

                         CALCULATE_K( 12, Type::real( 1.0 ), buffer_wavefunction, buffer_reservoir );

                         INTERMEDIATE_SUM_K( 12, Type::real( 5.4293734116568762e-2 ), Type::real( 0.0 ), Type::real( 0.0 ), Type::real( 0.0 ), Type::real( 0.0 ), Type::real( 4.4503128927524089e+0 ), Type::real( 1.8915178993145004e+0 ), Type::real( -5.8012039600105848e+0 ), Type::real( 3.1116436695781989e-1 ), Type::real( -1.5216094966251608e-1 ), Type::real( 2.0136540080403035e-1 ), Type::real( 4.4710615727772591e-2 ) );

                         ERROR_K( 12, Type::real( 4.1173689122373888e-2 ), Type::real( 0.0 ), Type::real( 0.0 ), Type::real( 0.0 ), Type::real( 0.0 ), Type::real( 5.6754693391286133e+0 ), Type::real( 2.3872768489717506e+0 ), Type::real( -7.4655811424655713e+0 ), Type::real( 6.6149321570779360e-1 ), Type::real( -4.8634006837553356e-1 ), Type::real( 1.1944219431891464e-1 ), Type::real( 6.7065923591658886e-2 ) );

        );
        auto msum = matrix.buffer_wavefunction_plus.transformReduce( Type::complex( 0.0 ), CUDAMatrix<Type::complex>::transform_abs2(), CUDAMatrix<Type::complex>::transform_sum() );
        Type::real normalization_factor = CUDA::real( msum );
        Type::real integrated_error = matrix.rk_error.sum();

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