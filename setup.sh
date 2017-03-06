#!/bin/bash
# sudo apt-get install build-essential libxmu-dev libxi-dev libgl-dev libosmesa-dev libglu-dev xorg-dev git cmake zip wget libsoil-dev libassimp-dev libgoogle-perftools-dev
# git clone https://github.com/nigels-com/glew.git glew
mkdir build_deps
pushd build_deps
wget https://downloads.sourceforge.net/project/glew/glew/2.0.0/glew-2.0.0.tgz
tar xzf glew-2.0.0.tgz
pushd glew-2.0.0
make all
sudo make install
popd
wget https://github.com/glfw/glfw/releases/download/3.2.1/glfw-3.2.1.zip
unzip glfw-3.2.1.zip
pushd glfw-3.2.1.zip
cmake .
make
sudo make install
popd
wget https://github.com/g-truc/glm/archive/0.9.8.4.tar.gz -O glm.tar.gz
tar xzf glm.tar.gz
pushd glm-0.9.8.4
cmake .
make
sudo make insall
popd
# just move headers from libfreetyp6-dev from /usr/include/freetype2/ to /usr/include
#wget http://download.savannah.gnu.org/releases/freetype/freetype-2.7.tar.gz
#tar xzf freetype-2.7.tar.gz
#pushd freetype-2.7
#mkdir build
#pushd build
# GET FONT AT http://www.dafont.com/digital-7.font
exit
