![resources/banner.png](resources/banner.png)
---

# Highly optimized Solver for the Nonlinear 2D Schrödinger Equation (GPU or CPU)
[![ScienceDirect](https://img.shields.io/badge/ScienceDirect-Available-green)](https://www.sciencedirect.com/science/article/pii/S0010465525001912) [![Build CPU](https://github.com/Schumacher-Group-UPB/PHOENIX/actions/workflows/c-cpp.yml/badge.svg)](https://github.com/Schumacher-Group-UPB/PHOENIX/actions/workflows/c-cpp.yml) [![Build GPU](https://github.com/Schumacher-Group-UPB/PHOENIX/actions/workflows/nvcc-cpp.yml/badge.svg)](https://github.com/Schumacher-Group-UPB/PHOENIX/actions/workflows/nvcc-cpp.yml) [![Issues](https://img.shields.io/github/issues/Schumacher-Group-UPB/PHOENIX.svg?maxAge=2592000)](https://github.com/Schumacher-Group-UPB/PHOENIX/issues) 

PHOENIX is a high-performance solver for the nonlinear two-dimensional Schrödinger equation that can operate on CPUs and GPUs (CUDA-accelerated). Originally designed for simulating exciton-polariton condensates, it has a broad range of applications in fields of nonlinear optics and atomic condensates. 

The project comes with a variety of examples, including Jupyter Notebooks and Matlab files, that demonstrate how to use PHOENIX in scientific research. You can explore these examples in the [examples folder](/examples/). 

If you would like to use PHOENIX or if you are missing certain functionalities in the code, please do not hesitate to [open an issue](https://github.com/Schumacher-Group-UPB/PHOENIX/issues/new) on Github.
We'd appreciate your feedback and should you need technical support we would be happy to help. 

If you use PHOENIX in your research, please cite: 
J. Wingenbach, D. Bauch, X. Ma, R. Schade, C. Plessl, and S. Schumacher. [Computer Physics Communications, 315, 109689 (2025)](https://www.sciencedirect.com/science/article/pii/S0010465525001912)

## Table of Contents

1. [System Requirements](#system-requirements)
2. [Quickstart Guide](#quickstart-guide)
3. [Building PHOENIX](#building-phoenix)
    - [With SFML Rendering](#build-with-sfml-rendering)
    - [Without Rendering](#build-without-rendering)
    - [CPU Kernel Compilation](#build-with-cpu-kernel)
4. [Advanced Features](#advanced-features)
    - [FP32 Precision](#fp32-single-precision)
    - [CUDA Architecture Optimization](#cuda-architecture)
5. [Troubleshooting](#troubleshooting)
6. [Benchmark Examples](#benchmarks)
7. [Custom Kernel Development](#custom-kernel-development)
    - [Adding Custom Variables](#adding-new-variables-to-the-kernels)
    - [Defining Custom Envelopes](#adding-new-envelopes-to-the-kernels)
8. [Current Issues](#current-issues)

---

## Quickstart Guide
An easy way to try out PHOENIX are the Jupyter notebooks available in the `examples` directory.

### Docker Container
We offer a Docker container that has all dependencies included and provides an easy way to try out PHOENIX via the included example Jupyter Notebooks.
#### Prerequisites:
* Windows/MacOS: Docker Desktop ([install guide](https://docs.docker.com/desktop/))
* Linux: Docker Engine ([install guide](https://docs.docker.com/engine/install/)) or Docker Desktop ([install guide](https://docs.docker.com/desktop/setup/install/linux/))
* For NVIDIA GPUs: a working NVIDIA GPU driver and Docker enabled for GPUs

#### Steps:
* Run in a terminal: 
  * if you want to use an NVIDIA GPU: `docker run -it --gpus=all -p 8888:8888 robertschade/phoenix:latest` 
  * otherwise: `docker run -it -p 8888:8888 robertschade/phoenix:latest` 
* open `http://localhost:8888` in a web browser
* navigate to `examples` and open a notebook in one of the subdirectories

### Prebuilt Binaries
We provide prebuilt binaries with every release on the [releases page](https://github.com/Schumacher-Group-UPB/PHOENIX/releases).

#### Prerequisites
* For NVIDIA GPUs: a working NVIDIA GPU driver and NVIDIA CUDA
* Python:
  * For Windows:
    1. Install Python (https://www.python.org/downloads/windows/) 
      * Important: enable "add python.exe to PATH" and "use admin priviledges when installing py.exe"
  * For MacOS:
    1. install Homebrew ([guide](https://brew.sh/))
    2. install gcc: run in terminal `brew install gcc`
    2. install python: run in terminal `brew install python`
  * For Linux:
    * Python is most likely already installed from your distribution

####  

* Windows:
  1. To download and unpack the latest PHOENIX release run the following commands in a terminal:
    * `curl https://github.com/Schumacher-Group-UPB/PHOENIX/archive/refs/tags/latest.zip -o PHOENIX-latest.zip`
    * `tar -xf PHOENIX-latest.zip`
    * `cd PHOENIX-latest`
    * `pip install .`
  2. Start Jupyter Notebook server
    * open terminal and run `jupyter-notebook.exe`
    * a web browser window should open. If this is not the case, manually copy the url shown in the terminal into a web browser and navigate to `PHOENIX-latest/examples`
    * in the subdirectories, e.g., `example_1` you can find jupyter notebooks to try out PHOENIX
* MacOS: 
  1. To download and unpack the latest PHOENIX release run the following commands in a terminal:
    * `curl https://github.com/Schumacher-Group-UPB/PHOENIX/archive/refs/tags/latest.zip -o PHOENIX-latest.zip -L`
    * `unzip PHOENIX-latest.zip`
    * `cd PHOENIX-latest`
    * `python3 -m venv venv`
    * `source venv/bin/activate`
    * `pip install .`
  2. Start Jupyter Notebook server
    * `source venv/bin/activate`
    * `jupyter notebook`
    * a web browser window should open. If this is not the case, manually copy the url shown in the terminal into a web browser and navigate to `PHOENIX-latest/examples`
    * in the subdirectories, e.g., `example_1` you can find jupyter notebooks to try out PHOENIX

* Linux:
  1. install libfftw3, cmake and libsfml with the mechanism of your Linux distribution
  2. To download and unpack the latest PHOENIX release run the following commands in a terminal:
    * `curl https://github.com/Schumacher-Group-UPB/PHOENIX/archive/refs/tags/latest.zip -o PHOENIX-latest.zip -L`
    * `unzip PHOENIX-latest.zip`
    * `cd PHOENIX-latest`
    * `python3 -m venv venv`
    * `source venv/bin/activate`
    * `pip install .`
  3. Build Phoenix (because a prebuilt binary for the many difefrent Linux distributions is hard to do):
    * For GPU with fp64 precision: `cmake -B build_gpu_fp64 -S . -DBUILD_ARCH=gpu -DTUNE=other -DPRECISION=fp64 -DSFML=OFF -DSFML_STATIC=OFF -DBUILD_SFML_FROM_SOURCE=OFF -DARCH=all && cmake --build build_gpu_fp64 -j8 --config Release`
    * For GPU with fp32 precision: `cmake -B build_gpu_fp32 -S . -DBUILD_ARCH=gpu -DTUNE=other -DPRECISION=fp32 -DSFML=OFF -DSFML_STATIC=OFF -DBUILD_SFML_FROM_SOURCE=OFF -DARCH=all && cmake --build build_gpu_fp32 -j8 --config Release`
    * For CPU with fp64 precision: `cmake -B build_cpu_fp64 -S . -DBUILD_ARCH=cpu -DTUNE=other -DPRECISION=fp64 -DSFML=OFF -DSFML_STATIC=OFF -DBUILD_SFML_FROM_SOURCE=OFF && cmake --build build_cpu_fp64 -j8 --config Release`
    * For CPU with fp32 precision: `cmake -B build_cpu_fp32 -S . -DBUILD_ARCH=cpu -DTUNE=other -DPRECISION=fp32 -DSFML=OFF -DSFML_STATIC=OFF -DBUILD_SFML_FROM_SOURCE=OFF && cmake --build build_cpu_fp32 -j8 --config Release`
  4. Start Jupyter Notebook server
    * `source venv/bin/activate`
    * `jupyter notebook`
    * a web browser window should open. If this is not the case, manually copy the url shown in the terminal into a web browser and navigate to `PHOENIX-latest/examples`
    * in the subdirectories, e.g., `example_1` you can find jupyter notebooks to try out PHOENIX

---

In case you struggle installing the requirements or building PHOENIX you can follow our detailed [step by step guide](https://github.com/Schumacher-Group-UPB/PHOENIX/blob/master/manual.md).

---
## Building PHOENIX from source (recommended)

If the precompiled versions don’t meet your needs, or you wish to modify the source code, you can build PHOENIX yourself.

### Preparation
- If you use an NVIDIA GPU install the necessary drivers as listed on their website: (https://docs.nvidia.com/datacenter/tesla/driver-installation-guide/choose-an-installation-method.html).

- Install a nvidia-keyring and the necessary CUDA-package:
   ```bash
   wget https://developer.download.nvidia.com/compute/cuda/repos/${distro}/x86_64/cuda-keyring_1.1-1_all.deb
   dpkg -i cuda-keyring_1.1-1_all.deb
   apt update
   sudo apt install cuda-toolkit
   ```
   *IMPORTANT*: Do not install the `nvidia-cuda-toolkit` because it removes nvidia-open which is required for desktop rendering!

- Add nvcc to path:
	```bash
	echo -e '\n#Add CUDA-compiler to path:\nexport PATH=/usr/local/cuda/bin:$PATH\nexport LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH' >> ~/.bashrc
	```

### 1. Clone the Repository  
```bash
git clone --recursive https://github.com/Schumacher-Group-UPB/PHOENIX
```
Ensure the `--recursive` flag is used in order to fetch the SFML submodule.
   
### 2. Building SFML   
Install SFML as stated on their website:  
   ```bash
   sudo apt install \
	libxrandr-dev \
	libxcursor-dev \
	libxi-dev \
	libudev-dev \
	libfreetype-dev \
	libflac-dev \
	libvorbis-dev \
	libgl1-mesa-dev \
	libegl1-mesa-dev \
	libfreetype-dev
   ```
   Here an error can occur that openAL is not found. This is resolved by executing
   ```bash
   sudo apt install libopenal-dev
   ```
   Create makefiles and build SFML:  
   (execute in SFML folder of PHOENIX) 
   ```bash
   cmake -B build
   cmake --build build
   ```
   
### 3. Building PHOENIX  
   Configure CMAKE:   
   (execute in PHOENIX folder)
   ```bash
   cmake -S . -B build_gpu_fp64 -DBUILD_ARCH=gpu -DSFML=ON -DPRECISION=fp64
   ```
   * **`build_gpu_fp64`**: name of the created folder
   * **`BUILD_ARCH`**: `gpu` / `cpu`
   * **`SFML`**: `ON` / `OFF` (graphical output)
   * **`PRECISION`**: `fp32` / `fp64` (single- and double-precision respectively)
   
   Build:  
   (execute in build folder, so here in the build_gpu_fp64 folder)
   ```bash
   make SFML=TRUE SFML_PATH=/custompath/PHOENIX/external/SFML/ FP32=FALSE ARCH=CC
   ```
   * **`SFML_PATH`**: Path to your SFML installation folder.
     
      Replace `custompath` with the correct path on your machine.
   * **`FP32`**: Use single precision floats. Can be either set to `TRUE` or `FALSE`.
      
      Default is `FALSE`.
   * **`ARCH`**: CUDA compute capability related your graphics card. (e.g. ARCH=75)

      You can find the compute capability of your graphics card here: https://developer.nvidia.com/cuda/gpus
---

## Building PHOENIX

If the precompiled versions don’t meet your needs, or you wish to modify the source code, you can build PHOENIX yourself.

### Build with SFML Rendering (to generate "live" output)
1. **Clone the Repository**
   ```bash
   git clone --recursive https://github.com/Schumacher-Group-UPB/PHOENIX
   ```
   Ensure the `--recursive` flag is used to fetch the SFML submodule.

2. **Build SFML**  
   Use CMake or MSVC to compile SFML. Alternatively, download a precompiled version.

3. **Compile PHOENIX**
   ```bash
   make SFML=TRUE [SFML_PATH=path/to/SFML FP32=TRUE/FALSE ARCH=CC]
   ```
   - **`SFML_PATH`**: Specify the SFML installation directory (if not in the system PATH).  
   - **`FP32`**: Use single-precision floats (default: double-precision).  
   - **`ARCH`**: Specify the CUDA compute capability (e.g., `ARCH=75`).
   - **`OPTIMIZATION=-O0`**: Use to compile on Windows

### Build Without Rendering
1. **Clone the Repository**
   ```bash
   git clone https://github.com/Schumacher-Group-UPB/PHOENIX
   ```

2. **Compile PHOENIX**
   ```bash
   make [ARCH=CC]
   ```

### Build with CPU Kernel
To build PHOENIX for CPU execution, use the `CPU=TRUE` flag:
```bash
make CPU=TRUE COMPILER=g++
```

---

## Advanced Features

### FP32 Single Precision
By default, PHOENIX uses double-precision (64-bit) floats. For performance optimization in convergent simulations, you can switch to single-precision:
```bash
make FP32=TRUE
```

### CUDA Architecture
Optimize for your GPU by specifying its compute capability:
```bash
make ARCH=CC
```
Replace `CC` with your GPU’s compute capability (e.g., `ARCH=86` for an RTX 3070).

---

## Troubleshooting

### Compilation Errors Despite Correct Setup
- **Cause**: Version mismatch between Visual Studio and CUDA.  
- **Solution**: Update or downgrade one of the components. Compatible combinations:  
  - VS Community 17.9.2 + CUDA 12.4

### Missing SFML DLLs
Ensure the required `.dll` files are copied to the folder containing your executable.

---

## Benchmarks

PHOENIX has been benchmarked against MATLAB solvers and CPU implementations. Below are the runtime results (1024x1024 grid per iteration):

| System                     | FP32 GPU | FP64 GPU | FP32 CPU | FP64 CPU |
|----------------------------|----------|----------|----------|----------|
| RTX 3070 Ti / Ryzen 6c     | 311 µs   | 1120 µs  | 8330 µs  | 12800 µs |
| RTX 4090 / Ryzen 24c       | 94 µs    | 313 µs   | TBD      | TBD      |
| A100 / AMD Milan 7763      | 125 µs   | 232 µs   | 378 µs   | 504 µs   |

---

## Custom Kernel Development

PHOENIX is designed to allow users to customize its computational behavior by editing the kernels. While this requires some familiarity with the codebase, we’ve provided detailed instructions to make the process as straightforward as possible, even for those with limited C++ experience.

---

### Editing the Kernels

All kernel-related computations are found in the file:

- **Kernel Source File**: [`include/kernel/kernel_gp_compute.cuh`](include/kernel/kernel_gp_compute.cuh)  

The kernels are responsible for solving the nonlinear Schrödinger equation. To modify the kernel logic, locate the designated section within this file.

#### Key Sections of the Kernel Source File

- **Complete Kernel Function**:  
  This is used for the Runge-Kutta (RK) iterator. Modify this section for changes affecting the RK solver.

- **Partial Functions**:  
  These are used for the Split-Step Fourier (SSF) solver. If you want both solvers to reflect your changes, ensure you edit these as well.

---

### Adding Custom Variables

Adding new user-defined variables to the kernels is a two-step process. You’ll first define the variable in the program's parameter structure, then ensure it is parsed and accessible in the kernel.

#### Step 1: Define the Variable
Navigate to the **System Header File**:  
[`include/system/system_parameters.hpp`](include/system/system_parameters.hpp)

Find the `Parameters` struct and add your custom variable. There is a marked section for custom variable definitions, making it easy to locate.

**Examples**:
```cpp
real_number custom_var; // Define without a default value
real_number custom_var = 0.5; // Define with a default value
complex_number complex_var = {0.5, -0.5}; // Complex variable with default value 0.5 - 0.5i
```

#### Step 2: Parse the Variable
Navigate to the **System Initialization File**:  
[`source/system/system_initialization.cpp`](source/system/system_initialization.cpp)

Look for the designated location to add parsing logic. You can add a new command-line argument to set the variable's value dynamically when the program is executed.

**Examples**:
```cpp
if ((index = findInArgv("--custom_var", argc, argv)) != -1)
    p.custom_var = getNextInput(argv, argc, "custom_var", ++index);

if ((index = findInArgv("--custom_vars", argc, argv)) != -1) {
    p.custom_var_1 = getNextInput(argv, argc, "custom_var_1", ++index);
    p.custom_var_2 = getNextInput(argv, argc, "custom_var_2", index);
    p.custom_var_3 = getNextInput(argv, argc, "custom_var_3", index);
}
```

Once added, the variable will be accessible in the kernel code using `p.custom_var`.

You can now pass this variable as the command-line argument 

```
--custom_var a
--custom_vars a b c
```

---

### Adding New Envelopes

Custom envelopes are useful for spatially varying initial conditions or parameter fields. This process involves defining the envelope, parsing it, and linking it to a matrix.

#### Step 1: Define the Envelope
Navigate to the **System Header File**:  
[`include/system/system_parameters.hpp`](include/system/system_parameters.hpp)

Locate the envelope definitions, marked with comments for easy identification. Add your envelope to the list.

**Example**:
```cpp
PC3::Envelope pulse, pump, mask, initial_state, fft_mask, potential, custom_envelope;
// Add your envelope to the end of this line
```

#### Step 2: Parse the Envelope
Navigate to the **System Initialization File**:  
[`source/system/system_initialization.cpp`](source/system/system_initialization.cpp)

Find the section where other envelopes are parsed, and add your envelope.

**Example**:
```cpp
custom_envelope = PC3::Envelope::fromCommandlineArguments(argc, argv, "customEnvelope", false);
// The name used for parsing the command line is "customEnvelope"
```

You can now pass this envelope as a command-line argument using:
```
--customEnvelope [evelope arguments]
```

#### Step 3: Initialize the Envelope
Navigate to the **Solver Initialization File**:  
[`source/cuda_solver/solver/solver_initialization.cu`](source/cuda_solver/solver/solver_initialization.cu)

Find the designated location for envelope evaluation and add your code. This step ensures the envelope’s values are transferred to the appropriate matrix.

**Example**:
```cpp
std::cout << "Initializing Custom Envelopes..." << std::endl;
if (system.custom_envelope.size() == 0) {
    std::cout << "No custom envelope provided." << std::endl;
} else {
    system.custom_envelope(matrix.custom_matrix_plus.getHostPtr(), PC3::Envelope::AllGroups, PC3::Envelope::Polarization::Plus, 0.0);
    if (system.p.use_twin_mode) {
        system.custom_envelope(matrix.custom_matrix_minus.getHostPtr(), PC3::Envelope::AllGroups, PC3::Envelope::Polarization::Minus, 0.0);
    }
}
```

The envelope will now initialize the custom matrix during runtime.

---

### Adding New Matrices

To add new matrices for use in the solver, you’ll need to define the matrix, ensure it is properly constructed, and link it to the envelopes.

#### Step 1: Define the Matrix
Navigate to the **Matrix Container Header File**:  
[`include/solver/matrix_container.cuh`](include/solver/matrix_container.cuh)

Use the macro `DEFINE_MATRIX` to define your matrix. Add your definition at the designated location.

**Example**:
```cpp
DEFINE_MATRIX(complex_number, custom_matrix_plus, 1, true) \
DEFINE_MATRIX(complex_number, custom_matrix_minus, 1, use_twin_mode) \
```

- **Type**: Use `complex_number` or `real_number`.  
- **Name**: The matrix name (`custom_matrix_plus`).  
- **Condition for Construction**: Define conditions (`use_twin_mode`).

#### Step 2: Link to Envelopes
Once defined, matrices can be linked to envelopes in the solver initialization file:  
[`source/cuda_solver/solver/solver_initialization.cu`](source/cuda_solver/solver/solver_initialization.cu)

Use the initialization code as shown in the envelope example.

---

### Testing and Debugging

After making these changes:
1. **Compile the Code**: Rebuild the program using `make`.  
2. **Test Your Changes**: Run the executable with the new command-line arguments or input files.  
3. **Output the Results**: Use the matrix output functionality in `solver_output_matrices.cu` to inspect the results.

**Example**:
```cpp
system.filehandler.outputMatrixToFile(matrix.custom_matrix.getHostPtr(), system.p.N_x, system.p.N_y, header_information, "custom_matrix");
```

This outputs your matrix as a `.txt` file for easy analysis.

---

These instructions are designed to guide users through customizing the PHOENIX solver with minimal prior C++ experience. For further assistance, refer to existing code and comments within the files to better understand the structure. The compiler will flag errors, which can help identify and correct mistakes during the editing process.
