#pragma once

#include "system/system_parameters.hpp"
#include "solver/solver.hpp"

// Include all the solvers here
#include "solver/iterator/runge_kutta.cuh"
#include "solver/iterator/bogacki.cuh"
#include "solver/iterator/cash_karp.cuh"
#include "solver/iterator/midpoint.cuh"
#include "solver/iterator/heun.cuh"
#include "solver/iterator/houwen_wray.cuh"
#include "solver/iterator/newton.cuh"
#include "solver/iterator/nsrk78.cuh"
#include "solver/iterator/ssprk3.cuh"
#include "solver/iterator/nystroem.cuh"
#include "solver/iterator/fehlberg.cuh"
#include "solver/iterator/dormand_prince.cuh"

#include <unordered_map>
#include <memory>
#include <functional>
#include <string>
#include <vector>
#include <stdexcept>
#include <utility>
#include <type_traits>

namespace PHOENIX {

class SolverFactory {
   public:
    using Creator = std::function<std::unique_ptr<Solver>( SystemParameters& )>;

    using Adaptive = std::true_type;
    using Fixed = std::false_type;

    struct Info {
        std::string description;
        bool is_adaptive;
    };
    struct SolverInfo {
        Info info;
        Creator creator;
    };

    // Register a solver with key, description, and creation function
    static void register_solver( const std::string& key, const std::string& description, const bool is_adaptive, Creator creator ) {
        registry_[key] = SolverInfo{ {description, is_adaptive}, std::move( creator ) };
    }

    // Create a solver based on the iterator name in system parameters
    static std::unique_ptr<Solver> create( SystemParameters& system ) {
        const auto& key = system.iterator;
        auto it = registry_.find( key );
        if ( it != registry_.end() ) {
            return it->second.creator( system );
        }
        throw std::invalid_argument( "Unknown solver: " + key );
    }

    // List of available solver keys and their descriptions
    static std::map<std::string, Info> available_solvers() {
        std::map<std::string, Info> result;
        for ( const auto& [key, el] : registry_ ) {
            result[key] = el.info;
        }
        return result;
    }

   private:
    static inline std::unordered_map<std::string, SolverInfo> registry_;
};

// Registration macro
#define REGISTER_SOLVER( KEY, CLASS, ADAPTIVE, DESCRIPTION )                                                                                                       \
    namespace {                                                                                                                                                    \
    struct CLASS##Registrator {                                                                                                                                    \
        CLASS##Registrator() {                                                                                                                                     \
            PHOENIX::SolverFactory::register_solver( KEY, DESCRIPTION, ADAPTIVE,[]( PHOENIX::SystemParameters & sys ) { return std::make_unique<CLASS>( sys ); } ); \
        }                                                                                                                                                          \
    };                                                                                                                                                             \
    static CLASS##Registrator reg_##CLASS;                                                                                                                         \
    }

} // namespace PHOENIX
