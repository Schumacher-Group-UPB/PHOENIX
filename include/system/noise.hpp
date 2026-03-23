#pragma once

#include <cstdint>
#include "cuda/typedef.cuh"

namespace PHOENIX::Noise {

// ---------------------------------------------------------------------------
// Uniform white noise  [-amplitude, +amplitude] on each real/imag channel
// ---------------------------------------------------------------------------
void addUniformNoise( Type::complex* buf, size_t N,
                      Type::real amplitude, uint32_t seed );
void addUniformNoise( Type::real* buf, size_t N,
                      Type::real amplitude, uint32_t seed );

// ---------------------------------------------------------------------------
// Gaussian (normal) white noise, std-dev = amplitude
// ---------------------------------------------------------------------------
void addGaussianNoise( Type::complex* buf, size_t N,
                       Type::real amplitude, uint32_t seed );
void addGaussianNoise( Type::real* buf, size_t N,
                       Type::real amplitude, uint32_t seed );

// ---------------------------------------------------------------------------
// Spatially correlated Gaussian noise
// Generated as white Gaussian noise convolved with a 2-D separable Gaussian
// filter of width correlation_length (same physical units as dx / dy).
// The result is rescaled so its RMS equals amplitude before being added to buf.
// ---------------------------------------------------------------------------
void addCorrelatedNoise( Type::complex* buf, size_t N_c, size_t N_r,
                         Type::real amplitude, uint32_t seed,
                         Type::real correlation_length,
                         Type::real dx, Type::real dy );
void addCorrelatedNoise( Type::real* buf, size_t N_c, size_t N_r,
                         Type::real amplitude, uint32_t seed,
                         Type::real correlation_length,
                         Type::real dx, Type::real dy );

} // namespace PHOENIX::Noise
