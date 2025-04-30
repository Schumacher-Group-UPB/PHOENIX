#pragma once
#include <iostream>
#include <string>
#include <vector>
#include <map>
#include <memory>
#include <fstream>
#ifdef USE_CPU
    #include <algorithm>
    #include <ranges>
#endif
#include "cuda/typedef.cuh"
#include "cuda/cuda_macro.cuh"
#include "kernel/kernel_halo.cuh"
#include "misc/escape_sequences.hpp"
#include "cuda/cuda_matrix_base.hpp"
#include "misc/commandline_io.hpp"

namespace PHOENIX {

/**
 * @brief CUDA Wrapper for a matrix
 * Handles memory management and host-device synchronization when
 * using the getDevicePtr() and getHostPtr() functions.
 *
 * NEW: The main purpose of this class remains the communication between
 * the full size host matrices (NxN) and the device matrices, which are halo'ed
 * and may be composed of multiple MxM subgrids, each with its own device pointer.
 *
 * @tparam T either Type::real or Type::complex
 */
template <typename T>
class CUDAMatrix : CUDAMatrixBase {
   private:
    // Rows and Cols of the Matrix. These can be different, so rows =/= cols
    Type::uint32 rows, cols;
    Type::uint32 subgrid_rows, subgrid_cols, subgrid_rows_with_halo, subgrid_cols_with_halo;
    // The total Size of the Matrix = rows*cols. Used for allocation purposes.
    Type::uint32 total_size_host;
    Type::uint32 total_size_device;
    // The number of subgrids the device matrix is composed of
    Type::uint32 subgrids_columns, subgrids_rows;
    Type::uint32 total_num_subgrids;     // = subgrids_columns * subgrids_rows;
    Type::uint32 subgrid_size;           // = subgrid_rows * subgrid_cols;
    Type::uint32 subgrid_size_with_halo; // = subgrid_rows_with_halo * subgrid_cols_with_halo;
    // The size of the halo around each subgrid
    Type::uint32 halo_size;
    // The number of individual matrices inside this buffer. All matrices are chained after each other.
    Type::uint32 num_matrices;
    // Name of the Matrix. Mostly used for debugging purposes.
    std::string name;

    // Device Vector. When using nvcc, this is a thrust::device_vector. When using gcc, this is a std::vector
    Type::host_vector<Type::device_vector<T>> device_data;
    // Save a host vector of device vectors of pointers to the subgrids. this way we can access a pointer to the respective subgrids of each submatrix.
    Type::host_vector<Type::device_vector<T*>> subgrid_pointers_device;
    // Host Vector. When using nvcc, this is a thrust::host_vector. When using gcc, this is a std::vector
    Type::host_vector<T> host_data;

    // Static buffer for the full size device matrix. This is used when the full grid is required on the device, for example
    // when doing a FFT or when synchronizing the device with the host matrices. We specifically use a map here to allow
    // for multiple sizes of matrices.
    inline static std::map<Type::uint32, Type::device_vector<T>> device_data_full;

    // Size of this Matrix. Mostly used for debugging and the Summary
    double size_in_mb_host = 0;
    double size_in_mb_device = 0;

    // Synchronization Flag
    bool host_is_ahead = true;

    // Is constructed flag
    bool is_constructed = false;

   public:
    CUDAMatrix() {
        name = "unnamed";
        rows = 0;
        cols = 0;
        total_size_host = 0;
        total_size_device = 0;
        num_matrices = 0;
        host_is_ahead = true;
    };

    CUDAMatrix( CUDAMatrix& other ) : rows( other.rows ), cols( other.cols ), total_size_host( other.total_size_host ), total_size_device( other.total_size_device ), name( other.name ), device_data( other.device_data ), host_data( other.host_data ) {
        other.total_size_host = 0;
        other.total_size_device = 0;
        other.cols = 0;
        other.rows = 0;
    }
    CUDAMatrix( CUDAMatrix&& other ) : rows( other.rows ), cols( other.cols ), total_size_host( other.total_size_host ), total_size_device( other.total_size_device ), name( other.name ), device_data( other.device_data ), host_data( other.host_data ) {
        other.total_size_host = 0;
        other.total_size_device = 0;
        other.cols = 0;
        other.rows = 0;
    }

    CUDAMatrix( Type::uint32 rows, Type::uint32 cols, const std::string& name ) : rows( rows ), cols( cols ), name( name ) {
        construct( rows, cols, name );
    }

    CUDAMatrix( Type::uint32 rows, Type::uint32 cols, T* data, const std::string& name ) : CUDAMatrix( rows, cols, name ) {
        setTo( data );
    }

