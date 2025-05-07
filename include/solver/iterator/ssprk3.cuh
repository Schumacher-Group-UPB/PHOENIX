#pragma once
#include "solver/solver.hpp"

namespace PHOENIX {

class SSPRK3 : public Solver {
   public:
    SSPRK3( SystemParameters& system );

    void step( bool variable_time_step );
};

} // namespace PHOENIX