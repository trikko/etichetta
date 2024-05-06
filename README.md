# Etichetta [![License](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/trikko/etichetta/blob/main/LICENSE) [![Donate](https://img.shields.io/badge/paypal-buy_me_a_beer-FFEF00?logo=paypal&logoColor=white)](https://paypal.me/andreafontana/5)
<sup>International Phonetic Alphabet: /e-ti-'ket-ta/ [mp3](https://www.dropbox.com/scl/fi/ow41ztln8vcbw8t10bcd1/etichetta.mp3?rlkey=6lecfwxq9h2aj6nzzimjlejdp&st=n1d6clii&dl=0)</sup>

Etichetta is a project that aims to provide a simple and efficient way to annotate images.

<img src="https://github.com/trikko/etichetta/assets/647157/7ab51282-e2ed-435e-b44b-f9073c0df18c" width=480>

## Quick start
|  |  |
| -- | -- |
| <img src="https://github.com/trikko/etichetta/assets/647157/80822b8f-052c-4564-99d9-b4292d70bc72" width=480> | Press `SHIFT` and draw on the image to select the area to zoom in. Press `Z` to goes back to full view. |  
| <img src="https://github.com/trikko/etichetta/assets/647157/71d4eba5-52e9-4334-a600-918f6642d268" width=480> | Press `Z` to zoom into the current annotation. Press `N` (next) and `P` (previous) to cycle thru annotations. |
| <img src="https://github.com/trikko/etichetta/assets/647157/32c44c48-e04e-4003-9ba7-6178c4571039" width=480> | Press `SPACE` to start drawing a new annotation. Press `ESC` to cancel, `ENTER` to save and go back to edit mode or `SPACE` to save and start another annotation. Press `G` to toggle guidelines. |
| <img src="https://github.com/trikko/etichetta/assets/647157/3bbd1148-6a75-4cfd-8718-3d2bfbf9dcb5" width=480> | Press a key from `1` to `9` to change the label. Or press `L` and search by typing label's name or index. | 



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

I do not have access to any machine with macOS and therefore it is difficult to perform the necessary tests for development. Anyway to try etichetta on a macOS machine, you can run it inside a Docker container and connect a display, using XQuartz.

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
