#pragma once

#include <map>
#include <iomanip>
#include <filesystem>
#include <vector>
#include <string>
#include <queue>
#include <thread>
#include <mutex>
#include <condition_variable>
#include <fstream>
#include <sstream>
#include <iostream>
#include <complex>
#include <variant>
#include "cuda/typedef.cuh"

namespace PHOENIX {

class FileHandler {
   public:
    std::map<std::string, std::ofstream> files;
    std::string outputPath, outputName, color_palette, color_palette_phase;

    FileHandler();
    FileHandler( int argc, char** argv );
    FileHandler( FileHandler& other ) = delete;
    ~FileHandler();

    struct Header {
        // Spatial Parameters
        Type::real L_x, L_y;
        Type::real dx, dy;
        // Time Parameter
        Type::real t;
        // Oscillator Parameters
        Type::real t0, freq, sigma;

        Header() : L_x( 0 ), L_y( 0 ), dx( 0 ), dy( 0 ), t( 0 ), t0( 0 ), freq( 0 ), sigma( 0 ) {
        }
        Header( Type::real L_x, Type::real L_y, Type::real dx, Type::real dy, Type::real t ) : Header() {
            this->L_x = L_x;
            this->L_y = L_y;
            this->dx = dx;
            this->dy = dy;
            this->t = t;
            this->t0 = 0;
            this->freq = 0;
            this->sigma = 0;
        }
        Header( Type::real L_x, Type::real L_y, Type::real dx, Type::real dy, Type::real t, Type::real t0, Type::real freq, Type::real sigma ) : Header() {
            this->L_x = L_x;
            this->L_y = L_y;
            this->dx = dx;
            this->dy = dy;
            this->t = t;
            this->t0 = t0;
            this->freq = freq;
            this->sigma = sigma;
        }

        friend std::ostream& operator<<( std::ostream& os, const Header& header ) {
            os << "LX " << header.L_x << " LY " << header.L_y << " DX " << header.dx << " DY " << header.dy << " TIME " << header.t;
            if ( header.t0 != 0 and header.freq != 0 and header.sigma != 0 )
                os << " OSC T0 " << header.t0 << " FREQ " << header.freq << " SIGMA " << header.sigma;
            return os;
        }
    };

    template <typename T>
    struct QueueItem {
        Type::host_vector<T> matrix;
        Type::uint32 N_c, N_r;
        Type::uint32  start_c, end_c, start_r, end_r, increment;
        Header header;
        std::string fpath;
    };

    std::queue<std::variant<QueueItem<Type::complex>, QueueItem<Type::real>>> matrixQueue;
    std::mutex queueMutex;
    std::condition_variable queueCondition;
    std::condition_variable completionCondition;
    std::vector<std::thread> workerThreads;
    bool stopWorker;

    std::string toPath( const std::string& name );

    std::ofstream& getFile( const std::string& name );

    bool loadMatrixFromFile( const std::string& filepath, Type::complex* buffer );
    bool loadMatrixFromFile( const std::string& filepath, Type::real* buffer );

    void outputMatrixToFile( const Type::complex* buffer, Type::uint32 col_start, Type::uint32 col_stop, Type::uint32 row_start, Type::uint32 row_stop, const Type::uint32 N_c, const Type::uint32 N_r, Type::uint32 increment, const Header& header, std::ofstream& out, const std::string& name );
    void outputMatrixToFile( const Type::complex* buffer, Type::uint32 col_start, Type::uint32 col_stop, Type::uint32 row_start, Type::uint32 row_stop, const Type::uint32 N_c, const Type::uint32 N_r, Type::uint32 increment, const Header& header, const std::string& out );
    void outputMatrixToFile( const Type::complex* buffer, const Type::uint32 N_c, const Type::uint32 N_r, const Header& header, const std::string& out );
    void outputMatrixToFile( const Type::complex* buffer, const Type::uint32 N_c, const Type::uint32 N_r, const Header& header, std::ofstream& out, const std::string& name );

    void outputMatrixToFile( const Type::real* buffer, Type::uint32 col_start, Type::uint32 col_stop, Type::uint32 row_start, Type::uint32 row_stop, const Type::uint32 N_c, const Type::uint32 N_r, Type::uint32 increment, const Header& header, std::ofstream& out, const std::string& name );
    void outputMatrixToFile( const Type::real* buffer, Type::uint32 col_start, Type::uint32 col_stop, Type::uint32 row_start, Type::uint32 row_stop, const Type::uint32 N_c, const Type::uint32 N_r, Type::uint32 increment, const Header& header, const std::string& out );
    void outputMatrixToFile( const Type::real* buffer, const Type::uint32 N_c, const Type::uint32 N_r, const Header& header, const std::string& out );
    void outputMatrixToFile( const Type::real* buffer, const Type::uint32 N_c, const Type::uint32 N_r, const Header& header, std::ofstream& out, const std::string& name );

    std::vector<std::vector<Type::real>> loadListFromFile( const std::string& path, const std::string& name );
    void outputListToFile( const std::string& path, std::vector<std::vector<Type::real>>& data, const std::string& name );

    void init( int argc, char** argv );

    void processQueue();
    void waitForCompletion();
    // Queue matrix is same footprint as outputMatrixToFile, but with a queue
    void queueComplexMatrix( const Type::host_vector<Type::complex>& matrix, Type::uint32 col_start, Type::uint32 col_stop, Type::uint32 row_start, Type::uint32 row_stop, const Type::uint32 N_c, const Type::uint32 N_r, Type::uint32 increment, const Header& header, const std::string& out );
    void queueRealMatrix( const Type::host_vector<Type::real>& matrix, Type::uint32 col_start, Type::uint32 col_stop, Type::uint32 row_start, Type::uint32 row_stop, const Type::uint32 N_c, const Type::uint32 N_r, Type::uint32 increment, const Header& header, const std::string& out );
    };

std::vector<char*> readConfigFromFile( int argc, char** argv );

} // namespace PHOENIX