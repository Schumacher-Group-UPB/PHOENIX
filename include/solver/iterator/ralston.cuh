#pragma once
#include "solver/solver.hpp"

namespace PHOENIX {

class Ralston : public Solver {
   public:
    Ralston( SystemParameters& system );

    void step( bool variable_time_step );
};

class Ralston3 : public Solver {
   public:
    Ralston3( SystemParameters& system );

    void step( bool variable_time_step );
};

class Ralston4 : public Solver {
   public:
    Ralston4( SystemParameters& system );

    void step( bool variable_time_step );
};

} // namespace PHOENIX