    CUDAMatrix( Type::uint32 root_size, const std::string& name ) : CUDAMatrix( root_size, root_size, name ) {};
    CUDAMatrix( Type::uint32 root_size, T* data, const std::string& name ) : CUDAMatrix( root_size, root_size, data, name ) {};

    /**
     * @return: std::string - The name of this matrix.
     */
    std::string getName() const {
        return name;
    }

    /**
     * Sets the host data of this matrix to the input.
     * @param data: Type::host_vector<T> Source vector. Only source vectors with matching types can be copied to the host data of the matrix.
     * @return: ptr to this object to enable chaining of these operations.
     */
    CUDAMatrix<T>& setTo( const Type::host_vector<T>& data ) {
        // Set the host data to the current data. This works fine with both std::vector and thrust::vector
        host_data = data;
        // The host data has been updated, so the host is now ahead.
        host_is_ahead = true;
        // Log this action
        if ( global_matrix_transfer_log ) {
            std::cout << PHOENIX::CLIO::prettyPrint( "Copied " + std::to_string( data.size() ) + " elements to '" + getName() + "'.", PHOENIX::CLIO::Control::Info | PHOENIX::CLIO::Control::Secondary ) << std::endl;
        }
        // Return this pointer
        return *this;
    }

    /**
     * Sets the host data of this matrix to the other matrix' data
     * @param other: Other CUDAMatrix of same size
     */
    CUDAMatrix<T>& setTo( CUDAMatrix<T>& other ) {
        // Set the host data to the current data. This works fine with both std::vector and thrust::vector
        host_data = other.getHostVector();
        // The host data has been updated, so the host is now ahead.
        host_is_ahead = true;
        // Log this action
        if ( global_matrix_transfer_log ) {
            std::cout << PHOENIX::CLIO::prettyPrint( "Copied '" + other.getName() + "' to '" + getName() + "'", PHOENIX::CLIO::Control::Info | PHOENIX::CLIO::Control::Secondary ) << std::endl;
        }
        // Return this pointer
        return *this;
    }

    /**
     * Destructor. Destroys both the host and the device Matrix.
     */
    ~CUDAMatrix() {
        // Subtract the current size of this matrix from the global matrix size
        global_total_device_mb -= size_in_mb_device * num_matrices;
        global_total_host_mb -= size_in_mb_host * num_matrices;
        // Log this action. Mostly for simple debugging.
        if ( global_matrix_creation_log )
            std::cout << PHOENIX::CLIO::prettyPrint( "Freeing " + std::to_string( num_matrices ) + "x" + std::to_string( rows ) + "x" + std::to_string( rows ) + " matrix '" + name + "'. Total allocated space: " + std::to_string( global_total_host_mb ) + "MB (host), " + std::to_string( global_total_device_mb ) + "MB (device)", PHOENIX::CLIO::Control::Info | PHOENIX::CLIO::Control::Secondary ) << std::endl;
        // Clear the Host data
        host_data.clear();
        device_data.clear();
        device_data_full.clear();
        // Host is not ahead
        host_is_ahead = false;
        // The matrix is no longer constructed
        is_constructed = false;
    }

    /**
     * Calculates the sizes of the matrix and the subgrids from the rows, cols, subgrids_columns, subgrids_rows and halo_size.
     */
    void calculateSizes() {
        total_size_host = rows * cols;
        size_in_mb_host = total_size_host * sizeof( T ) / 1024.0 / 1024.0;
        total_size_device = ( rows + 2 * halo_size ) * ( cols + 2 * halo_size );
        size_in_mb_device = total_size_device * sizeof( T ) / 1024.0 / 1024.0;
        subgrid_rows = rows / subgrids_rows;
        subgrid_rows_with_halo = subgrid_rows + 2 * halo_size;
        subgrid_cols = cols / subgrids_columns;
        subgrid_cols_with_halo = subgrid_cols + 2 * halo_size;
        total_num_subgrids = subgrids_columns * subgrids_rows;
        subgrid_size = subgrid_rows * subgrid_cols;
        subgrid_size_with_halo = subgrid_rows_with_halo * subgrid_cols_with_halo;
    }

