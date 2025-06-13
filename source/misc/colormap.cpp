#include <fstream>
#include <cmath>
#include <iostream>
#include "misc/colormap.hpp"
#include "misc/commandline_io.hpp"

// TODO: optional: return as tuple (with std::tie(r,g,b)) such that the Color class is not needed outside this class
ColorPalette::Color &ColorPalette::getColor( double value, bool invert, bool cutoff ) {
    if (std::isnan(value))
        return black;
    if ( value == 0 && cutoff )
        return black;
    if ( invert )
        value = std::abs( 1.0 - value );
    int indx = ( (int)( value * numberOfOutputColors ) ) % numberOfOutputColors;
    // std::cout << "returning color for index "<< indx << "; r = " << output_colors[indx].r << ", g = " << output_colors[indx].g << ", b = " << output_colors[indx].b <<std::endl;
    return output_colors[indx];
}

/*
    Read colormalette from TXT file. Colors can be either hex or r g b values
*/
void ColorPalette::readColorPaletteFromTXT( std::string filepath, int repetitions ) {
    std::cout << PHOENIX::CLIO::prettyPrint( "Loading .txt colormap from " + filepath, PHOENIX::CLIO::Control::Info ) << std::endl;
    for ( int o = 0; o < repetitions; o++ ) {
        std::ifstream file( filepath );
        std::string str;
        while ( std::getline( file, str ) ) {
            // Check if line starts with #
            if ( str.at( 0 ) == '#' ) {
                int r = (int)std::strtol( str.substr( 0, 2 ).c_str(), NULL, 16 );
                int g = (int)std::strtol( str.substr( 2, 2 ).c_str(), NULL, 16 );
                int b = (int)std::strtol( str.substr( 4, 2 ).c_str(), NULL, 16 );
                input_colors.push_back( Color( r, g, b ) );
                continue;
            }
            // Split line by ' '
            std::vector<std::string> line;
            std::string word = "";
            for ( auto x : str ) {
                if ( x == ' ' ) {
                    line.push_back( word );
                    word = "";
                } else {
                    word = word + x;
                }
            }
            line.push_back( word );
            int r = std::stoi( line[0] );
            int g = std::stoi( line[1] );
            int b = std::stoi( line[2] );
            input_colors.push_back( Color( r, g, b ) );
        }
    }
}

/*
    Reads gnuplot colorpalette .pal, converst contained hex colors to r,g,b and saves them into input_colors array
*/
void ColorPalette::readColorPaletteFromGnuplotDOTPAL( std::string filepath, int repetitions ) {
    std::cout << PHOENIX::CLIO::prettyPrint( "Loading .pal gnuplot colormap from " + filepath, PHOENIX::CLIO::Control::Info ) << std::endl;
    for ( int o = 0; o < repetitions; o++ ) {
        std::ifstream file( filepath );
        std::string str;
        bool startfound = false;
        int i = 0;
        int j = 0;
        std::vector<int> color;
        while ( std::getline( file, str ) ) {
            if ( str.size() < 6 )
                continue;
            if ( str.substr( 0, 19 ).compare( "set palette defined" ) == 0 ) {
                startfound = true;
                i = 19;
            }
            // Assuming Hex Colors
            if ( startfound ) {
                int pos = str.find( "#" );
                if ( pos > 0 && pos < 1E4 ) {
                    str = str.substr( pos + 1, 6 );
                    int r = (int)std::strtol( str.substr( 0, 2 ).c_str(), NULL, 16 );
                    int g = (int)std::strtol( str.substr( 2, 2 ).c_str(), NULL, 16 );
                    int b = (int)std::strtol( str.substr( 4, 2 ).c_str(), NULL, 16 );
                    input_colors.push_back( Color( r, g, b ) );
                }
                // Assuming 0-1 RGB range colors
                else {
                    color.clear();
                    // Find first non-space value (integer)
                    while ( i < str.size() && str.at( i ) == ' ' ) i++;
                    // Skip the integer
                    while ( i < str.size() && str.at( i ) != ' ' ) i++;
                    for ( int k = 0; k < 3; k++ ) {
                        if ( i >= str.size() ) {
                            k = 3;
                            break;
                        }
                        // Skip the spaces
                        while ( str.at( i ) == ' ' || str.at( i ) == '(' ) i++;
                        j = i;
                        // Parse value
                        while ( str.at( i ) != ' ' && str.at( i ) != ',' && str.at( i ) != ')' ) i++;
                        color.push_back( (int)( 255.0 * std::strtod( str.substr( j, i - j ).c_str(), NULL ) ) );
                    }
                    if ( color.size() == 3 )
                        input_colors.push_back( Color( color.at( 0 ), color.at( 1 ), color.at( 2 ) ) );
                    i = 0;
                    j = 0;
                }
            }
        }
    }
}

double ColorPalette::lerp( double v0, double v1, double t ) {
    return ( 1.0 - t ) * v0 + t * v1;
}

void ColorPalette::initColors() {
    int intermediateColors = std::floor( numberOfOutputColors / input_colors.size() );
    // Creating interpolation list for colors
    for ( int c = 0; c < input_colors.size() - 1; c++ ) {
        ;
        for ( int i = 0; i < intermediateColors; i++ ) {
            int r = (int)( lerp( input_colors[c].r, input_colors[( c + 1 ) % input_colors.size()].r, (double)( i ) / intermediateColors ) );
            int g = (int)( lerp( input_colors[c].g, input_colors[( c + 1 ) % input_colors.size()].g, (double)( i ) / intermediateColors ) );
            int b = (int)( lerp( input_colors[c].b, input_colors[( c + 1 ) % input_colors.size()].b, (double)( i ) / intermediateColors ) );
            output_colors.push_back( Color( r, g, b ) );
        }
    }
    numberOfOutputColors = output_colors.size();
}