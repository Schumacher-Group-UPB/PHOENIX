#pragma once
#include <vector>
#include <string>
#include <fstream>
#include <numeric>
#include <typeinfo>
#include <cassert>

#include "cuda/typedef.cuh"

namespace PHOENIX::simple_npy {

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
std::vector<char> create_npy_header( const std::vector<size_t>& shape ) {
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

    std::vector<char> final_header = { char( 0x93 ), 'N', 'U', 'M', 'P', 'Y', 0x01, 0x00 };
    uint16_t header_len = static_cast<uint16_t>( header.size() );
    final_header.push_back( header_len & 0xFF );
    final_header.push_back( ( header_len >> 8 ) & 0xFF );
    final_header.insert( final_header.end(), header.begin(), header.end() );

    return final_header;
}

// Specialization for complex numbers: Ensure (real, imag) pairs are stored correctly
std::vector<Type::real> flatten_complex_data(const std::vector<Type::complex>& complex_data) {
    std::vector<Type::real> flat_data(complex_data.size() * 2);
    for (size_t i = 0; i < complex_data.size(); ++i) {
        flat_data[2 * i] = complex_data[i].real();
        flat_data[2 * i + 1] = complex_data[i].imag();
    }
    return flat_data;
}

template <typename T>
void save_npy( std::ofstream& fstream, const std::vector<T>& data, size_t rows, size_t cols ) {
    std::vector<size_t> shape = { rows, cols };
    std::vector<char> header = create_npy_header<T>( shape );

    assert( fstream.is_open() && "Could not open file for writing." );

    fstream.write( header.data(), header.size() );
    fstream.write( reinterpret_cast<const char*>( data.data() ), rows * cols * sizeof( T ) );
    fstream.close();
}

// Overload for complex number saving
template <>
void save_npy<Type::complex>( std::ofstream& fstream, const std::vector<Type::complex>& data, size_t rows, size_t cols ) {
    std::vector<size_t> shape = { rows, cols };
    std::vector<char> header = create_npy_header<Type::complex>( shape );

    assert( fstream.is_open() && "Could not open file for writing." );

    std::vector<Type::real> flat_data = flatten_complex_data(data);

    fstream.write( header.data(), header.size() );
    fstream.write( reinterpret_cast<char*>( flat_data.data() ), flat_data.size() * sizeof( Type::real ) );
    fstream.close();
}

} // namespace PHOENIX::simple_npy
