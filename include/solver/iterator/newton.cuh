#pragma once
#include "solver/solver.hpp"

namespace PHOENIX {

class Newton : public Solver {
   public:
    Newton( SystemParameters& system );

    void step( bool variable_time_step );
};

} // namespace PHOENIX