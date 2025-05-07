#pragma once
#include "solver/solver.hpp"

namespace PHOENIX {

class Fehlberg2 : public Solver {
   public:
    Fehlberg2( SystemParameters& system );

    void step( bool variable_time_step );
};

class Fehlberg5 : public Solver {
   public:
    Fehlberg5( SystemParameters& system );

    void step( bool variable_time_step );
};

} // namespace PHOENIX