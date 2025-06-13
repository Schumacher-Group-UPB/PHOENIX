FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Install base dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    wget \
    curl \
    git \
    unzip \
    pkg-config \
    libx11-dev \
    libxrandr-dev \
    libxi-dev \
    libudev-dev \
    libopenal-dev \
    libpthread-stubs0-dev \
    libfftw3-dev \
    ca-certificates \
    gnupg \
    software-properties-common \
    lsb-release \
    libsfml-dev

# Install GCC (default is gcc-13 on Ubuntu 24.04)
RUN gcc --version && g++ --version

# Install latest CMake (>=3.29)
RUN wget https://github.com/Kitware/CMake/releases/download/v3.29.3/cmake-3.29.3-linux-x86_64.sh && \
    chmod +x cmake-3.29.3-linux-x86_64.sh && \
    ./cmake-3.29.3-linux-x86_64.sh --skip-license --prefix=/usr/local && \
    rm cmake-3.29.3-linux-x86_64.sh

# Install CUDA (nvcc) via official NVIDIA APT repo
RUN wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-ubuntu2404.pin && \
    mv cuda-ubuntu2404.pin /etc/apt/preferences.d/cuda-repository-pin-600 && \
    wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb && \
    dpkg -i cuda-keyring_1.1-1_all.deb && \
    apt-get update && \
    apt-get install -y cuda-nvcc-12-5 cuda-toolkit-12-5 && \
    rm -f cuda-keyring_1.1-1_all.deb


ENV PATH=/usr/local/cuda/bin:$PATH

# Build PHOENIX from source
WORKDIR /opt
RUN git clone --recursive https://github.com/Schumacher-Group-UPB/PHOENIX && \
    cd PHOENIX && \
    cmake -B build_gpu -S . \
    -DBUILD_ARCH=gpu \
    -DPRECISION=fp32 \
    -DSFML=ON \
    -DSFML_STATIC=OFF \
    -DBUILD_SFML_FROM_SOURCE=OFF && \
    cmake --build build_gpu -j8 --config Release && \
    cmake -B build_cpu -S . \
    -DBUILD_ARCH=cpu \
    -DPRECISION=fp32 \
    -DSFML=ON \
    -DSFML_STATIC=OFF \
    -DBUILD_SFML_FROM_SOURCE=OFF && \
    cmake --build build_cpu -j8 --config Release && \
    mkdir -p /workspace && \
    cp -r bin/* /workspace/

WORKDIR /workspace

# Start an interactive shell
CMD ["/bin/bash"]