    /**
     * Constructs the Device Matrix vector. This function only allocates the memory and does not copy any data.
     * @return: ptr to this matrix.
     */
    CUDAMatrix<T>& construct( Type::uint32 rows, Type::uint32 cols, Type::uint32 subgrids_columns, Type::uint32 subgrids_rows, Type::uint32 halo_size, const std::string& name, const Type::uint32 num_matrices = 1 ) {
        this->name = name;
        this->rows = rows;
        this->cols = cols;
        this->subgrids_columns = subgrids_columns;
        this->subgrids_rows = subgrids_rows;
        this->halo_size = halo_size;
        this->num_matrices = num_matrices;
        // Calculate the total size of this matrix as well as its size in bytes
        calculateSizes();
        if ( this->rows * this->cols == 0 ) {
            return *this;
        }
        // Add the size to the global counter for the device sizes and update the maximum encountered memory size
        global_total_device_mb += size_in_mb_device * num_matrices;
        global_total_device_mb_max = std::max( global_total_device_mb, global_total_device_mb_max );
        global_total_host_mb += size_in_mb_host * num_matrices;
        global_total_host_mb_max = std::max( global_total_host_mb, global_total_host_mb_max );
        // Log this action.
        if ( global_matrix_creation_log )
            std::cout << PHOENIX::CLIO::prettyPrint( "Allocating " + std::to_string( size_in_mb_device ) + " MB for " + std::to_string( num_matrices ) + "x(" + std::to_string( rows ) + "+" + std::to_string( 2 * halo_size ) + ")x(" + std::to_string( cols ) + "+" + std::to_string( 2 * halo_size ) + ")" + " device matrix '" + name + "' with halo " + std::to_string( halo_size ) + " and " + std::to_string( total_num_subgrids ) +
                                                         " total subgrids, total allocated device space: " + std::to_string( global_total_device_mb ) + " MB.",
                                                     PHOENIX::CLIO::Control::Info | PHOENIX::CLIO::Control::Secondary )
                      << std::endl;
        // Allocate the host data vector. This is a full size matrix.
        host_data = Type::host_vector<T>( total_size_host * num_matrices, (T)0.0 );
        // Allocate the device data vector. This is a vector of subgrids.
        device_data.resize( total_num_subgrids );
        subgrid_pointers_device.resize( num_matrices );
        for ( int nm = 0; nm < num_matrices; nm++ ) {
            subgrid_pointers_device[nm] = Type::device_vector<T*>( total_num_subgrids );
        }
        // Allocate the individual subgrids in a omp loop, ensuring first-touch memory allocation
#pragma omp parallel for schedule( static )
        for ( int i = 0; i < total_num_subgrids; i++ ) {
#ifdef USE_NUMA
            int numa_domain = i % PHOENIX_NUMA_DOMAINS;
            numa_run_on_node( numa_domain );
            numa_set_preferred( numa_domain );
            int cpu = sched_getcpu();
            int node = numa_node_of_cpu( cpu );
    #pragma omp critical
            std::cout << PHOENIX::CLIO::prettyPrint( "Allocating subgrid " + std::to_string( i ) + " on CPU " + std::to_string( cpu ) + " on NUMA node " + std::to_string( node ) + ".", PHOENIX::CLIO::Control::FullSuccess ) << std::endl;
#endif
            device_data[i] = Type::device_vector<T>( subgrid_size_with_halo * num_matrices, (T)0.0 );
            for ( int nm = 0; nm < num_matrices; nm++ ) subgrid_pointers_device[nm][i] = GET_RAW_PTR( device_data[i] ) + nm * subgrid_size_with_halo;
        }

        // Allocate a full-sized device matrix for manipulation of the full grid in e.g. FFTs or transfers.
        // This is the size of only one matrix, even if num_matrices is greater than 1. For larger matrices, a temporary buffer is created instead.
        if ( not device_data_full.count( total_size_host ) ) {
            if ( global_matrix_creation_log )
                std::cout << PHOENIX::CLIO::prettyPrint( "Full grid buffer for size " + std::to_string( total_size_host ) + " not found, creating new buffer.", PHOENIX::CLIO::Control::Info | PHOENIX::CLIO::Control::Secondary ) << std::endl;
            device_data_full[total_size_host] = Type::device_vector<T>( total_size_host );
        }
        // And the Device Matrix is now ahead of the host matrix
        host_is_ahead = true;
        // Constructed
        is_constructed = true;
        // Return pointer to this
        return *this;
    }

    /**
     * Alias for construct( rows, cols, name ) using root_size = rows*cols
     */
    CUDAMatrix<T>& construct( Type::uint32 root_size, const std::string& name ) {
        return construct( root_size, root_size, 1, 0, name, 1 );
    }

    /**
     * Fill Matrix with set value. From host-side only.
     * If the matrix is also on the device, synchronize the data.
     */
    CUDAMatrix<T>& fill( T value, Type::uint32 matrix = 0 ) {
        std::fill( host_data.begin() + matrix * total_size_host, host_data.begin() + ( matrix + 1 ) * total_size_host, value );
        hostToDeviceSync( matrix );
        return *this;
    }

