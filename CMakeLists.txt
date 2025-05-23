cmake_minimum_required(VERSION 3.25)
project(Phoenix LANGUAGES CXX)
set(PHOENIX_VERSION "v0.3.2")

# -------------------------------------------------------------------
# ------------ Mandatory choice:  BUILD_ARCH = cpu | gpu ------------
# -------------------------------------------------------------------
set(BUILD_ARCH "" CACHE STRING "cpu  or  gpu")
set_property(CACHE BUILD_ARCH PROPERTY STRINGS cpu gpu)

if(BUILD_ARCH STREQUAL "")
    message(FATAL_ERROR
        "\nConfig error: BUILD_ARCH is not set.\n"
        "Configure with   cmake -DBUILD_ARCH=cpu  …   or   -DBUILD_ARCH=gpu\n")
endif()

if(MSVC AND BUILD_ARCH STREQUAL "gpu")
    # Completely override the Release flags
    set(CMAKE_CXX_FLAGS_RELEASE "/Od /MD /W1 /EHsc" CACHE STRING "" FORCE)
    set(CMAKE_CUDA_FLAGS_RELEASE "-O0" CACHE STRING "" FORCE)
endif()

# -------------------------------------------------------------------
# ------------------------ User options -----------------------------
# -------------------------------------------------------------------
set(TUNE "native" CACHE STRING "CPU tuning: native | other")
set_property(CACHE TUNE PROPERTY STRINGS native other)

set(ARCH "none" CACHE STRING "CUDA arch: none | all | <smNumber>")
set_property(CACHE ARCH PROPERTY STRINGS none all 50 52 60 61 70 72 75 80 86 89 90)

set(NUMA "false" CACHE STRING "Enable NUMA and set domain count")

set(PRECISION "fp32" CACHE STRING "Precision: fp32 | fp64")
set_property(CACHE PRECISION PROPERTY STRINGS fp32 fp64)

set(PRETTYCMD "all" CACHE STRING "Pretty CMD: all | colors | symbols | none")
set_property(CACHE PRETTYCMD PROPERTY STRINGS all colors symbols none)

option(SFML "Enable SFML renderer" OFF)
set(SFML_PATH "${PROJECT_SOURCE_DIR}/external/SFML/" CACHE PATH "Optional custom root for SFML installation")
option(BUILD_SFML_FROM_SOURCE "Build SFML from external/SFML" ON)
option(SFML_STATIC "Use static linking for sfml" OFF)

set(RUNTIME_DIR "${PROJECT_SOURCE_DIR}/bin" CACHE PATH "Where to put built executables")

# -------------------------------------------------------------------
# ------------------- Common sources / includes ---------------------
# -------------------------------------------------------------------
file(GLOB_RECURSE CPP_SOURCES CONFIGURE_DEPENDS "${PROJECT_SOURCE_DIR}/source/*.cpp")
file(GLOB_RECURSE CU_SOURCES  CONFIGURE_DEPENDS "${PROJECT_SOURCE_DIR}/source/*.cu")

include_directories("${SFML_PATH}/include/")
include_directories("${PROJECT_SOURCE_DIR}/include")
include_directories("${PROJECT_SOURCE_DIR}/")

# -------------------------------------------------------------------
# ---- wrapper files (for *.cu in CPU build and *.cpp in GPU build) --
# -------------------------------------------------------------------
set(CPU_WRAPPERS)
file(MAKE_DIRECTORY "${CMAKE_BINARY_DIR}/cpu_wrappers")

foreach(cu ${CU_SOURCES})
    get_filename_component(base ${cu} NAME_WE)

    # path relative to the top-level source dir:
    file(RELATIVE_PATH rel "${PROJECT_SOURCE_DIR}" "${cu}")
    string(REPLACE "\\" "/" rel "${rel}")            # use / everywhere

    set(wrapper "${CMAKE_BINARY_DIR}/cpu_wrappers/cpu_${base}.cpp")
    file(GENERATE OUTPUT "${wrapper}"
         CONTENT "#include \"${rel}\"\n")

    list(APPEND CPU_WRAPPERS "${wrapper}")
endforeach()

set(GPU_WRAPPERS)
file(MAKE_DIRECTORY "${CMAKE_BINARY_DIR}/gpu_wrappers")

foreach(cpp ${CPP_SOURCES})
    get_filename_component(base ${cpp} NAME_WE)

    file(RELATIVE_PATH rel "${PROJECT_SOURCE_DIR}" "${cpp}")
    string(REPLACE "\\" "/" rel "${rel}")

    set(wrapper "${CMAKE_BINARY_DIR}/gpu_wrappers/gpu_${base}.cu")
    file(GENERATE OUTPUT "${wrapper}"
         CONTENT "#include \"${rel}\"\n")

    list(APPEND GPU_WRAPPERS "${wrapper}")
