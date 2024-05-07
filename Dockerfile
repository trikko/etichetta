FROM trikko/dlang-ubuntu
RUN sudo apt-get update
RUN sudo apt-get install libgtk-3-0 git -y

RUN git clone https://github.com/trikko/etichetta

RUN cd etichetta && dub build --build=release

WORKDIR /home/user/src/etichetta

ENTRYPOINT ./output/bin/etichetta