    /**
     * Synchronize the Host and Device matrices and copies to host data to the device data.
     * This functions usually doesn't have to be called manually by the user. Instead, is called automatically
     * depending on which access methods are called by the user. This function also constructs the device
     * matrix if that has not been done yet. This allows the user to create host matrices and only create
     * the corresponding device matrix when it is needed.
     * This function ALWAYS syncronizes all num_matrices individual matrices.
     */
    CUDAMatrix<T>& hostToDeviceSync( PHOENIX::Type::uint32 matrix = 0 ) {
        if ( not is_constructed or num_matrices == 0 )
            return *this;
        // Log this action
        if ( global_matrix_transfer_log )
            std::cout << PHOENIX::CLIO::prettyPrint( "Host to Device Sync for matrix '" + name + "' (" + std::to_string( matrix ) + ").", PHOENIX::CLIO::Control::Info | PHOENIX::CLIO::Control::Secondary ) << std::endl;

        // If the subgrid size is 1 and the halo_size is zero, we can just copy the full matrix to the device data
        const PHOENIX::Type::uint32 fullgrid_host_ptr_matrix_offset = total_size_host * matrix;
        if ( subgrid_size == 1 and halo_size == 0 ) {
            std::copy( host_data.begin() + fullgrid_host_ptr_matrix_offset, host_data.begin() + fullgrid_host_ptr_matrix_offset + total_size_host, device_data[0].begin() + fullgrid_host_ptr_matrix_offset );
        } else {
// Otherwise, we have to copy the full matrix to the device data_full and then split the full matrix into subgrids
#ifdef USE_CPU
            // Copy the matrix to the device buffer
            std::copy( host_data.begin() + fullgrid_host_ptr_matrix_offset, host_data.begin() + fullgrid_host_ptr_matrix_offset + total_size_host, device_data_full[total_size_host].begin() );
#else
            thrust::copy( host_data.begin() + fullgrid_host_ptr_matrix_offset, host_data.begin() + fullgrid_host_ptr_matrix_offset + total_size_host, device_data_full[total_size_host].begin() );
#endif
            toSubgrids( matrix );
        }
        // The Device Matrix is now ahead of the Host matrix
        host_is_ahead = false;
        // Return this pointer.
        return *this;
    }

    /**
     * Synchronize the Host and Device matrices and copies the device data to the host.
     * This functions usually doesn't have to be called manually by the user. Instead, is called automatically
     * depending on which access methods are called by the user. This function also constructs the device
     * matrix if that has not been done yet. This allows the user to create host matrices and only create
     * the corresponding device matrix when it is needed.
     */
    CUDAMatrix<T>& deviceToHostSync( PHOENIX::Type::uint32 matrix = 0 ) {
        if ( not is_constructed or num_matrices == 0 )
            return *this;
        // Log this data
        if ( global_matrix_transfer_log )
            std::cout << PHOENIX::CLIO::prettyPrint( "Device to Host Sync for matrix '" + name + "'.", PHOENIX::CLIO::Control::Info | PHOENIX::CLIO::Control::Secondary ) << std::endl;

        const PHOENIX::Type::uint32 fullgrid_host_ptr_matrix_offset = total_size_host * matrix;
        if ( subgrid_size == 1 and halo_size == 0 ) {
            std::copy( device_data[0].begin(), device_data[0].end(), host_data.begin() + fullgrid_host_ptr_matrix_offset );
        } else {
            toFull( matrix );
#ifdef USE_CPU
            // Copy the matrix to the device buffer
            std::copy( device_data_full[total_size_host].begin(), device_data_full[total_size_host].end(), host_data.begin() + fullgrid_host_ptr_matrix_offset );
#else
            thrust::copy( device_data_full[total_size_host].begin(), device_data_full[total_size_host].end(), host_data.begin() + fullgrid_host_ptr_matrix_offset );
#endif
            //host_data = device_data_full[total_size_host];
        }
        // The Host Matrix is now ahead of the device matrix
        host_is_ahead = true;
        // Return this pointer
        return *this;
    }

