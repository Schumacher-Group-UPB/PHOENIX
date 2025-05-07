#include <omp.h>
#include "cuda/typedef.cuh"
#include "kernel/kernel_compute.cuh"
#include "kernel/kernel_summation.cuh"
#include "kernel/kernel_halo.cuh"
#include "system/system_parameters.hpp"
#include "cuda/cuda_matrix.cuh"
#include "solver/iterator/dormand_prince.cuh"
#include "solver/solver_factory.hpp"

namespace PHOENIX {

// MARK: DormandPrince45
// ----------------------------------------------------------------------------------------------------- //
// ----------------------------------------- DormandPrince45 ------------------------------------------- //
// ----------------------------------------------------------------------------------------------------- //

DormandPrince45::DormandPrince45( SystemParameters& system ) : Solver( system ) {
    k_max_ = 7;
    halo_size_ = 7;
    is_adaptive_ = true;
    name_ = "Dormand–Prince 5(4)";
    description_ = "Dormand–Prince 5(4) method for time integration.";
    butcher_tableau_ =
        "     0.0      | 0.0          0.0         0.0          0.0       0.0           0.0        0.0     \n"
        "     1.0/5.0  | 1.0/5.0      0.0         0.0          0.0       0.0           0.0        0.0     \n"
        "     3.0/10.0 | 3.0/40.0     9.0/40.0    0.0          0.0       0.0           0.0        0.0     \n"
        "     4.0/5.0  | 44.0/45.0   -56.0/15.0   32.0/9.0     0.0       0.0           0.0        0.0     \n"
        "     8.0/9    | 19372./6561 -25360./2187 64448./6561 -212./729  0.0           0.0        0.0     \n"
        "     1.0      | 9017./3168  -355./33     46732./5247  49./176  -5103./18656   0.0        0.0     \n"
        "     1.0      | 35./384      0.0         500./1113    125./192 -2187./6784    11./84     0.0     \n"
        "     --------------------------------------------------------------------------------------------\n"
        "              | 35./384      0.0         500./1113    125./192 -2187./6784    11./84     0.0     \n"
        "              | 5179./57600  0.0         7571./16695  393./640 -92097./339200 187./2100  1.0/40.0";
}

void DormandPrince45::step( bool variable_time_step ) {
    bool cuda_graph = !variable_time_step;
    bool accept = !variable_time_step; // If we are not using variable time step, we can accept the solution right away.

    do {
        SOLVER_SEQUENCE(
            cuda_graph /*Capture CUDA Graph*/,

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
            
            if ( !variable_time_step ) { 
                
                FINAL_SUM_K( 6, Type::real( 35.0 / 384.0 ), Type::real( 0.0 ), Type::real( 500.0 / 1113.0 ), Type::real( 125.0 / 192.0 ), Type::real( -2187.0 / 6784.0 ), Type::real( 11.0 / 84.0 ) ); 
            
            } else {
                
                INTERMEDIATE_SUM_K( 6, Type::real( 35.0 / 384.0 ), Type::real( 0.0 ), Type::real( 500.0 / 1113.0 ), Type::real( 125.0 / 192.0 ), Type::real( -2187.0 / 6784.0 ), Type::real( 11.0 / 84.0 ) );

                // For DP, we need the 7th k
                CALCULATE_K( 7, Type::real( 1.0 ), buffer_wavefunction, buffer_reservoir );

                ERROR_K( 7, Type::real( 35.0 / 384.0 - 5179.0 / 57600.0 ), Type::real( 0.0 ), Type::real( 500.0 / 1113.0 - 7571.0 / 16695.0 ), Type::real( 125.0 / 192.0 - 393.0 / 640.0 ), Type::real( -2187.0 / 6784.0 + 92097.0 / 339200.0 ), Type::real( 11.0 / 84.0 - 187.0 / 2100.0 ), Type::real( -1.0 / 40.0 ) );

                // Redo this sum so we get the correct solution in buffer_...
                INTERMEDIATE_SUM_K( 6, Type::real( 35.0 / 384.0 ), Type::real( 0.0 ), Type::real( 500.0 / 1113.0 ), Type::real( 125.0 / 192.0 ), Type::real( -2187.0 / 6784.0 ), Type::real( 11.0 / 84.0 ) );
            } 
        );

        if ( !variable_time_step )
            return;

        accept = adaptTimeStep( 1.0 / 4.0, false );

        if ( accept ) {
            swapBuffers();
        }

    } while ( !accept );
}

REGISTER_SOLVER( "DP45", DormandPrince45, true, "Dormand–Prince 5(4) method for time integration." );

// MARK: DormandPrince85
// ----------------------------------------------------------------------------------------------------- //
// ----------------------------------------- DormandPrince85 ------------------------------------------- //
// ----------------------------------------------------------------------------------------------------- //

DormandPrince85::DormandPrince85( SystemParameters& system ) : Solver( system ) {
    k_max_ = 12;
    halo_size_ = 12;
    is_adaptive_ = true;
    name_ = "Dormand–Prince 8(5)";
    description_ = "Dormand–Prince 8(5) method for time integration.";
    butcher_tableau_ =
        "     0.0           |  0.0           0.0            0.0            0.0           0.0            0.0            0.0             0.0          0.0             0.0            0.0           0.0\n"
        "     0.05260015196 |  0.05260015196 0.0            0.0            0.0           0.0            0.0            0.0             0.0          0.0             0.0            0.0           0.0\n"
        "     0.07890022794 |  0.01972505698 0.05917517095  0.0            0.0           0.0            0.0            0.0             0.0          0.0             0.0            0.0           0.0\n"
        "     0.1183503419  |  0.02958758548 0.0            0.08876275643  0.0           0.0            0.0            0.0             0.0          0.0             0.0            0.0           0.0\n"
        "     0.2816496581  |  0.2413651342  0.0           -0.8845494793   0.9248340033  0.0            0.0            0.0             0.0          0.0             0.0            0.0           0.0\n"
        "     0.3333333333  |  0.03703703704 0.0            0.0            0.1708286087  0.1254676876   0.0            0.0             0.0          0.0             0.0            0.0           0.0\n"
        "     0.25          |  0.03710937500 0.0            0.0            0.1702522110  0.06021653898 -0.01757812500  0.0             0.0          0.0             0.0            0.0           0.0\n"
        "     0.3076923077  |  0.03709200012 0.0            0.0            0.1703839257  0.1072620304  -0.01531943775  0.008273789164  0.0          0.0             0.0            0.0           0.0\n"
        "     0.6512820513  |  0.6241109587  0.0            0.0           -3.360892629  -0.8682193468   27.592099699   20.15406755    -43.48988418  0.0             0.0            0.0           0.0\n"
        "     0.6           |  0.4776625364  0.0            0.0           -2.488114620  -0.5902908268   21.23005145    15.27923363    -33.28821097  -0.02033120171  0.0            0.0           0.0\n"
        "     0.8571428571  | -0.9371424301  0.0            0.0            5.186372429   1.091437349   -8.149787011   -18.52006566     22.73948710   2.493605553   -3.046764472    0.0           0.0\n"
        "     1.0           |  2.273310148   0.0            0.0           -10.534495467 -2.000872058   -17.958931863   27.94888453    -2.858998277  -8.872856934    12.36056718    0.643392746   0.0\n"
        "     ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------\n"
        "     0.0           |  0.0542937341  0.0            0.0            0.0           0.0            4.450312893    1.891517899    -5.801203960   0.311164367    -0.1521609497  0.2013654008  0.04471061573\n"
        "     0.0           |  0.0131200449  0.0            0.0            0.0           0.0           -1.225156446   -0.4957589       1.664377182  -0.350328848     0.3341791187  0.0819232064 -0.02235530786";
}

void DormandPrince85::step( bool variable_time_step ) {
    bool cuda_graph = !variable_time_step;
    bool accept = !variable_time_step; // If we are not using variable time step, we can accept the solution right away.

    do {
        SOLVER_SEQUENCE(
            cuda_graph /*Capture CUDA Graph*/,

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

            if ( variable_time_step ) {

                FINAL_SUM_K( 12, Type::real( 5.4293734116568762e-2 ), Type::real( 0.0 ), Type::real( 0.0 ), Type::real( 0.0 ), Type::real( 0.0 ), Type::real( 4.4503128927524089e+0 ), Type::real( 1.8915178993145004e+0 ), Type::real( -5.8012039600105848e+0 ), Type::real( 3.1116436695781989e-1 ), Type::real( -1.5216094966251608e-1 ), Type::real( 2.0136540080403035e-1 ), Type::real( 4.4710615727772591e-2 ) );
            } else {

                INTERMEDIATE_SUM_K( 12, Type::real( 5.4293734116568762e-2 ), Type::real( 0.0 ), Type::real( 0.0 ), Type::real( 0.0 ), Type::real( 0.0 ), Type::real( 4.4503128927524089e+0 ), Type::real( 1.8915178993145004e+0 ), Type::real( -5.8012039600105848e+0 ), Type::real( 3.1116436695781989e-1 ), Type::real( -1.5216094966251608e-1 ), Type::real( 2.0136540080403035e-1 ), Type::real( 4.4710615727772591e-2 ) );

                ERROR_K( 12, Type::real( 4.1173689122373888e-2 ), Type::real( 0.0 ), Type::real( 0.0 ), Type::real( 0.0 ), Type::real( 0.0 ), Type::real( 5.6754693391286133e+0 ), Type::real( 2.3872768489717506e+0 ), Type::real( -7.4655811424655713e+0 ), Type::real( 6.6149321570779360e-1 ), Type::real( -4.8634006837553356e-1 ), Type::real( 1.1944219431891464e-1 ), Type::real( 6.7065923591658886e-2 ) );
            }

        );

        if ( !variable_time_step )
            return;

        accept = adaptTimeStep( 1.0 / 4.0, false );

        if ( accept ) {
            swapBuffers();
        }

    } while ( !accept );
}

REGISTER_SOLVER( "DP85", DormandPrince85, true, "Dormand–Prince 8(5) method for time integration." );

} // namespace PHOENIX