endforeach()

# -------------------------------------------------------------------
# ---------------------- Helper macros (unchanged) ------------------
# -------------------------------------------------------------------
macro(add_prettycmd_definitions tgt)
    if(PRETTYCMD STREQUAL "none")
        target_compile_definitions(${tgt} PRIVATE PC3_NO_ANSI_COLORS PC3_NO_EXTENDED_SYMBOLS)
    elseif(PRETTYCMD STREQUAL "colors")
        target_compile_definitions(${tgt} PRIVATE PC3_NO_EXTENDED_SYMBOLS)
    elseif(PRETTYCMD STREQUAL "symbols")
        target_compile_definitions(${tgt} PRIVATE PC3_NO_ANSI_COLORS)
    endif()
endmacro()

macro(add_precision_definitions tgt)
    if(PRECISION STREQUAL "fp32")
        target_compile_definitions(${tgt} PRIVATE USE_32_BIT_PRECISION)
    endif()
endmacro()

macro(add_numa tgt)
    if(NUMA AND NOT NUMA STREQUAL "false")
        target_compile_definitions(${tgt} PRIVATE USE_NUMA PULSE_NUMA_DOMAINS=${NUMA})
        target_link_libraries(${tgt} PRIVATE numa)
    endif()
endmacro()

macro(enable_sfml tgt)
    if(SFML)
        if(BUILD_SFML_FROM_SOURCE)
            set(SFML_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
            set(SFML_BUILD_DOC OFF CACHE BOOL "" FORCE)
            set(SFML_BUILD_TEST_SUITE OFF CACHE BOOL "" FORCE)
            set(SFML_USE_STATIC_STD_LIBS OFF CACHE BOOL "" FORCE)

            if(SFML_STATIC)
                set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
                set(SFML_STATIC_LIBRARIES ON CACHE BOOL "" FORCE)
            else()
                set(BUILD_SHARED_LIBS ON CACHE BOOL "" FORCE)
                set(SFML_STATIC_LIBRARIES OFF CACHE BOOL "" FORCE)
            endif()

            add_subdirectory("${SFML_PATH}" EXCLUDE_FROM_ALL)
            
            target_link_directories(${tgt} PRIVATE ${CMAKE_BINARY_DIR}/SFML/lib)
            target_link_libraries(${tgt} PRIVATE sfml-graphics sfml-window sfml-system)

            if(SFML_STATIC)
                target_compile_definitions(${tgt} PRIVATE SFML_STATIC)
                find_package(Freetype REQUIRED)
                target_link_libraries(${tgt} PRIVATE opengl32 winmm gdi32 Freetype::Freetype)
            endif()

            if(NOT SFML_STATIC)
                add_custom_command(TARGET ${tgt} POST_BUILD
                    COMMAND ${CMAKE_COMMAND} -E copy_if_different
                        $<TARGET_FILE:sfml-graphics>
                        $<TARGET_FILE:sfml-window>
                        $<TARGET_FILE:sfml-system>
                        $<TARGET_FILE_DIR:${tgt}>
                )
            endif()
                
        else()
            if(SFML_PATH)
                list(APPEND CMAKE_PREFIX_PATH ${SFML_PATH})
            endif()

            if(SFML_STATIC)
                set(SFML_STATIC_LIBRARIES ON)
                find_package(SFML 2 COMPONENTS graphics window system REQUIRED)
                target_compile_definitions(${tgt} PRIVATE SFML_STATIC)
                
                target_link_libraries(${tgt} PRIVATE sfml-graphics sfml-window sfml-system)
                find_package(Freetype REQUIRED)
                target_link_libraries(${tgt} PRIVATE opengl32 winmm gdi32 Freetype::Freetype)

            else()
                find_package(SFML 2 COMPONENTS graphics window system REQUIRED)
                target_link_libraries(${tgt} PRIVATE sfml-graphics sfml-window sfml-system)

                add_custom_command(TARGET ${tgt} POST_BUILD
                    COMMAND ${CMAKE_COMMAND} -E copy_if_different
                        $<TARGET_FILE:sfml-graphics>
                        $<TARGET_FILE:sfml-window>
                        $<TARGET_FILE:sfml-system>
                        $<TARGET_FILE_DIR:${tgt}>
                )
            endif()
        endif()

        target_compile_definitions(${tgt} PRIVATE SFML_RENDER)
    endif()
endmacro()


set(EXE_NAME "PHOENIX_${BUILD_ARCH}_${PRECISION}")

string(TIMESTAMP BUILD_TIME "%Y-%m-%d %H:%M:%S")

add_custom_target(FinalMessage ALL
    COMMAND ${CMAKE_COMMAND} -E echo ""
    COMMAND ${CMAKE_COMMAND} -E echo "=============================================="
    COMMAND ${CMAKE_COMMAND} -E echo "==           PHOENIX BUILD SYSTEM           "
    COMMAND ${CMAKE_COMMAND} -E echo "=============================================="
    COMMAND ${CMAKE_COMMAND} -E echo "==  Version        : ${PHOENIX_VERSION}"
    COMMAND ${CMAKE_COMMAND} -E echo "==  Build Type     : ${CMAKE_BUILD_TYPE}"
    COMMAND ${CMAKE_COMMAND} -E echo "==  Architecture   : ${BUILD_ARCH}"
    COMMAND ${CMAKE_COMMAND} -E echo "==  Output Path    : ${RUNTIME_DIR}/${BUILD_ARCH}"
    COMMAND ${CMAKE_COMMAND} -E echo "==  Built At       : ${BUILD_TIME}"
    COMMAND ${CMAKE_COMMAND} -E echo "=============================================="
    COMMAND ${CMAKE_COMMAND} -E echo ">> Summary:"
    COMMAND ${CMAKE_COMMAND} -E echo "   -  Precision       : ${PRECISION}"
    COMMAND ${CMAKE_COMMAND} -E echo "   -  SFML Renderer   : ${SFML} $<$<BOOL:${SFML_STATIC}>:(static)>"
    COMMAND ${CMAKE_COMMAND} -E echo "Phoenix is now ready!"
    COMMENT "Final build summary"
)

# Conditionally add optional messages
if(NOT SFML)
    add_custom_command(TARGET FinalMessage PRE_BUILD
        COMMAND ${CMAKE_COMMAND} -E echo "     ℹ  To enable SFML, use: -DSFML=ON")
endif()

if(NOT PRECISION STREQUAL "fp64")
    add_custom_command(TARGET FinalMessage PRE_BUILD
        COMMAND ${CMAKE_COMMAND} -E echo "     ℹ  To enable fp64, use: -DPRECISION=fp64")
endif()

# ===================================================================
# ============================ CPU build ============================
# ===================================================================
if(BUILD_ARCH STREQUAL "cpu")

    add_executable(${EXE_NAME} ${CPP_SOURCES} ${CPU_WRAPPERS})

    target_compile_options(${EXE_NAME} PRIVATE
        $<$<CXX_COMPILER_ID:GNU,Clang>:-std=c++20 -fopenmp -O3 -x c++ -funroll-loops -finline-limit=20000>)
    if(TUNE STREQUAL "native")
        target_compile_options(${EXE_NAME} PRIVATE $<$<CXX_COMPILER_ID:GNU,Clang>:-mtune=native -march=native>)
    endif()

    find_package(OpenMP REQUIRED)
    target_link_libraries(${EXE_NAME} PRIVATE OpenMP::OpenMP_CXX)

    find_package(FFTW QUIET COMPONENTS Float Double)
    if(FFTW_FOUND)
        target_link_libraries(${EXE_NAME} PRIVATE FFTW::Float FFTW::Double)
    else()
        message(WARNING "FFTW not found – cpu target will link successfully only if FFTW symbols are not required at run-time.")
        target_link_libraries(${EXE_NAME} PRIVATE fftw3f fftw3)
    endif()

    target_compile_definitions(${EXE_NAME} PRIVATE USE_CPU)

    add_precision_definitions (${EXE_NAME})
    add_prettycmd_definitions (${EXE_NAME})
    add_numa                  (${EXE_NAME})
    enable_sfml               (${EXE_NAME})

    set(cpu_runtime_dir "${RUNTIME_DIR}/cpu")
    set_target_properties(${EXE_NAME} PROPERTIES
        RUNTIME_OUTPUT_DIRECTORY "${cpu_runtime_dir}"
        RUNTIME_OUTPUT_DIRECTORY_RELEASE "${cpu_runtime_dir}"
        RUNTIME_OUTPUT_DIRECTORY_DEBUG "${cpu_runtime_dir}"
        RUNTIME_OUTPUT_DIRECTORY_RELWITHDEBINFO "${cpu_runtime_dir}"
        RUNTIME_OUTPUT_DIRECTORY_MINSIZEREL "${cpu_runtime_dir}"
    )

    set_target_properties(${EXE_NAME} PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${cpu_runtime_dir}")

    target_compile_definitions(${EXE_NAME} PRIVATE PHOENIX_VERSION="${PHOENIX_VERSION}")

    add_dependencies(FinalMessage ${EXE_NAME})
endif()

# ===================================================================
# ============================ GPU build ============================
# ===================================================================
if(BUILD_ARCH STREQUAL "gpu")

    find_program(NVCC_EXECUTABLE nvcc)
    if(NOT NVCC_EXECUTABLE)
        message(FATAL_ERROR "BUILD_ARCH=gpu but nvcc not found")
    endif()

    set(CMAKE_CUDA_COMPILER "${NVCC_EXECUTABLE}" CACHE FILEPATH "" FORCE)

    add_executable(${EXE_NAME} ${CU_SOURCES} ${GPU_WRAPPERS})

    set_target_properties(${EXE_NAME} PROPERTIES
        CUDA_SEPARABLE_COMPILATION ON
        CUDA_RESOLVE_DEVICE_SYMBOLS ON)

    # Architecture flags
    if(ARCH STREQUAL "none")
        set_property(TARGET ${EXE_NAME} PROPERTY CUDA_ARCHITECTURES OFF)
    elseif(ARCH STREQUAL "all")
        set_property(TARGET ${EXE_NAME} PROPERTY CUDA_ARCHITECTURES 50;52;60;61;70;72;75;80;86;89;90)
    else()
        set_property(TARGET ${EXE_NAME} PROPERTY CUDA_ARCHITECTURES ${ARCH})
    endif()

    enable_language(CUDA)

    find_package(OpenMP) # Windows...
    target_link_libraries(${EXE_NAME} PRIVATE OpenMP::OpenMP_CXX)

    target_compile_options(${EXE_NAME} PRIVATE
    $<$<COMPILE_LANGUAGE:CUDA>:
            -O0
            -std=c++20
            -rdc=true
            --expt-extended-lambda
            --expt-relaxed-constexpr
            $<$<CXX_COMPILER_ID:MSVC>:-Xcompiler=/std:c++20>
            $<$<NOT:$<CXX_COMPILER_ID:MSVC>>:-Xcompiler=-std=c++20>
            -x cu
        >
    )

    if(MSVC)
        target_compile_options(${EXE_NAME} PRIVATE $<$<COMPILE_LANGUAGE:CXX>:/std:c++20>)
        target_compile_options(${EXE_NAME} PRIVATE $<$<COMPILE_LANGUAGE:CUDA>:-Xcompiler=/openmp>)
    else()
        target_compile_options(${EXE_NAME} PRIVATE $<$<COMPILE_LANGUAGE:CXX>:-std=c++20>)
        target_compile_options(${EXE_NAME} PRIVATE $<$<COMPILE_LANGUAGE:CUDA>:-Xcompiler=-fopenmp>)
    endif()

    find_package(CUDAToolkit REQUIRED)
    target_link_libraries(${EXE_NAME} PRIVATE CUDA::cudart CUDA::cufft CUDA::curand)
    if(TARGET CUDA::cudadevrt)
        target_link_libraries(${EXE_NAME} PRIVATE CUDA::cudadevrt)
    endif()

    add_precision_definitions (${EXE_NAME})
    add_prettycmd_definitions (${EXE_NAME})
    enable_sfml               (${EXE_NAME})

    if(MSVC)
        set_target_properties(${EXE_NAME} PROPERTIES
            CUDA_SEPARABLE_COMPILATION ON
            CUDA_RESOLVE_DEVICE_SYMBOLS ON
            CUDA_STANDARD 20
            CUDA_STANDARD_REQUIRED YES
            CUDA_OPTIMIZATION_LEVEL "0"
        )
        target_compile_options(${EXE_NAME} PRIVATE
            $<$<COMPILE_LANGUAGE:CXX>:/Od>
            $<$<COMPILE_LANGUAGE:CUDA>:-O0>
        )
    endif()

    set(gpu_runtime_dir "${RUNTIME_DIR}/gpu")
    set_target_properties(${EXE_NAME} PROPERTIES
        RUNTIME_OUTPUT_DIRECTORY "${gpu_runtime_dir}"
        RUNTIME_OUTPUT_DIRECTORY_RELEASE "${gpu_runtime_dir}"
        RUNTIME_OUTPUT_DIRECTORY_DEBUG "${gpu_runtime_dir}"
        RUNTIME_OUTPUT_DIRECTORY_RELWITHDEBINFO "${gpu_runtime_dir}"
        RUNTIME_OUTPUT_DIRECTORY_MINSIZEREL "${gpu_runtime_dir}"
    )
    set_target_properties(${EXE_NAME} PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${gpu_runtime_dir}")

    target_compile_definitions(${EXE_NAME} PRIVATE PHOENIX_VERSION="${PHOENIX_VERSION}")

    add_dependencies(FinalMessage ${EXE_NAME})
endif()