    // Debug purposes only
    void print() {
        for ( int i = 0; i < 10; i++ ) {
            for ( int j = 0; j < subgrid_cols; j++ ) {
                std::cout << device_data[0][i * subgrid_cols + j] << " ";
            }
            std::cout << std::endl;
        }
    }
    // output device_vector[0] to file
    void dumpToFile( std::string path, std::string fp ) {
        for ( int r = 0; r < subgrids_rows; r++ ) {
            for ( int c = 0; c < subgrids_columns; c++ ) {
                std::ofstream file;
                file.open( path + std::to_string( r ) + std::string( "_" ) + std::to_string( c ) + std::string( "_" ) + fp + std::string( ".txt" ) );
                for ( int i = 0; i < subgrid_rows_with_halo; i++ ) {
                    for ( int j = 0; j < subgrid_cols_with_halo; j++ ) {
                        T v = device_data[r * subgrids_columns + c][i * subgrid_cols_with_halo + j];
                        file << CUDA::real( v ) << " ";
                    }
                    file << std::endl;
                }
                file.close();
            }
        }
    }

    /**
     * Returns the total size of this matrix.
     */
    inline Type::uint32 getTotalSize() const {
        return total_size_host;
    }

    CUDAMatrix<T>& toFull( PHOENIX::Type::device_vector<T>& out, PHOENIX::Type::uint32 matrix = 0, PHOENIX::Type::stream_t stream = 0 ) {
        if ( not is_constructed )
            return *this;
// Copy all device data to a device buffer.
#ifdef USE_CPU
        // On the CPU, we need exactly one thread per cell
        dim3 block_size( rows, 1 );
        dim3 grid_size( cols, 1 );
#else
        // On the GPU, we need at least one thread per cell
        dim3 block_size( 256, 1 );
        dim3 grid_size( ( rows * cols + block_size.x ) / block_size.x, 1 );
#endif
        auto fullgrid_dev_ptr = GET_RAW_PTR( out );
        auto dev_ptrs = getSubgridDevicePtrs( matrix );
        if ( global_matrix_transfer_log )
            std::cout << PHOENIX::CLIO::prettyPrint( "Copying " + std::to_string( subgrids_columns ) + "x" + std::to_string( subgrids_rows ) + " subgrids to full grid buffer for matrix '" + name + "' (" + std::to_string( matrix ) + ")", PHOENIX::CLIO::Control::Info | PHOENIX::CLIO::Control::Secondary ) << std::endl;
        CALL_FULL_KERNEL( PHOENIX::Kernel::Halo::halo_grid_to_full_grid, "halo_to_full:" + name, grid_size, block_size, stream, cols, rows, subgrids_columns, subgrid_cols, subgrid_rows, halo_size, fullgrid_dev_ptr, dev_ptrs );

        return *this;
    }

    CUDAMatrix<T>& toFull( PHOENIX::Type::uint32 matrix = 0, PHOENIX::Type::stream_t stream = 0 ) {
        // Copy all device data to the full static device_data_full buffer
        // This function will copy the data within the respective halos, if they exist,
        // to the full matrix.
        toFull( device_data_full[total_size_host], matrix, stream );
        return *this;
    }

    CUDAMatrix<T>& toSubgrids( PHOENIX::Type::device_vector<T>& in, PHOENIX::Type::uint32 matrix = 0, PHOENIX::Type::stream_t stream = 0 ) {
        if ( not is_constructed )
            return *this;
// Copy all device data of a device_vector to the subgrids.
#ifdef USE_CPU
        // On the CPU, we need exactly one thread per cell
        dim3 block_size( rows, 1 );
        dim3 grid_size( cols, 1 );
#else
        // On the GPU, we need at least one thread per cell
        dim3 block_size( 256, 1 );
        dim3 grid_size( ( rows * cols + block_size.x ) / block_size.x, 1 );
#endif

        auto fullgrid_dev_ptr = GET_RAW_PTR( in );
        auto dev_ptrs = getSubgridDevicePtrs( matrix );
        if ( global_matrix_transfer_log )
            std::cout << PHOENIX::CLIO::prettyPrint( "Copying full grid buffer to subgrids for matrix '" + name + "' (" + std::to_string( matrix ) + ")", PHOENIX::CLIO::Control::Info | PHOENIX::CLIO::Control::Secondary ) << std::endl;
        CALL_FULL_KERNEL( PHOENIX::Kernel::Halo::full_grid_to_halo_grid, "full_to_halo:" + name, grid_size, block_size, stream, cols, rows, subgrids_columns, subgrid_cols, subgrid_rows, halo_size, fullgrid_dev_ptr, dev_ptrs );

        return *this;
    }

    CUDAMatrix<T>& toSubgrids( PHOENIX::Type::uint32 matrix = 0, PHOENIX::Type::stream_t stream = 0 ) {
        // Copy all device data of the full static device_data_full buffer
        // This function will copy the data within the full matrix to the respective subgrid
        // The halos will remain unsynchronized
        toSubgrids( device_data_full[total_size_host], matrix, stream );
        return *this;
    }

