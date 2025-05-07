#pragma once
#include "solver/solver.hpp"

namespace PHOENIX {

class DormandPrince45 : public Solver {
   public:
    DormandPrince45( SystemParameters& system );

    void step( bool variable_time_step );
};

class DormandPrince85 : public Solver {
   public:
    DormandPrince85( SystemParameters& system );

    void step( bool variable_time_step );
};

} // namespace PHOENIX