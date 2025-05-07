#pragma once
#include "solver/solver.hpp"

namespace PHOENIX {

class NSRK78 : public Solver {
   public:
    NSRK78( SystemParameters& system );

    void step( bool variable_time_step );
};

} // namespace PHOENIX