    // MARK: Data Accessing
    // ===================================================================== //
    // =------------------------- Data Accessing --------------------------= //
    // ===================================================================== //

    /**
     * Returns the raw pointer to the device memory. This is used in the Kernels, because they
     * cannot directly work with std::vector or thrust::device_vectors.
     */
    inline T* getDevicePtr( Type::uint32 subgrid = 0, Type::uint32 matrix = 0 ) {
        if ( not is_constructed )
            return nullptr;
        // If the host is ahead, synchronize first
        if ( host_is_ahead )
            hostToDeviceSync( matrix );
        // This is equivalent to "GET_RAW_PTR( subgrid_pointers_device[matrix][subgrid] );" but we use this to avoid accessing the device vector.
        return GET_RAW_PTR( device_data[subgrid] ) + matrix * subgrid_size_with_halo;
    }

    /**
     * Returns a vector of device pointers
     * @return T** - Pointer to the device pointers
     */
    inline T** getSubgridDevicePtrs( Type::uint32 matrix = 0 ) {
        if ( not is_constructed )
            return nullptr;
        return GET_RAW_PTR( subgrid_pointers_device[matrix] );
    }

    /**
     * Returns the raw pointer to the host memory.
    */
    inline T* getHostPtr( Type::uint32 matrix = 0 ) {
        if ( not is_constructed )
            return nullptr;
        // If the device is ahead, synchronize first
        if ( not host_is_ahead )
            deviceToHostSync();
        // In this case, we can just return .data() on either std::vector or thrust::host_vector
        return host_data.data() + matrix * total_size_host;
    }

    /**
     * Returns the host vector. The return type is const because you are not supposed to manipulated
     * the data this way.
     */

    inline const Type::host_vector<T>& getHostVector() {
        if ( not host_is_ahead )
            deviceToHostSync();
        return host_data;
    }

    /**
     * Returns the raw pointer to the device memory buffer. To get the correct matrix data,
     * use toFull().fullMatrixPointer().
     */
    // Pointer
    T* fullMatrixPointer() {
        if ( not is_constructed )
            return nullptr;
        return GET_RAW_PTR( device_data_full[total_size_host] );
    }
    // Begin Iterator
    auto fullMatrixBegin() {
        return device_data_full[total_size_host].begin();
    }
    // End Iterator
    auto fullMatrixEnd() {
        return device_data_full[total_size_host].end();
    }

    Type::device_vector<T>& getFullMatrix( bool sync = false, PHOENIX::Type::uint32 matrix = 0 ) {
        if ( sync ) {
            toFull( matrix );
        }
        return device_data_full[total_size_host];
    }

    Type::host_vector<Type::device_vector<T>>& getDeviceData() {
        return device_data;
    }
    Type::host_vector<T>& getHostData() {
        return host_data;
    }
    const Type::host_vector<Type::device_vector<T>>& getDeviceData() const {
        return device_data;
    }
    const Type::host_vector<T>& getHostData() const {
        return host_data;
    }

    void swap( CUDAMatrix& other ) noexcept {
        using std::swap;

        // If your base‐class has any state, swap it first:
        swap( static_cast<CUDAMatrixBase&>( *this ), static_cast<CUDAMatrixBase&>( other ) );

        // Now swap every non‐static data member:
        swap( rows, other.rows );
        swap( cols, other.cols );
        swap( subgrid_rows, other.subgrid_rows );
        swap( subgrid_cols, other.subgrid_cols );
        swap( subgrid_rows_with_halo, other.subgrid_rows_with_halo );
        swap( subgrid_cols_with_halo, other.subgrid_cols_with_halo );
        swap( total_size_host, other.total_size_host );
        swap( total_size_device, other.total_size_device );
        swap( subgrids_columns, other.subgrids_columns );
        swap( subgrids_rows, other.subgrids_rows );
        swap( total_num_subgrids, other.total_num_subgrids );
        swap( subgrid_size, other.subgrid_size );
        swap( subgrid_size_with_halo, other.subgrid_size_with_halo );
        swap( halo_size, other.halo_size );
        swap( num_matrices, other.num_matrices );
        swap( name, other.name );
        swap( device_data, other.device_data );
        swap( subgrid_pointers_device, other.subgrid_pointers_device );
        swap( host_data, other.host_data );
        swap( size_in_mb_host, other.size_in_mb_host );
        swap( size_in_mb_device, other.size_in_mb_device );
        swap( host_is_ahead, other.host_is_ahead );
        swap( is_constructed, other.is_constructed );
        // note: we do *not* swap the static device_data_full map
    }

