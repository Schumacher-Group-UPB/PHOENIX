#pragma once
#include "solver/solver.hpp"

namespace PHOENIX {

class CashKarp : public Solver {
   public:
    CashKarp( SystemParameters& system );

    void step( bool variable_time_step );
};

} // namespace PHOENIX