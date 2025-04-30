#pragma once
#include <vector>
#include <string>
#include <fstream>
#include <numeric>
#include <typeinfo>
#include <cassert>
#include <cstring>

#include "cuda/typedef.cuh"

namespace PHOENIX::Output {

char endian_char() {
    int x = 1;
    return ( *reinterpret_cast<char*>( &x ) ) ? '<' : '>';
}

template <typename T>
std::string type_char() {
    if constexpr ( std::is_same<T, float>::value )
        return "f4";
    if constexpr ( std::is_same<T, double>::value )
        return "f8";
    if constexpr ( std::is_same<T, int8_t>::value )
        return "i1";
    if constexpr ( std::is_same<T, int16_t>::value )
        return "i2";
    if constexpr ( std::is_same<T, int32_t>::value )
        return "i4";
    if constexpr ( std::is_same<T, int64_t>::value )
        return "i8";
    if constexpr ( std::is_same<T, uint8_t>::value )
        return "u1";
    if constexpr ( std::is_same<T, uint16_t>::value )
        return "u2";
    if constexpr ( std::is_same<T, uint32_t>::value )
        return "u4";
    if constexpr ( std::is_same<T, uint64_t>::value )
        return "u8";
    if constexpr ( std::is_same<T, bool>::value )
        return "b1";
    // Complex: NumPy stores as pairs (real, imag)
    if constexpr ( std::is_same<T, Type::complex>::value ) {
        if constexpr ( std::is_same<Type::real, float>::value ) return "c8";   // Complex float
        if constexpr ( std::is_same<Type::real, double>::value ) return "c16"; // Complex double
    }
    return "?"; // Unknown type
}

template <typename T>
std::vector<char> create_binary_header( const std::vector<size_t>& shape, const std::string& name ) {
    std::string header = "{'descr': '";
    header += endian_char();
    header += type_char<T>();
    header += "', 'fortran_order': False, 'shape': (";
    for ( size_t i = 0; i < shape.size(); ++i ) {
        if ( i > 0 )
            header += ", ";
        header += std::to_string( shape[i] );
    }
    if ( shape.size() == 1 )
        header += ",";
    header += "), }";

    while ( ( 10 + header.size() ) % 16 != 15 ) header += ' ';
    header += '\n';

    // Numpy magic string with header as text
    //{ char( 0x93 ), ... name ..., 0x01, 0x00 };
    std::vector<char> final_header;
    final_header.push_back( 0x93 );
    final_header.insert( final_header.end(), name.begin(), name.end() );
    final_header.push_back( 0x01 );
    final_header.push_back( 0x00 );

    uint16_t header_len = static_cast<uint16_t>( header.size() );
    final_header.push_back( header_len & 0xFF );
    final_header.push_back( ( header_len >> 8 ) & 0xFF );
    final_header.insert( final_header.end(), header.begin(), header.end() );

    return final_header;
}

// Specialization for complex numbers: Ensure (real, imag) pairs are stored correctly
// Interleaved: [real, imag, real, imag, ...]
// Non-interleaved: [real, real, ..., imag, imag, ...]
std::vector<Type::real> flatten_complex_data(const std::vector<Type::complex>& complex_data, bool interleaved = false) {
    std::vector<Type::real> flat_data(complex_data.size() * 2);
    
    if (interleaved) {
        for ( size_t i = 0; i < complex_data.size(); ++i ) {
            flat_data[2 * i] = complex_data[i].real();
            flat_data[2 * i + 1] = complex_data[i].imag();
        }
    } else {
        for ( size_t i = 0; i < complex_data.size(); ++i ) {
            flat_data[i] = complex_data[i].real();
            flat_data[complex_data.size() + i] = complex_data[i].imag();
        }
    }
    return flat_data;
}

template <typename T>
void save_binary( std::ofstream& fstream, const std::string& dtype, const std::vector<T>& data, size_t rows, size_t cols ) {
    std::vector<size_t> shape = { rows, cols };
    std::vector<char> header = create_binary_header<T>( shape, dtype );

    assert( fstream.is_open() && "Could not open file for writing." );

    fstream.write( header.data(), header.size() );
    fstream.write( reinterpret_cast<const char*>( data.data() ), rows * cols * sizeof( T ) );
}

// Overload for complex number saving
void save_binary( std::ofstream& fstream, const std::string& dtype, const std::vector<Type::complex>& data, size_t rows, size_t cols, bool interleaved ) {
    std::vector<size_t> shape = { rows, cols };
    std::vector<char> header = create_binary_header<Type::complex>( shape, dtype );

    assert( fstream.is_open() && "Could not open file for writing." );

    std::vector<Type::real> flat_data = flatten_complex_data( data, interleaved );

    fstream.write( header.data(), header.size() );
    fstream.write( reinterpret_cast<char*>( flat_data.data() ), flat_data.size() * sizeof( Type::real ) );
}

// ======================================================================================================================================
// Write MATLAB v4 .mat file
// ======================================================================================================================================
//
// The MATLAB v4 format is quite simple for a single matrix variable:
//   1) A 128‑byte descriptive text header (often "MATLAB 4.0 MAT‑file...").
//   2) An array header of 5 int32 fields:
//        type   (e.g. 0 == double matrix)
//        mrows  (# of rows)
//        ncols  (# of columns)
//        imagf  (1 if complex, 0 if real)
//        namelen (length of the variable name + 1 for '\0')
//   3) The variable name (null‑terminated)
//   4) The real part data, in column‑major order (mrows*ncols doubles).
//   5) If imagf==1, the imaginary part data, also mrows*ncols doubles.

#pragma pack( push, 1 )
struct MatlabV4ArrayHeader {
    int32_t type; // 0 == double
    int32_t mrows;
    int32_t ncols;
    int32_t imagf;   // 0 == real, 1 == complex
    int32_t namelen; // includes the null terminator
};
#pragma pack( pop )

// Helper: reorder a [rows x cols] buffer from row-major to column-major
// so that MATLAB interprets it in the usual way.  If your data is already
// column-major, you can skip this step.
template <typename T>
std::vector<T> rowMajorToColMajor( const std::vector<T>& src, size_t rows, size_t cols ) {
    std::vector<T> dst( rows * cols );
    for ( size_t j = 0; j < cols; ++j ) {
        for ( size_t i = 0; i < rows; ++i ) {
            // Source is row-major => index = i*cols + j
            // Destination is col-major => index = j*rows + i
            dst[j * rows + i] = src[i * cols + j];
        }
    }
    return dst;
}

// ======================================================================================================================================
// save_matlab4: Real T version
// ======================================================================================================================================
template <typename T>
void save_matlab4( std::ofstream& fstream, const std::string& var_name, const std::vector<T>& data, size_t rows, size_t cols ) {
    assert( fstream.is_open() && "Could not open file for writing in save_matlab4 (real)." );

    // 1) Write the 128‑byte descriptive text header
    {
        char header[128];
        std::memset( header, 0, 128 );
        const char* text = "MATLAB 4.0 MAT-file, Created by PHOENIX::Output";
        std::memcpy( header, text, std::min<size_t>( std::strlen( text ), 127 ) );
        fstream.write( header, 128 );
    }

    // 2) Fill the array header
    MatlabV4ArrayHeader array_header;
    array_header.type = 0; // 0 => T
    array_header.mrows = static_cast<int32_t>( rows );
    array_header.ncols = static_cast<int32_t>( cols );
    array_header.imagf = 0; // real
    // var_name.size() + 1 for null terminator
    array_header.namelen = static_cast<int32_t>( var_name.size() + 1 );

    fstream.write( reinterpret_cast<const char*>( &array_header ), sizeof( array_header ) );

    // 3) Write the variable name (null‑terminated)
    fstream.write( var_name.c_str(), var_name.size() + 1 );

    // 4) Reorder the real data to column-major; write it
    std::vector<T> colMajorData = rowMajorToColMajor( data, rows, cols );
    fstream.write( reinterpret_cast<const char*>( colMajorData.data() ), colMajorData.size() * sizeof( T ) );
}

// ======================================================================================================================================
// save_matlab4: Complex version
// ======================================================================================================================================
//
// We assume the input `data` may be interleaved or not, but we flatten to
// separate real block + separate imaginary block in column-major order.
// That is how MATLAB v4 expects complex data: real block, then imag block.

void save_matlab4_complex( std::ofstream& fstream, const std::string& var_name, const std::vector<Type::complex>& data, size_t rows, size_t cols ) {
    assert( fstream.is_open() && "Could not open file for writing in save_matlab4 (complex)." );

    // 1) 128‑byte descriptive text header
    {
        char header[128];
        std::memset( header, 0, 128 );
        const char* text = "MATLAB 4.0 MAT-file, Created by PHOENIX::Output (complex)";
        std::memcpy( header, text, std::min<size_t>( std::strlen( text ), 127 ) );
        fstream.write( header, 128 );
    }

    // 2) Array header
    MatlabV4ArrayHeader array_header;
    array_header.type = 0; // 0 => double
    array_header.mrows = static_cast<int32_t>( rows );
    array_header.ncols = static_cast<int32_t>( cols );
    array_header.imagf = 1; // 1 => complex
    array_header.namelen = static_cast<int32_t>( var_name.size() + 1 );

    fstream.write( reinterpret_cast<const char*>( &array_header ), sizeof( array_header ) );

    // 3) Write the variable name (null‑terminated)
    fstream.write( var_name.c_str(), var_name.size() + 1 );

    // 4) Flatten real & imag parts separately, then reorder each in column-major
    //    so that MATLAB sees them as the correct shape.
    //    We'll reuse flatten_complex_data() to get real+imag as separate blocks
    //    in a single vector, then split them again for column-major reordering.
    const size_t N = rows * cols;
    const std::vector<Type::real> flat_interleaved = flatten_complex_data( data, /*interleaved=*/false );
    // The above `false` means [all reals..., all imags...].
    // Reals occupy flat_interleaved[0 .. N-1]
    // Imags occupy flat_interleaved[N .. 2N-1]

    std::vector<Type::real> real_data( N ), imag_data( N );
    for ( size_t i = 0; i < N; ++i ) {
        real_data[i] = flat_interleaved[i];
        imag_data[i] = flat_interleaved[N + i];
    }

    // Now reorder to column-major:
    std::vector<Type::real> real_col = rowMajorToColMajor( real_data, rows, cols );
    std::vector<Type::real> imag_col = rowMajorToColMajor( imag_data, rows, cols );

    // 5) Write real block
    fstream.write( reinterpret_cast<const char*>( real_col.data() ), real_col.size() * sizeof( Type::real ) );

    // 6) Write imaginary block
    fstream.write( reinterpret_cast<const char*>( imag_col.data() ), imag_col.size() * sizeof( Type::real ) );
}

} // namespace PHOENIX::simple_binary