    // MARK: Transformations on Device Data
    // ===================================================================== //
    // =------------------------- Transformations -------------------------= //
    // ===================================================================== //
    // These functions are used to transform the device data in the matrix.
    // They are applied per-subgrid and may change the actual subgrid device
    // data in place. The host data is then marked as outdated.
    // Oh and these also transform all num_matrices matrices. :)

    struct transform_abs2 {
        PHOENIX_HOST_DEVICE T operator()( const T& x ) const {
            const T res = CUDA::abs2( x );
            return res;
        }
    };
    struct transform_sum {
        PHOENIX_HOST_DEVICE T operator()( const T& lhs, const T& rhs ) const {
            return lhs + rhs;
        }
    };

    /**
     * Transforms the device data in the matrix using a lambda function.
     * Transformations happen per subgrid. This function changes the device data in place.
     * @param func: Lambda function that takes a T and returns a T.
     */
    template <typename Func>
    CUDAMatrix<T>& transform( Func func, size_t matrix = 0 ) {
        size_t matrix_start = matrix * subgrid_size_with_halo;
        size_t matrix_end = ( matrix + 1 ) * subgrid_size_with_halo;
// Transform the data
#ifdef USE_CPU
    #pragma omp parallel for schedule( static )
        for ( int i = 0; i < total_num_subgrids; i++ ) {
            std::ranges::transform( device_data[i].begin() + matrix_start, device_data[i].begin() + matrix_end, device_data[i].begin() + matrix_start, func );
        }
#else
        for ( int i = 0; i < total_num_subgrids; i++ ) {
            thrust::transform( device_data[i].begin() + matrix_start, device_data[i].begin() + matrix_end, device_data[i].begin() + matrix_start, func );
        }
#endif
        // The device matrix is now ahead
        host_is_ahead = false;
        // Return this pointer
        return *this;
    }

    /**
     * Transforms and reduces the device data in the matrix using a lambda function.
     * Transformations happen per subgrid. This function does not change the device data.
     * @param func: Lambda function that takes a T and returns a T.
     * @param reduction: Lambda function that takes two Ts and returns a T. 
    */
    template <typename Func, typename Reduction>
    T transformReduce( T init, Func func, Reduction reduction, size_t matrix = 0 ) {
        T result = init;
        size_t matrix_start = matrix * subgrid_size_with_halo;
        size_t matrix_end = ( matrix + 1 ) * subgrid_size_with_halo;
// Transform the data
#ifdef USE_CPU
    #pragma omp parallel for schedule( static )
        for ( int i = 0; i < total_num_subgrids; i++ ) {
            result = std::transform_reduce( device_data[i].begin() + matrix_start, device_data[i].begin() + matrix_end, result, reduction, func );
        }
#else
        for ( int i = 0; i < total_num_subgrids; i++ ) {
            result = thrust::transform_reduce( device_data[i].begin() + matrix_start, device_data[i].begin() + matrix_end, func, result, reduction );
        }
#endif
        // Return this pointer
        return result;
    }

    /**
     * Calculates the minimum and maximum values of the device data in the matrix.
     * Transformations happen per subgrid. This function does not change the device data.
     * @return: std::pair<T, T> - The minimum and maximum values of the matrix.
    */
    std::tuple<T, T> extrema( size_t matrix = 0 ) {
        T min = std::numeric_limits<T>::max();
        T max = std::numeric_limits<T>::min();
        size_t matrix_start = matrix * subgrid_size_with_halo;
        size_t matrix_end = ( matrix + 1 ) * subgrid_size_with_halo;
        // Transform the data
#ifdef USE_CPU
    #pragma omp parallel for schedule( static )
        for ( int i = 0; i < total_num_subgrids; i++ ) {
            auto [min_i, max_i] = std::ranges::minmax_element( device_data[i].begin() + matrix_start, device_data[i].begin() + matrix_end, []( T a, T b ) { return a < b; } );
    #pragma omp critical
            {
                min = min < *min_i ? min : *min_i;
                max = max > *max_i ? max : *max_i;
            }
        }
#else
        for ( int i = 0; i < total_num_subgrids; i++ ) {
            auto result = thrust::minmax_element( device_data[i].begin() + matrix_start, device_data[i].begin() + matrix_end, [] PHOENIX_DEVICE( T a, T b ) { return a < b; } );
            // Result contains pointers to DEVICE memory, so we cant just dereference them
            T min_i, max_i;
            thrust::copy( result.first, result.first + 1, &min_i );
            thrust::copy( result.second, result.second + 1, &max_i );
            min = min < min_i ? min : min_i;
            max = max > max_i ? max : max_i;
        }
#endif
        // Return the result
        return std::make_tuple( min, max );
    }

