#pragma once
#include "solver/solver.hpp"

namespace PHOENIX {

class SSFM : public Solver {
   public:
    SSFM( SystemParameters& system );

    void step( bool variable_time_step );
};

} // namespace PHOENIX