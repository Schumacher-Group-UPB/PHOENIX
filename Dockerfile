#FROM --platform=linux/amd64 ubuntu:24.04
FROM --platform=linux/adm64 nvidia/cuda:12.9.1-devel-ubuntu24.04

RUN apt-get update && apt-get install -y build-essential libfftw3-dev libsfml-dev build-essential python3-venv git cmake python3-pip
RUN apt clean

RUN cd /opt && git clone --recursive https://github.com/Schumacher-Group-UPB/PHOENIX 

RUN cd /opt/PHOENIX && python3 -m venv venv
RUN . /opt/PHOENIX/venv/bin/activate && pip install numpy matplotlib h5py jupyter scipy

RUN cd /opt/PHOENIX && cmake -B build_cpu_fp64 -S . -DBUILD_ARCH=cpu -DTUNE=other -DPRECISION=fp64 -DSFML=ON -DSFML_STATIC=OFF -DBUILD_SFML_FROM_SOURCE=OFF && cmake --build build_cpu_fp64 -j8 --config Release
RUN cd /opt/PHOENIX && cmake -B build_cpu_fp32 -S . -DBUILD_ARCH=cpu -DTUNE=other -DPRECISION=fp32 -DSFML=ON -DSFML_STATIC=OFF -DBUILD_SFML_FROM_SOURCE=OFF && cmake --build build_cpu_fp32 -j8 --config Release

EXPOSE 8888/tcp

WORKDIR /opt/PHOENIX/

CMD . /opt/PHOENIX/venv/bin/activate && jupyter notebook --ip=0.0.0.0 --port=8888 --no-browser --allow-root --NotebookApp.token=''

