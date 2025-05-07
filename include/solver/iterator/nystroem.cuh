#pragma once
#include "solver/solver.hpp"

namespace PHOENIX {

class Nystroem : public Solver {
   public:
    Nystroem( SystemParameters& system );

    void step( bool variable_time_step );
};

} // namespace PHOENIX