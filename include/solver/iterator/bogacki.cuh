#pragma once
#include "solver/solver.hpp"

namespace PHOENIX {

class BogackiShampine : public Solver {
   public:
    BogackiShampine( SystemParameters& system );

    void step( bool variable_time_step );
};

} // namespace PHOENIX