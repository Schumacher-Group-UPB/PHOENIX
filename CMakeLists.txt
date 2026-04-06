cmake_minimum_required(VERSION 3.25)
project(Phoenix LANGUAGES CXX)
set(PHOENIX_VERSION "v0.4.0-pre")

include(FetchContent)

# -------------------------------------------------------------------
# ------------ Mandatory choice:  BUILD_ARCH = cpu | gpu ------------
# -------------------------------------------------------------------
set(BUILD_ARCH "gpu" CACHE STRING "cpu  or  gpu")
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
set_property(CACHE ARCH PROPERTY STRINGS none all 50 52 60 61 70 72 75 80 86 89 90 100 120)

set(NUMA "false" CACHE STRING "Enable NUMA and set domain count")

set(PRECISION "fp32" CACHE STRING "Precision: fp32 | fp64")
set_property(CACHE PRECISION PROPERTY STRINGS fp32 fp64)

set(PRETTYCMD "all" CACHE STRING "Pretty CMD: all | colors | symbols | none")
set_property(CACHE PRETTYCMD PROPERTY STRINGS all colors symbols none)

option(SFML "Enable SFML+ImGui renderer" OFF)
option(SFML_STATIC "Use static linking for sfml" OFF)

if(SFML)
    set(SFML_BUILD_EXAMPLES   OFF CACHE BOOL "" FORCE)
    set(SFML_BUILD_DOC        OFF CACHE BOOL "" FORCE)
    set(SFML_BUILD_TEST_SUITE OFF CACHE BOOL "" FORCE)
    set(SFML_USE_STATIC_STD_LIBS OFF CACHE BOOL "" FORCE)
    if(SFML_STATIC)
        set(BUILD_SHARED_LIBS      OFF CACHE BOOL "" FORCE)
        set(SFML_STATIC_LIBRARIES  ON  CACHE BOOL "" FORCE)
    else()
        set(BUILD_SHARED_LIBS      ON  CACHE BOOL "" FORCE)
        set(SFML_STATIC_LIBRARIES  OFF CACHE BOOL "" FORCE)
    endif()
    FetchContent_Declare(SFML
        GIT_REPOSITORY https://github.com/SFML/SFML.git
        GIT_TAG        2.6.2
        GIT_SHALLOW    TRUE
    )
    FetchContent_MakeAvailable(SFML)

    FetchContent_Declare(imgui
        GIT_REPOSITORY https://github.com/ocornut/imgui.git
        GIT_TAG        v1.89.9-docking
        GIT_SHALLOW    TRUE
    )
    FetchContent_GetProperties(imgui)
    if(NOT imgui_POPULATED)
        FetchContent_Populate(imgui)
    endif()

    file(READ "${imgui_SOURCE_DIR}/imconfig.h" _imconfig)
    string(REPLACE "//#define ImDrawIdx unsigned int"
                    "#define ImDrawIdx unsigned int"
                   _imconfig "${_imconfig}")
    file(WRITE "${imgui_SOURCE_DIR}/imconfig.h" "${_imconfig}")

    set(IMGUI_DIR          ${imgui_SOURCE_DIR} CACHE PATH "" FORCE)
    set(IMGUI_SFML_FIND_SFML OFF CACHE BOOL "" FORCE)
    FetchContent_Declare(imgui-sfml
        GIT_REPOSITORY https://github.com/SFML/imgui-sfml.git
        GIT_TAG        v2.6
        GIT_SHALLOW    TRUE
    )
    FetchContent_MakeAvailable(imgui-sfml)

    FetchContent_Declare(implot3d
        GIT_REPOSITORY https://github.com/brenocq/implot3d
        GIT_TAG        v0.3
        GIT_SHALLOW    TRUE
    )
    FetchContent_GetProperties(implot3d)
    if(NOT implot3d_POPULATED)
        FetchContent_Populate(implot3d)
    endif()
    include_directories("${implot3d_SOURCE_DIR}")

    FetchContent_Declare(implot
        GIT_REPOSITORY https://github.com/epezent/implot.git
        GIT_TAG        v0.16
        GIT_SHALLOW    TRUE
    )
    FetchContent_GetProperties(implot)
    if(NOT implot_POPULATED)
        FetchContent_Populate(implot)
    endif()
    include_directories("${implot_SOURCE_DIR}")
