#pragma once
#include "solver/solver.hpp"

namespace PHOENIX {

class Heun2 : public Solver {
   public:
    Heun2( SystemParameters& system );

    void step( bool variable_time_step );
};

class Heun3 : public Solver {
   public:
    Heun3( SystemParameters& system );

    void step( bool variable_time_step );
};
} // namespace PHOENIX