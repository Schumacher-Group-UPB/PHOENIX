#include "system/noise.hpp"
#include <algorithm>
#include <cmath>
#include <numeric>
#include <random>
#include <vector>

namespace PHOENIX::Noise {

// ============================================================
// Internal helpers
// ============================================================

// Single-channel separable Gaussian convolution.
// sigma_x / sigma_y are in pixel units.
// Clamps at borders (zero-flux boundary).
static void gaussianConvolve2D( const std::vector<Type::real>& src,
                                std::vector<Type::real>&       dst,
                                size_t N_c, size_t N_r,
                                Type::real sigma_x, Type::real sigma_y ) {
    const size_t N = N_c * N_r;

    // Build normalised 1-D kernels
    auto makeKernel = []( Type::real sigma ) -> std::vector<Type::real> {
        const int r = std::max( 1, (int)std::ceil( 3.0 * sigma ) );
        std::vector<Type::real> k( 2 * r + 1 );
        Type::real sum = 0;
        for ( int i = -r; i <= r; ++i ) {
            k[i + r] = std::exp( -0.5 * ( i / sigma ) * ( i / sigma ) );
            sum += k[i + r];
        }
        for ( auto& v : k ) v /= sum;
        return k;
    };

    std::vector<Type::real> kx = makeKernel( sigma_x );
    std::vector<Type::real> ky = makeKernel( sigma_y );
    const int rx = (int)kx.size() / 2;
    const int ry = (int)ky.size() / 2;

    // Horizontal pass (vary column, fixed row)
    std::vector<Type::real> tmp( N, 0 );
    for ( int r = 0; r < (int)N_r; ++r ) {
        for ( int c = 0; c < (int)N_c; ++c ) {
            Type::real acc = 0;
            for ( int k = -rx; k <= rx; ++k ) {
                const int cc = std::clamp( c + k, 0, (int)N_c - 1 );
                acc += kx[k + rx] * src[r * N_c + cc];
            }
            tmp[r * N_c + c] = acc;
        }
    }

    // Vertical pass (vary row, fixed column)
    dst.assign( N, 0 );
    for ( int r = 0; r < (int)N_r; ++r ) {
        for ( int c = 0; c < (int)N_c; ++c ) {
            Type::real acc = 0;
            for ( int k = -ry; k <= ry; ++k ) {
                const int rr = std::clamp( r + k, 0, (int)N_r - 1 );
                acc += ky[k + ry] * tmp[rr * N_c + c];
            }
            dst[r * N_c + c] = acc;
        }
    }
}

// Compute RMS of a buffer; returns 1 if all-zero to avoid divide-by-zero.
static Type::real computeRMS( const std::vector<Type::real>& v ) {
    const Type::real mean_sq = std::transform_reduce(
        v.begin(), v.end(), Type::real( 0 ),
        std::plus<>{}, []( Type::real x ) { return x * x; } ) / (Type::real)v.size();
    const Type::real rms = std::sqrt( mean_sq );
    return rms > 0 ? rms : Type::real( 1 );
}

// ============================================================
// addUniformNoise
// ============================================================

void addUniformNoise( Type::complex* buf, size_t N,
                      Type::real amplitude, uint32_t seed ) {
    std::mt19937 gen{ seed };
    std::uniform_real_distribution<Type::real> dist{ -amplitude, amplitude };
    for ( size_t i = 0; i < N; ++i )
        buf[i] += Type::complex{ dist( gen ), dist( gen ) };
}

void addUniformNoise( Type::real* buf, size_t N,
                      Type::real amplitude, uint32_t seed ) {
    std::mt19937 gen{ seed };
    std::uniform_real_distribution<Type::real> dist{ -amplitude, amplitude };
    for ( size_t i = 0; i < N; ++i )
        buf[i] += dist( gen );
}

// ============================================================
// addGaussianNoise
// ============================================================

void addGaussianNoise( Type::complex* buf, size_t N,
                       Type::real amplitude, uint32_t seed ) {
    std::mt19937 gen{ seed };
    std::normal_distribution<Type::real> dist{ 0, amplitude };
    for ( size_t i = 0; i < N; ++i )
        buf[i] += Type::complex{ dist( gen ), dist( gen ) };
}

void addGaussianNoise( Type::real* buf, size_t N,
                       Type::real amplitude, uint32_t seed ) {
    std::mt19937 gen{ seed };
    std::normal_distribution<Type::real> dist{ 0, amplitude };
    for ( size_t i = 0; i < N; ++i )
        buf[i] += dist( gen );
}

// ============================================================
// addCorrelatedNoise (complex)
// ============================================================

void addCorrelatedNoise( Type::complex* buf, size_t N_c, size_t N_r,
                         Type::real amplitude, uint32_t seed,
                         Type::real correlation_length,
                         Type::real dx, Type::real dy ) {
    const size_t N = N_c * N_r;

    // Sigma in pixel units; fall back to plain Gaussian noise if < 0.5 px
    const Type::real sx = correlation_length / dx;
    const Type::real sy = correlation_length / dy;
    if ( sx < 0.5 && sy < 0.5 ) {
        addGaussianNoise( buf, N, amplitude, seed );
        return;
    }
    const Type::real clamped_sx = std::max( sx, Type::real( 0.5 ) );
    const Type::real clamped_sy = std::max( sy, Type::real( 0.5 ) );

    std::mt19937 gen{ seed };
    std::normal_distribution<Type::real> dist{ 0, 1 };

    // Generate white noise for real and imaginary channels
    std::vector<Type::real> white_re( N ), white_im( N );
    for ( auto& v : white_re ) v = dist( gen );
    for ( auto& v : white_im ) v = dist( gen );

    // Convolve each channel
    std::vector<Type::real> corr_re, corr_im;
    gaussianConvolve2D( white_re, corr_re, N_c, N_r, clamped_sx, clamped_sy );
    gaussianConvolve2D( white_im, corr_im, N_c, N_r, clamped_sx, clamped_sy );

    // Normalise to target amplitude and accumulate
    const Type::real scale_re = amplitude / computeRMS( corr_re );
    const Type::real scale_im = amplitude / computeRMS( corr_im );
    for ( size_t i = 0; i < N; ++i )
        buf[i] += Type::complex{ corr_re[i] * scale_re, corr_im[i] * scale_im };
}

// ============================================================
// addCorrelatedNoise (real)
// ============================================================

void addCorrelatedNoise( Type::real* buf, size_t N_c, size_t N_r,
                         Type::real amplitude, uint32_t seed,
                         Type::real correlation_length,
                         Type::real dx, Type::real dy ) {
    const size_t N = N_c * N_r;

    const Type::real sx = correlation_length / dx;
    const Type::real sy = correlation_length / dy;
    if ( sx < 0.5 && sy < 0.5 ) {
        addGaussianNoise( buf, N, amplitude, seed );
        return;
    }
    const Type::real clamped_sx = std::max( sx, Type::real( 0.5 ) );
    const Type::real clamped_sy = std::max( sy, Type::real( 0.5 ) );

    std::mt19937 gen{ seed };
    std::normal_distribution<Type::real> dist{ 0, 1 };

    std::vector<Type::real> white( N );
    for ( auto& v : white ) v = dist( gen );

    std::vector<Type::real> corr;
    gaussianConvolve2D( white, corr, N_c, N_r, clamped_sx, clamped_sy );

    const Type::real scale = amplitude / computeRMS( corr );
    for ( size_t i = 0; i < N; ++i )
        buf[i] += corr[i] * scale;
}

} // namespace PHOENIX::Noise
