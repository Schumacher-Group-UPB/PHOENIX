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

