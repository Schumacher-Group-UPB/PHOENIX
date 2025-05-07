#pragma once
#include "solver/solver.hpp"

namespace PHOENIX {

class HouwenWray : public Solver {
   public:
    HouwenWray( SystemParameters& system );

    void step( bool variable_time_step );
};

} // namespace PHOENIX