#!/bin/bash
# Build the AppImage. Run it from anywhere: it works on the repository this script belongs to.
set -euo pipefail

cd "$(dirname "$0")/.."

dub run :setup
dub build --build=release

cd appimage

# Tools required to build the AppImage, pinned so a new upstream version can't break the build
LINUXDEPLOY_VERSION="1-alpha-20251107-1"
GTK_PLUGIN_COMMIT="7a3fbc31a9e5075073ff8790f26effbac5f84453"

wget -c "https://raw.githubusercontent.com/linuxdeploy/linuxdeploy-plugin-gtk/${GTK_PLUGIN_COMMIT}/linuxdeploy-plugin-gtk.sh"
wget -c "https://github.com/linuxdeploy/linuxdeploy/releases/download/${LINUXDEPLOY_VERSION}/linuxdeploy-x86_64.AppImage"

# make them executable so that we can call them (and also, plugins called from linuxdeploy are called like binaries)
chmod +x linuxdeploy-x86_64.AppImage linuxdeploy-plugin-gtk.sh

# linuxdeploy must bundle our onnxruntime, not one installed on the system: the binary rpath
# (../../ext/onnx/lib) doesn't work from inside AppDir, so point it there explicitly
export LD_LIBRARY_PATH="$(realpath ../ext/onnx/lib)${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# Create the AppImage directory
./linuxdeploy-x86_64.AppImage --appdir=AppDir

# Copy the application binary to the AppDir
cp ../output/bin/etichetta AppDir/usr/bin/

# The WebGPU plugin is loaded at runtime, linuxdeploy can't find it by itself
mkdir -p AppDir/usr/lib
cp ../ext/onnx/lib/libonnxruntime_providers_webgpu.so AppDir/usr/lib/

# Run the build. No strip: the strip bundled with linuxdeploy can't read libraries of newer
# distributions (.relr.dyn sections) and would stop the build
NO_STRIP=1 DEPLOY_GTK_VERSION=3 ./linuxdeploy-x86_64.AppImage --plugin gtk -i ../res/etichetta.svg -d ../res/etichetta.desktop --appdir=AppDir --output appimage