    /**
     * Reduces the device data in the matrix using a lambda function.
     * Transformations happen per subgrid. This function does not change the device data.
     * @param reduction: Lambda function that takes two Ts and returns a T. 
    */
    template <typename Reduction>
    T reduce( T init, Reduction reduction, size_t matrix = 0 ) {
        T result = init;
        size_t matrix_start = matrix * subgrid_size_with_halo;
        size_t matrix_end = ( matrix + 1 ) * subgrid_size_with_halo;
// Transform the data
#ifdef USE_CPU
    #pragma omp parallel for schedule( static )
        for ( int i = 0; i < total_num_subgrids; i++ ) {
            result = std::reduce( device_data[i].begin() + matrix_start, device_data[i].begin() + matrix_end, result, reduction );
        }
#else
        for ( int i = 0; i < total_num_subgrids; i++ ) {
            result = thrust::reduce( thrust::device, device_data[i].begin() + matrix_start, device_data[i].begin() + matrix_end, result, reduction );
        }
#endif
        return result;
    }

    /**
     * Calculates the sum of the device data in the matrix.
     * Transformations happen per subgrid. This function does not change the device data.
     * @return: T - The sum of the matrix.
    */
    T sum( size_t matrix = 0 ) {
#ifdef USE_CPU
        return reduce( T( 0.0 ), std::plus<T>(), matrix );
#else
        return reduce( T( 0.0 ), thrust::plus<T>(), matrix );
#endif
    }

    // MARK: Transforms on Static Device Data
    // ===================================================================== //
    // =---------------- Transformations on Static Data -------------------= //
    // ===================================================================== //
    // These functions are used to transform the full device data in the matrix.
    // They are applied to the full device data and do not change any of the
    // subgrid device data.

    // Example usecase: m.staticCWiseAbs2(true).staticNormalize().toSubgrids()
    // Which calculates moves the subgrid data to the static device buffer,
    // calculates the cwise abs2 and normalizes the full matrix, and then moves
    // the data back to the subgrids.
    // m.staticFunc(true) is equivalent to m.toFull().staticFunc()

    CUDAMatrix<T>& staticCWiseAbs2( bool first_time = false, PHOENIX::Type::uint32 matrix = 0 ) {
        if ( first_time )
            toFull( matrix );
#ifdef USE_CPU
    #pragma omp parallel for schedule( static )
        for ( int i = 0; i < total_size_host; i++ ) {
            device_data_full[total_size_host][i] = CUDA::abs2( device_data_full[total_size_host][i] );
        }
#else
        thrust::transform( device_data_full[total_size_host].begin(), device_data_full[total_size_host].end(), device_data_full[total_size_host].begin(), [] PHOENIX_DEVICE( T x ) { return CUDA::abs2( x ); } );
#endif
        return *this;
    }

    CUDAMatrix<T>& staticNormalize( T& min, T& max, bool first_time = false, PHOENIX::Type::uint32 matrix = 0 ) {
        if ( first_time )
            toFull( matrix );
#ifdef USE_CPU
    #pragma omp parallel for schedule( static )
        for ( int i = 0; i < total_size_host; i++ ) {
            device_data_full[total_size_host][i] = ( device_data_full[total_size_host][i] - min ) / ( max - min );
        }
#else
        thrust::transform( device_data_full[total_size_host].begin(), device_data_full[total_size_host].end(), device_data_full[total_size_host].begin(), [min, max] PHOENIX_DEVICE( T x ) { return ( x - min ) / ( max - min ); } );
#endif
        return *this;
    }

    CUDAMatrix<T>& staticNormalize( bool first_time = false, PHOENIX::Type::uint32 matrix = 0 ) {
        auto [min, max] = extrema();
        return staticNormalize( min, max, first_time, matrix );
    }

    CUDAMatrix<T>& staticAngle( bool first_time = false, PHOENIX::Type::uint32 matrix = 0 ) {
        if ( first_time )
            toFull( matrix );
#ifdef USE_CPU
    #pragma omp parallel for schedule( static )
        for ( int i = 0; i < total_size_host; i++ ) {
            device_data_full[total_size_host][i] = CUDA::arg( device_data_full[total_size_host][i] );
        }
#else
        thrust::transform( device_data_full[total_size_host].begin(), device_data_full[total_size_host].end(), device_data_full[total_size_host].begin(), [] PHOENIX_DEVICE( T x ) { return CUDA::arg( x ); } );
#endif
        return *this;
    }
};

} // namespace PHOENIX
