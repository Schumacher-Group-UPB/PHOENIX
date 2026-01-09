## Building PHOENIX from source - Linux (recommended)

If the precompiled versions don’t meet your needs, or you wish to modify the source code, you can build PHOENIX yourself.

### Preparation
- If you use an NVIDIA GPU install the necessary drivers as listed on their [website](https://docs.nvidia.com/datacenter/tesla/driver-installation-guide/choose-an-installation-method.html).

- Install a nvidia-keyring and the necessary CUDA-package:
   ```bash
   wget https://developer.download.nvidia.com/compute/cuda/repos/${distro}/x86_64/cuda-keyring_1.1-1_all.deb
   dpkg -i cuda-keyring_1.1-1_all.deb
   apt update
   sudo apt install cuda-toolkit
   ```
   Replace `${distro}` with your distribution.  
   Supported distros can be found at `https://developer.download.nvidia.com/compute/cuda/repos/`.   

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
   
   
### 2. Building PHOENIX  
   Configure CMAKE:   
   (execute in PHOENIX folder)
   ```bash
   cmake -S . -B build_gpu_fp64 -DBUILD_ARCH=gpu 
   ```
   * **`build_gpu_fp64`**: name of the created folder  
        Choose a name which fits to your build. If you want a build which runs on the CPU with 32-bit-precision it would make sense to name the folder build_cpu_fp32 
   * **`BUILD_ARCH`**: `gpu` / `cpu`
   
   Build:  
   (execute in build folder, so here in the build_gpu_fp64 folder)
   ```bash
   make
   ```

   It is recommended to specify the CUDA-architecture. See [Optimization](#optimization).

---

## Optimization

There are a few optimizations which can enhance the efficiency of calculations or are better tailored to your specific application.  
Therefore you will need to add some flags to the previous `cmake` and `make` commands. Those flags can be combined to your liking.

### CUDA Architecture
Optimize for your GPU by specifying its compute capability:
```bash
make ARCH=CC
```
Replace `CC` with your GPU’s compute capability (e.g., `ARCH=86` for an RTX 3070).

You can find the compute capability of your graphics card [here](https://developer.nvidia.com/cuda/gpus)

Example for a RTX 3070:  
```bash
cmake -S . -B build_gpu_fp64 -DBUILD_ARCH=gpu
```

```bash
make ARCH=86
```

### FP32 Single Precision
By default, PHOENIX uses double-precision (64-bit) floats. For performance optimization in convergent simulations, you can switch to single-precision:
```bash
make FP32=TRUE
```

Example:

```bash
cmake -S . -B build_gpu_fp32 -DBUILD=gpu
```

```bash
make FP32=TRUE
```

### Build with CPU Kernel
To build PHOENIX for CPU execution, use the `CPU=TRUE` flag:
```bash
make CPU=TRUE COMPILER=g++
```

Example:
```bash
cmake -S . -B build_cpu_fp64 -DBUILD=cpu
```

```bash
make CPU=TRUE COMPILER=g++
```
---

## Build with SFML Rendering (to generate "live" output)
### 1. Clone the Repository
```bash
git clone --recursive https://github.com/Schumacher-Group-UPB/PHOENIX
```
Ensure the `--recursive` flag is used to fetch the SFML submodule.

### 2. Building SFML   
Install SFML as stated on their [website](https://www.sfml-dev.org/tutorials/3.0/getting-started/cmake/):  
```bash
sudo apt update \
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
cmake -S . -B build_gpu_fp64 -DBUILD_ARCH=gpu -DSFML=ON
```
   
Build:  
(execute in build folder, so here in the build_gpu_fp64 folder)
```bash
make SFML=TRUE SFML_PATH=/custompath/PHOENIX/external/SFML/
```
* **`SFML_PATH`**: Path to your SFML installation folder.    
Replace `custompath` with the correct path on your machine.

---

## Running PHOENIX


---



