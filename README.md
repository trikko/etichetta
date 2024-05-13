# Etichetta [![License](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/trikko/etichetta/blob/main/LICENSE) [![Donate](https://img.shields.io/badge/paypal-buy_me_a_beer-FFEF00?logo=paypal&logoColor=white)](https://paypal.me/andreafontana/5)
<sup>International Phonetic Alphabet: /e-ti-'ket-ta/ [mp3](https://www.dropbox.com/scl/fi/ow41ztln8vcbw8t10bcd1/etichetta.mp3?rlkey=6lecfwxq9h2aj6nzzimjlejdp&st=n1d6clii&dl=0)</sup>

Etichetta is a project that aims to provide a simple and efficient way to annotate images.

<img src="https://github.com/trikko/etichetta/assets/647157/09be6f08-d9e8-420a-aeee-2fed69fe6c61" width=480>

<sup>You can download [here](https://www.printables.com/@AndreaFontana) those 3d printed models.</sup>

## Quick start
A simple tutorial to start using Etichetta can be found on the [HOWTO](https://github.com/trikko/etichetta/blob/main/HOWTO.md) page.

## Prebuilt packages (Linux, Windows)
[![Snap](https://img.shields.io/badge/-Linux_AppImage_-red.svg?style=for-the-badge&logo=linux)](https://github.com/trikko/etichetta/releases/latest/download/etichetta-x86_64.AppImage)

[![Windows](https://img.shields.io/badge/-Windows_installer-blue.svg?style=for-the-badge&logo=windows)](https://github.com/trikko/etichetta/releases/latest/download/etichetta-setup.exe)

## Build from source (Linux, Windows)

To build etichetta from source install a dlang compiler (DMD, LDC, GDC) from [dlang.org](https://dlang.org)
On windows you also need MSBuild package (c/c++ compiler) and Windows SDK.

Then:

```
git close https://github.com/trikko/etichetta
cd etichetta
dub run :setup
dub
```

To use GPU acceleration, read `ext/README.md`.

## Etichetta on macOS (with Docker and XQuartz)

I do not have access to any machine with macOS and therefore it is difficult to perform the necessary tests for development. Anyway to try etichetta on a macOS machine, you can run it inside a Docker container and connect a display, using XQuartz.

You can use the scripts inside the folder `macos-docker`.

Build the last docker image running `./build-docker-etichetta.sh` and run it using `./run-docker-etichetta.sh`

## License

This project is licensed under the [MIT License](https://github.com/your-username/etichetta/blob/main/LICENSE).
