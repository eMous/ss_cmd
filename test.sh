#!/bin/bash
  echo "--------------Installing libsodium--------------" | tee -a ss_install.log
  if [[ false ]] ; then
    # Installation of libsodium
    export LIBSODIUM_VER=1.0.16
    wget https://download.libsodium.org/libsodium/releases/libsodium-$LIBSODIUM_VER.tar.gz 2>&1 | tee -a ss_install
    tar xvf libsodium-$LIBSODIUM_VER.tar.gz
    pushd libsodium-$LIBSODIUM_VER
    ./configure --prefix=/usr && make
    sudo make install
    popd
    sudo ldconfig
  fi 2>&1 >>ss_install.log | tee -a ss_install.log 
  echo "--------------Libsodium Installed--------------" | tee -a ss_install.log
