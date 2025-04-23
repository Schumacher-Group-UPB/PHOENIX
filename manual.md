# Requirements
- [MSVC](https://visualstudio.microsoft.com/de/downloads/) [Windows] or [GCC](https://gcc.gnu.org/) [Linux]
  Older versions of MSVC can be downloaded [from here](https://learn.microsoft.com/en-us/visualstudio/releases/2022/release-history#fixed-version-bootstrappers).
- [CUDA](https://developer.nvidia.com/cuda-downloads)
- Optional: [SFML](https://www.sfml-dev.org/download.php) v 2.6.x
- Optional: [FFTW](https://www.fftw.org/) for the CPU version
- Optional: [Gnuplot](http://www.gnuplot.info/) for fast plotting

If you are on Windows it is required to install some kind of UNIX based software distribution like [msys2](https://www.msys2.org/) or any wsl UNIX distribution for the makefile to work.
You also need to add the VS cl.exe as well as the CUDA nvcc.exe to your path if you want to compile PHOENIX yourself.
Also, make sure to check the C++ Desktop Development section in the VS installer! Then, add [cl.exe](https://stackoverflow.com/questions/7865432/command-line-compile-using-cl-exe) to your [path](https://stackoverflow.com/questions/9546324/adding-a-directory-to-the-path-environment-variable-in-windows)

# Getting Started with PHOENIX

To successfully execute PHOENIX for the first time, follow the steps outlined below:

#### 1. Verify Your Hardware

PHOENIX is designed to run on CPUs or Nvidia GPUs. Verify your hardware to ensure compatibility:

- **Windows**: Open the Start menu, type "Device Manager," and press Enter to launch the Control Panel. Expand the "Display adapters" section to see your GPU listed. Right-click on the listed GPU and select "Properties" to view the manufacturer details if necessary.
- **Linux**: Use the command `lspci` to identify the GPU.

#### Steps 2 - 4 will give you detailed instructions on how to install the mandatory requirements. If you have already installed them or do not need help, please continue with step 5.

#### 2. Install Visual Studio Microsoft (Windows) or the GNU Compiler GCC (linux)

Select the right software for your operating system. Download and install it. If you are installing Microsoft Visual Studios, make sure you check "C++ Desktop Development section" during the installation process (see Screenshot). **Do not make any changes to the installation path for Visual Studio!**
![vs_install](https://github.com/user-attachments/assets/dbff5749-e292-438c-8261-84c42905ffff)

#### 3. Install CUDA and MSYS2

Download CUDA [here](https://developer.nvidia.com/cuda-downloads) and follow the instructions given. **Do not make any changes to the installation path for CUDA!**
Download MSYS2 [here](https://www.msys2.org/) and install it.

#### 4. Add the new executables to your path

Open your Enviroment Variables

- **Windows**: Right-click on Start-button then click on "System" in the context menu. Click "Advanced system settings" and go to "Advanced" tab. Now click Enviroment Variables. Here, double-click on "Path" in the lower section. Click on new to add to your path.

Now you need to find the path to your cl.exe of Visual Studio and nvcc.exe for CUDA, if you have not changed the preset path during installation you should find your executable at the same location as marked orange in the screenshot.
![add_path](https://github.com/user-attachments/assets/1e2d479c-993f-4ce5-acc9-61212484992b)

Note that in your case the version-number in the path (\14.37.32822\ for VS and \v12.3\ for CUDA) can be different.

#### Great! Now you can continue with executing PHOENIX for the very first time.

# Recommended: Build PHOENIX yourself

We use a simple Makefile to create binaries for either Windows or Linux. How to build PHOENIX yourself is explained below.

### Errors on Compilation even though VS and CUDA are installed, CUDA and cl are in the path variable

If you get syntax or missing file errors, your Visual Studio installation may be incompatible with your current CUDA version. Try updating or downgrading either CUDA or VS, depending on what's older on your system. Older versions of VS can be downloaded [from here](https://learn.microsoft.com/en-us/visualstudio/releases/2022/release-history#fixed-version-bootstrappers). Don't forget to add the new VS installation to your path. You can download older version for CUDA directly from Nvidias website. 

Current working combinations: VS Community Edition or VS Build Tools 17.9.2 - CUDA 12.4

### Optional: Build with SFML rendering
1 -  Clone the repository using
```    
    git clone --recursive https://github.com/AG-Schumacher-UPB/PHOENIX
``` 
This will also download the SFML repository. I suggest also downloading a precompiled version of the library using the link at the top.

2 - Build SFML using CMake and/or MSVC

Alternatively, download SFML 2.6.1 or higher for MSVC if you are on Windows or for gcc if you are on linux.

3 - Compile PHOENIX using 

```
make SFML=TRUE/FALSE [SFML_PATH=external/SFML/ FP32=TRUE/FALSE ARCH=NONE/ALL/XY]
```
Note, that arguments in `[]` are optional and default to `FALSE` (or `NONE`) if omitted. Pass only one parameter to the arguments, for example *either* `TRUE` *or* `FALSE`.

When using SFML rendering, you need to either install all SFML libraries correctly, or copy the .dll files that come either with building SFML yourself or with the download of precompiled versions to the main folder of your PHOENIX executable. If you do not do this and still compile with SFML support, PHOENIX will crash on launch. For the compilation, you also *need* to provide the path to your SFML installation if it's not already in your systems path. You can do this by setting the `SFML_PATH=...` variable when compiling, similar to passing `SFML=TRUE`. The SFML path needs to contain the SFML `include/...` as well as the `lib/...` folder. These are NOT contained directly in the recursively cloned SFML repository, but rather get created when building SFML yourself. They are also contained in any precompiled version of SFML, so I suggest to simply download a precompiled version.

### Build without rendering
1 - Clone the repositry using 
```bash
git clone https://github.com/Schumacher-Group-UPB/PHOENIX
```

2 - Compile PHOENIX using 
```bash
make [TETM=TRUE/FALSE ARCH=NONE/ALL/XY]`
```

### Build with CPU Kernel
If you want to compile this program as a CPU version, you can do this by adding the `CPU=TRUE` compiler flag to `make`.
While nvcc can compile this into CPU code, it generally makes more sense to use [GCC](https://gcc.gnu.org/) or any other compiler of your choice, as those are generally faster and better for CPU code than nvcc.
You can specify the compiler using the `COMPILER=` flag to `make`.

```bash
make [SFML=TRUE/FALSE FP32=TRUE/FALSE TETM=TRUE/FALSE CPU=TRUE COMPILER=g++]
```

## FP32 - Single Precision
By default, the program is compiled using double precision 64b floats.
For some cases, FP32 may be sufficient for convergent simulations.
To manually change the precision to 32b floats, use

```
FP32=TRUE
```

when using the makefile.

# CUDA Architexture
You can also specify the architexture used when compiling PHOENIX. The release binaries are compiled with a variety of Compute Capabilities (CC). To ensure maximum performance, picking the CC for your specific GPU and using 

```
ARCH=xy
```

when using the Makefile, where xy is your CC, is most beneficial.

# When building on Windows
If you build PHOENIX on Windows it is required to use the Optimization flag

```
OPTIMIZATION=-O0
```

# Example (valid for Windows)
make TARGET=PHOENIX.exe SFML=FALSE GPU=TRUE FP32=TRUE OPTIMIZATION=-O0 -j24 

#### Optional: Download and Prepare PHOENIX

Only use the precompiled PHOENIX executable if your version-numbers installed match the above. Otherwhise it is highly recommended to compile PHOENIX yourself.

Download the precompiled PHOENIX executable from [here](https://github.com/AG-Schumacher-UPB/PHOENIX/releases). This version supports single-precision float operations on your GPU and includes the SFML multimedia library for visualization.

1. Place the downloaded executable into an empty directory on your system.
2. Open a console window and navigate to your newly created PHOENIX directory.


#### 6. Execute PHOENIX

You are now ready to run PHOENIX for the first time. Copy and execute the following command in your console:

```sh
./PHOENIX.exe[.o] --N 400 400 --L 40 40 --boundary zero zero --tmax 1000 --initialState 0.1 add 70 70 0 0 plus 1 0 gauss+noDivide --gammaC 0.15 --pump 100 add 4.5 4.5 0 0 both 1 none gauss+noDivide+ring --outEvery 5 --path output\
```

This command will:

- Execute PHOENIX on a 400x400 grid with zero boundary conditions for a real-space grid of 40x40 micrometers.
- Evolve the system for 1 ns (`--tmax`).
- Use PHOENIX-predefined pump and initial conditions, defining the initial state as a vortex with topological charge +1 (`--initialState`).
- Set the polariton loss rate of the condensate to 0.15 (`--gammaC`).
- Create a ring-shaped pump (`--pump`).
- Set the data output rate to every 5 picoseconds (`--outEvery`) and specify the output directory (`--path output`).

For further details on the command syntax, use `./PHOENIX.exe[.o] --help`.

#### 7. Review Results

Upon successful execution, the time-evolution will be displayed. After the program completes, it will print a summary of the process. The output directory will contain the desired results.

Congratulations on performing your first GPU-accelerated calculation using PHOENIX. For a comprehensive introduction to all other features of PHOENIX, please refer to the extended documentation.

If you want to compile your own (modified) version of PHOENIX please read on.
