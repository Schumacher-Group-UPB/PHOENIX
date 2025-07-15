#FROM ubuntu:24.04
FROM nvidia/cuda:12.9.1-devel-ubuntu24.04

RUN apt-get update && apt-get install -y build-essential libfftw3-dev libsfml-dev build-essential python3-venv git cmake python3-pip curl wget
RUN apt clean

RUN cd /opt && git clone --recursive https://github.com/robertschade/PHOENIX && cd PHOENIX && git checkout latest
#RUN cd /opt && git clone --recursive https://github.com/Schumacher-Group-UPB/PHOENIX && cd PHOENIX && git checkout latest

RUN cd /opt/PHOENIX && python3 -m venv venv
RUN . /opt/PHOENIX/venv/bin/activate && cd /opt/PHOENIX && pip install .

RUN cd /opt/PHOENIX && cmake -B build_cpu_fp64 -S . -DBUILD_ARCH=cpu -DTUNE=other -DPRECISION=fp64 -DSFML=OFF -DSFML_STATIC=OFF -DBUILD_SFML_FROM_SOURCE=OFF && cmake --build build_cpu_fp64 -j8 --config Release
RUN cd /opt/PHOENIX && cmake -B build_cpu_fp32 -S . -DBUILD_ARCH=cpu -DTUNE=other -DPRECISION=fp32 -DSFML=OFF -DSFML_STATIC=OFF -DBUILD_SFML_FROM_SOURCE=OFF && cmake --build build_cpu_fp32 -j8 --config Release
RUN cd /opt/PHOENIX && cmake -B build_gpu_fp64 -S . -DBUILD_ARCH=gpu -DTUNE=other -DPRECISION=fp64 -DSFML=OFF -DSFML_STATIC=OFF -DBUILD_SFML_FROM_SOURCE=OFF -DARCH=all && cmake --build build_gpu_fp64 -j8 --config Release
RUN cd /opt/PHOENIX && cmake -B build_gpu_fp32 -S . -DBUILD_ARCH=gpu -DTUNE=other -DPRECISION=fp32 -DSFML=OFF -DSFML_STATIC=OFF -DBUILD_SFML_FROM_SOURCE=OFF -DARCH=all && cmake --build build_gpu_fp32 -j8 --config Release

EXPOSE 127.0.0.1:8888:8888/tcp
WORKDIR /opt/PHOENIX/
ENV PHOENIX_BIN_DIR=/opt/PHOENIX/bin
CMD . /opt/PHOENIX/venv/bin/activate && jupyter notebook --ip=0.0.0.0 --port=8888 --no-browser --allow-root --NotebookApp.token=''
