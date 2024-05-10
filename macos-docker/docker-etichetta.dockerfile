FROM trikko/dlang-ubuntu
RUN sudo apt-get update
RUN sudo apt-get install libgtk-3-0 git -y
RUN curl -s https://api.github.com/repos/trikko/etichetta/tags | grep "\s.*\"name\"" | sort -r | head -n 1 | grep -o "v[0-9].[0-9].[0-9]" > /tmp/version
RUN git clone https://github.com/trikko/etichetta --depth 1 -b `cat /tmp/version`
RUN cd etichetta && dub build --build=release
WORKDIR /home/user/src/etichetta/output/bin

ENTRYPOINT ./etichetta