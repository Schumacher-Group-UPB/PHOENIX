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

1. Quickstart Guide
    - [Docker container](https://github.com/Schumacher-Group-UPB/PHOENIX/blob/master/manual_docker.md)
    - [Prebuilt binaries](https://github.com/Schumacher-Group-UPB/PHOENIX/blob/master/manual_binaries.md)
2. Building PHOENIX from source
    - [Linux (recommended)](https://github.com/Schumacher-Group-UPB/PHOENIX/blob/master/manual_linux.md)
    - [Windows](https://github.com/Schumacher-Group-UPB/PHOENIX/blob/master/manual_windows.md)
    - [MacOS](https://github.com/Schumacher-Group-UPB/PHOENIX/blob/master/manual_mac.md)

3. [Custom Kernel Development](https://github.com/Schumacher-Group-UPB/PHOENIX/blob/master/custom_kernel.md)

---

## Benchmarks

PHOENIX has been benchmarked on different GPUs and CPUs. Below are the runtime results (1024x1024 grid per iteration):

| System                     | FP32 GPU | FP64 GPU | FP32 CPU | FP64 CPU |
|----------------------------|----------|----------|----------|----------|
| RTX 3070 Ti / Ryzen 6c     | 311 µs   | 1120 µs  | 8330 µs  | 12800 µs |
| RTX 4090 / Ryzen 24c       | 94 µs    | 313 µs   | TBD      | TBD      |
| A100 / AMD Milan 7763      | 125 µs   | 232 µs   | 378 µs   | 504 µs   |

Please refer to [Computer Physics Communications, 315, 109689 (2025)](https://www.sciencedirect.com/science/article/pii/S0010465525001912) for an in-depth analysis.

---

