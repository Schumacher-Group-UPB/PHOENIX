#pragma once
#include "solver/solver.hpp"

namespace PHOENIX {

class MidPoint : public Solver {
   public:
    MidPoint( SystemParameters& system );

    void step( bool variable_time_step );
};
} // namespace PHOENIX