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

1. [Quickstart Guide](https://github.com/Schumacher-Group-UPB/PHOENIX/blob/master/quickstart.md)
2. [Building PHOENIX from source]
    - [Linux (recommended)](https://github.com/Schumacher-Group-UPB/PHOENIX/blob/master/manual_linux.md)
    - [Windows](https://github.com/Schumacher-Group-UPB/PHOENIX/blob/master/manual_windows.md)
    - [MacOS](https://github.com/Schumacher-Group-UPB/PHOENIX/blob/master/manual_mac.md)


3. [Advanced Features](#advanced-features)
    - [FP32 Precision](#fp32-single-precision)
    - [CUDA Architecture Optimization](#cuda-architecture)
4. [Troubleshooting](#troubleshooting)
5. [Benchmark Examples](#benchmarks)
6. [Custom Kernel Development](#custom-kernel-development)
    - [Adding Custom Variables](#adding-new-variables-to-the-kernels)
    - [Defining Custom Envelopes](#adding-new-envelopes-to-the-kernels)
7. [Current Issues](#current-issues)

---


---

In case you struggle installing the requirements or building PHOENIX you can follow our detailed [step by step guide](https://github.com/Schumacher-Group-UPB/PHOENIX/blob/master/manual.md).

---

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
