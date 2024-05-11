#!/bin/bash

cd ..

# This script is used to build the AppImage for the application.
dub run :setup
dub build --build=release

cd appimage

# Download the tools required to build the AppImage.
wget -c "https://raw.githubusercontent.com/linuxdeploy/linuxdeploy-plugin-gtk/master/linuxdeploy-plugin-gtk.sh"
wget -c "https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage"

# make them executable so that we can call them (and also, plugins called from linuxdeploy are called like binaries)
chmod +x linuxdeploy-x86_64.AppImage linuxdeploy-plugin-gtk.sh

# Create the AppImage directory
./linuxdeploy-x86_64.AppImage --appdir=AppDir

# Copy the application binary to the AppDir
cp ../output/bin/etichetta AppDir/usr/bin/

# Run the build
DEPLOY_GTK_VERSION=3 ./linuxdeploy-x86_64.AppImage --plugin gtk -i ../res/etichetta.svg -d ../res/etichetta.desktop  --library=/usr/lib/x86_64-linux-gnu/libphobos2.so --appdir=AppDir --output appimage