endif()

set(RUNTIME_DIR "${PROJECT_SOURCE_DIR}/bin" CACHE PATH "Where to put built executables")

# -------------------------------------------------------------------
# ------------------- Common sources / includes ---------------------
# -------------------------------------------------------------------
file(GLOB_RECURSE CPP_SOURCES CONFIGURE_DEPENDS "${PROJECT_SOURCE_DIR}/source/*.cpp")
file(GLOB_RECURSE CU_SOURCES  CONFIGURE_DEPENDS "${PROJECT_SOURCE_DIR}/source/*.cu")

# Exclude gui backends from auto-glob; add the single active backend explicitly.
list(FILTER CU_SOURCES  EXCLUDE REGEX ".*/source/gui/.*")
list(FILTER CPP_SOURCES EXCLUDE REGEX ".*/source/gui/.*")
list(FILTER CU_SOURCES  EXCLUDE REGEX ".*/source/misc/gui\\.cu$")
list(APPEND CU_SOURCES
    "${PROJECT_SOURCE_DIR}/source/gui/sfml/gui.cu"
    "${PROJECT_SOURCE_DIR}/source/gui/sfml/gui_matrix_panel.cu"
    "${PROJECT_SOURCE_DIR}/source/gui/sfml/gui_control.cu"
    "${PROJECT_SOURCE_DIR}/source/gui/sfml/gui_envelope_editor.cu"
    "${PROJECT_SOURCE_DIR}/source/gui/sfml/gui_runstring_config.cu"
    "${PROJECT_SOURCE_DIR}/source/gui/sfml/gui_benchmark.cu"
)

# implot3d and implot sources added after the glob so they are not wiped by GLOB_RECURSE
if(SFML)
    list(APPEND CPP_SOURCES
        "${implot3d_SOURCE_DIR}/implot3d.cpp"
        "${implot3d_SOURCE_DIR}/implot3d_items.cpp"
        "${implot3d_SOURCE_DIR}/implot3d_meshes.cpp"
        "${implot_SOURCE_DIR}/implot.cpp"
        "${implot_SOURCE_DIR}/implot_items.cpp"
    )
endif()

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
        # Link SFML (fetched via FetchContent above) and imgui-sfml
        target_link_libraries(${tgt} PRIVATE
            sfml-graphics sfml-window sfml-system
            ImGui-SFML::ImGui-SFML)
        target_compile_definitions(${tgt} PRIVATE SFML_RENDER)

        if(SFML_STATIC)
            target_compile_definitions(${tgt} PRIVATE SFML_STATIC)
            # SFML built from source (FetchContent) bundles its own Freetype.
            # Only link the platform system libs required for a static SFML build.
            if(WIN32)
                target_link_libraries(${tgt} PRIVATE opengl32 winmm gdi32)
            endif()
        else()
            # Copy DLLs to output directory on Windows
            add_custom_command(TARGET ${tgt} POST_BUILD
                COMMAND ${CMAKE_COMMAND} -E copy_if_different
                    $<TARGET_FILE:sfml-graphics>
                    $<TARGET_FILE:sfml-window>
                    $<TARGET_FILE:sfml-system>
                    $<TARGET_FILE:ImGui-SFML::ImGui-SFML>
                    $<TARGET_FILE_DIR:${tgt}>
            )
        endif()
    endif()
endmacro()


