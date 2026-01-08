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
