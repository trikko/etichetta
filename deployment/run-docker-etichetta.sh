#!/bin/bash
open -a XQuartz
xhost +localhost
docker run -ti --rm -e DISPLAY=host.docker.internal:0 -v /tmp/.X11-unix:/tmp/.X11-unix -v $HOME:/etichetta docker-etichetta
