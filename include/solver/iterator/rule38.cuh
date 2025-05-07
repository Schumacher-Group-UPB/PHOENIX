#pragma once
#include "solver/solver.hpp"

namespace PHOENIX {

class Rule38 : public Solver {
   public:
    Rule38( SystemParameters& system );

    void step( bool variable_time_step );
};

} // namespace PHOENIX