set(EXE_NAME "PHOENIX_${BUILD_ARCH}_${PRECISION}")
if(SFML)
    string(APPEND EXE_NAME "_sfml")

    if(SFML_STATIC)
        string(APPEND EXE_NAME "_s")
    endif()
endif()

string(TIMESTAMP BUILD_TIME "%Y-%m-%d %H:%M:%S")

add_custom_target(FinalMessage ALL
    COMMAND ${CMAKE_COMMAND} -E echo ""
    COMMAND ${CMAKE_COMMAND} -E echo "=============================================="
    COMMAND ${CMAKE_COMMAND} -E echo "==           PHOENIX BUILD SYSTEM           "
    COMMAND ${CMAKE_COMMAND} -E echo "=============================================="
    COMMAND ${CMAKE_COMMAND} -E echo "==  Version        : ${PHOENIX_VERSION}"
    COMMAND ${CMAKE_COMMAND} -E echo "==  Build Type     : $<CONFIG>"
    COMMAND ${CMAKE_COMMAND} -E echo "==  Architecture   : ${BUILD_ARCH}"
    COMMAND ${CMAKE_COMMAND} -E echo "==  Output Path    : ${RUNTIME_DIR}/${BUILD_ARCH}"
    COMMAND ${CMAKE_COMMAND} -E echo "==  Built At       : ${BUILD_TIME}"
    COMMAND ${CMAKE_COMMAND} -E echo "=============================================="
    COMMAND ${CMAKE_COMMAND} -E echo ">> Summary:"
    COMMAND ${CMAKE_COMMAND} -E echo "   -  Precision       : ${PRECISION}"
    COMMAND ${CMAKE_COMMAND} -E echo "   -  GUI (SFML+ImGui): ${SFML} $<$<BOOL:${SFML_STATIC}>:[static]>"
    COMMAND ${CMAKE_COMMAND} -E echo "Phoenix is now ready!"
    COMMENT "Final build summary"
)

# Conditionally add optional messages
if(NOT SFML)
    add_custom_command(TARGET FinalMessage PRE_BUILD
        COMMAND ${CMAKE_COMMAND} -E echo "     i  To enable SFML+ImGui GUI, use: -DSFML=ON")
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
        $<$<CXX_COMPILER_ID:GNU,Clang>:-fopenmp -x c++ -funroll-loops -finline-limit=20000>
        $<$<CXX_COMPILER_ID:MSVC>:/openmp>
    )
    set_target_properties(${EXE_NAME} PROPERTIES CXX_STANDARD 23)

    if(TUNE STREQUAL "native")
        target_compile_options(${EXE_NAME} PRIVATE $<$<CXX_COMPILER_ID:GNU,Clang>:-mtune=native -march=native>)
    endif()

    if(CMAKE_BUILD_TYPE STREQUAL "Release")
        list(APPEND CPU_OPT_FLAGS -O3)
    else()
        list(APPEND CPU_OPT_FLAGS -O0)
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
        set_property(TARGET ${EXE_NAME} PROPERTY CUDA_ARCHITECTURES 60;61;70;72;75;80;86;89;90;100;120)
    else()
        set_property(TARGET ${EXE_NAME} PROPERTY CUDA_ARCHITECTURES ${ARCH})
    endif()

    enable_language(CUDA)

    find_package(OpenMP) # Windows...
    target_link_libraries(${EXE_NAME} PRIVATE OpenMP::OpenMP_CXX)

    target_compile_options(${EXE_NAME} PRIVATE
    $<$<COMPILE_LANGUAGE:CUDA>:
            -O3
            -std=c++20
            -rdc=true
            --expt-extended-lambda
            --expt-relaxed-constexpr
            $<$<CXX_COMPILER_ID:MSVC>:-Xcompiler=/std:c++20>
            $<$<NOT:$<CXX_COMPILER_ID:MSVC>>:-Xcompiler=-std=c++20>
            -x cu
            -Wno-deprecated-gpu-targets
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
