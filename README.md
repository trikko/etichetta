# Etichetta [![License](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/trikko/etichetta/blob/main/LICENSE) [![Donate](https://img.shields.io/badge/paypal-buy_me_a_beer-FFEF00?logo=paypal&logoColor=white)](https://paypal.me/andreafontana/5)
<sub>[IPA](https://en.wiktionary.org/wiki/Wiktionary:International_Phonetic_Alphabet): /e-ti-'ket-ta/</sub>

Etichetta is a project that aims to provide a simple and efficient way to annotate images.

## Prebuilt packages (Linux, Windows)
> [!NOTE]
> The packages are not yet available. You can build and run a preview version of etichetta by following the instructions below.

[![Snap](https://img.shields.io/badge/-Linux_SNAP_-red.svg?style=for-the-badge&logo=linux)](https://github.com/trikko/tshare/releases/latest/download/etichetta.snap)

[![Windows](https://img.shields.io/badge/-Windows_installer-blue.svg?style=for-the-badge&logo=windows)](https://github.com/trikko/tshare/releases/latest/download/etichetta-setup.exe)

## Build from source (Linux, Windows)

To build etichetta from source install a dlang compiler (DMD, LDC, GDC), checkout this repository and build.

```bash
git clone https://github.com/trikko/etichetta
dub --build=release
```

## Etichetta on macOS (with Docker and XQuartz)

To run etichetta on a macOS machine, you can run it inside a Docker container and connect a display, using XQuartz.

### Step #1. Build the docker image (one time)
Save the following code in a file named `Dockerfile`:

```Dockerfile
FROM trikko/dlang-ubuntu
RUN sudo apt-get update
RUN sudo apt-get install libgtk-3-0 git -y
RUN git clone https://github.com/trikko/etichetta
RUN cd etichetta && dub build --build=release
WORKDIR /home/user/src/etichetta

ENTRYPOINT ./output/bin/etichetta
```

Build the image:

```
docker build -t etichetta .
```

### Step #2. Run the container
```bash
open -a XQuartz
xhost +localhost
docker run -ti --rm -e DISPLAY=host.docker.internal:0 -v /tmp/.X11-unix:/tmp/.X11-unix etichetta`
```

## License

This project is licensed under the [MIT License](https://github.com/your-username/etichetta/blob/main/LICENSE).
