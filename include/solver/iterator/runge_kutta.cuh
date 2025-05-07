#pragma once
#include "solver/solver.hpp"

namespace PHOENIX {

class RungeKutta3 : public Solver {
   public:
    RungeKutta3( SystemParameters& system );

    void step( bool variable_time_step );
};

class RungeKutta4 : public Solver {
   public:
    RungeKutta4( SystemParameters& system );

    void step( bool variable_time_step );
};

} // namespace PHOENIX