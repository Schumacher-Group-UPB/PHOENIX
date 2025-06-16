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

# Install PowerShell Core and modules
RUN apt-get update && apt-get install -y wget apt-transport-https software-properties-common gnupg && \
    wget -q https://packages.microsoft.com/config/ubuntu/24.04/packages-microsoft-prod.deb && \
    dpkg -i packages-microsoft-prod.deb && \
    apt-get update && apt-get install -y powershell && \
    pwsh -Command "Set-PSRepository -Name PSGallery -InstallationPolicy Trusted; Install-Module PSReadLine -Force -Scope AllUsers; Install-Module PowerType -Force -Scope AllUsers" && \
    mkdir -p /etc/powershell && \
    echo "Import-Module PSReadLine; Import-Module PowerType; Enable-PowerType; Set-PSReadLineOption -PredictionSource HistoryAndPlugin; Set-PSReadLineOption -PredictionViewStyle ListView; Set-PSReadLineOption -Colors @{ Command = '#80CBC4'; Number = '#F78C6C'; Member = '#82AAFF'; Operator = '#89DDFF'; Type = '#C792EA'; Variable = '#C3E88D'; Parameter = '#FFCB6B'; ContinuationPrompt = '#757575'; Default = '#D0D0D0'; String = '#C3E88D'; Keyword = '#FF5370'; Comment = '#546E7A'; InlinePrediction = '#555555' }; function phoenix { param([Parameter(Mandatory=\$true)][ValidateSet('cpu','gpu')][string]\$arch, [Parameter(ValueFromRemainingArguments=\$true)][string[]]\$args); \$binary = switch (\$arch) { 'cpu' { '/workspace/cpu/PHOENIX_cpu_fp32_sfml' } 'gpu' { '/workspace/gpu/PHOENIX_gpu_fp32_sfml' } }; & \$binary @args }" > /etc/powershell/Microsoft.PowerShell_profile.ps1 && \
    echo "function phoenix { param([string]\$arch = 'gpu', [Parameter(ValueFromRemainingArguments=\$true)][string[]]\$args); \$binary = switch (\$arch) { 'cpu' { '/workspace/cpu/PHOENIX_cpu_fp32_sfml' } 'gpu' { '/workspace/gpu/PHOENIX_gpu_fp32_sfml' } default { Write-Host 'Usage: phoenix [cpu|gpu] [args...]'; return } }; & \$binary @args }; Set-Alias phoenix-gpu '/workspace/gpu/PHOENIX_gpu_fp32_sfml'; Set-Alias phoenix-cpu '/workspace/cpu/PHOENIX_cpu_fp32_sfml'" >> /etc/powershell/Microsoft.PowerShell_profile.ps1
# Also install profile for CurrentUserCurrentHost
RUN mkdir -p /root/.config/powershell && \
    cp /etc/powershell/Microsoft.PowerShell_profile.ps1 /root/.config/powershell/Microsoft.PowerShell_profile.ps1
    # Copy phoenix.ps1 dictionary into PowerType module folder
COPY tools/phoenix_docker.ps1 /usr/local/share/powershell/Modules/PowerType/0.1.0/Dictionaries/phoenix.ps1
RUN echo 'phoenix() { case "$1" in cpu) shift; /workspace/cpu/PHOENIX_cpu_fp32_sfml "$@" ;; gpu) shift; /workspace/gpu/PHOENIX_gpu_fp32_sfml "$@" ;; "" ) /workspace/gpu/PHOENIX_gpu_fp32_sfml ;; *) echo "Usage: phoenix [cpu|gpu] [args...]"; return 1 ;; esac; }; export -f phoenix; alias phoenix-gpu="/workspace/gpu/PHOENIX_gpu_fp32_sfml"; alias phoenix-cpu="/workspace/cpu/PHOENIX_cpu_fp32_sfml"' >> /etc/bash.bashrc

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

RUN mkdir -p /etc/phoenix && echo "Welcome to PHOENIX! 🔥🐍\n========================================================================================================================\n\n                            _____    _     _    _____    _______   __   _   _____   _     _\n                           |_____]   |_____|   |     |   |______   | \\  |     |      \\___/\n                           |       . |     | . |_____| . |______ . |  \\_| . __|__ . _/   \\_ .\n\n                   ⚛️  Paderborn Highly Optimized and Energy-efficient solver for two-dimensional\n                                Nonlinear Schrödinger equations with Integrated eXtensions\n                                                   Version: v0.3.2\n\n------------------------------------------------------------------------------------------------------------------------\n\n📢  If you use this software in published work, please cite:\n    Bauch, D., Schade, R., Wingenbach, J., and Schumacher, S.  \n    *PHOENIX: A High-Performance Solver for the Gross-Pitaevskii Equation [Computer software].*  \n    🔗 https://github.com/Schumacher-Group-UPB/PHOENIX\n\n🛠️  Usage:\n    phoenix cpu [args]      ▶ Run CPU-based solver\n    phoenix gpu [args]      ▶ Run GPU-based solver\n\n💡  Pro tip: use it interactively with PowerShell for autocompletion & inline suggestions!\n\n    pwsh [Enter]            ▶ You will end up in a powershell environment\n    > phoenix cpu [args]\n    > phoenix gpu [args]\n\n🚀  Powered by ❤️, physics, and optimized C++\n========================================================================================================================" > /etc/phoenix/welcome.txt

# Start an interactive shell
CMD ["bash", "-c", "cat /etc/phoenix/welcome.txt && exec bash"]
