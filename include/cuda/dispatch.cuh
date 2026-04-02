#pragma once
#include <type_traits>
#include <utility>

namespace PHOENIX::Dispatch {

namespace detail {

// The Dispatcher struct accumulates compile-time boolean types recursively.
// CompileTimeBools... grows with each recursion step.
template <typename... CompileTimeBools>
struct Dispatcher {
    // Base case: all runtime booleans consumed. Call f with the accumulated types.
    template <typename Func>
    static void run( Func &&f ) {
        f( CompileTimeBools{}... );
    }

    // Recursive case: consume one runtime bool, append true_type or false_type, recurse.
    template <typename Func, typename... Rest>
    static void run( Func &&f, bool current, Rest... rest ) {
        if ( current ) {
            Dispatcher<CompileTimeBools..., std::true_type>::run( std::forward<Func>( f ), rest... );
        } else {
            Dispatcher<CompileTimeBools..., std::false_type>::run( std::forward<Func>( f ), rest... );
        }
    }
};

} // namespace detail

// Public entry point: maps runtime boolean arguments to compile-time type parameters.
// Usage:
//   PHOENIX::Dispatch::dispatch( [&](auto a_t, auto b_t) {
//       constexpr bool a = decltype(a_t)::value;
//       constexpr bool b = decltype(b_t)::value;
//       my_kernel<a, b><<<grid, block>>>(args);
//   }, runtime_bool_a, runtime_bool_b );
template <typename Func, typename... Bools>
inline void dispatch( Func &&f, Bools... bools ) {
    detail::Dispatcher<>::run( std::forward<Func>( f ), bools... );
}

} // namespace PHOENIX::Dispatch
