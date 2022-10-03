#!/bin/bash

# DEBUGGING
env
date

# BUILD

for retry in {1..5}; do
    git clone -b $BRANCH --single-branch --depth 1 https://github.com/root-project/root.git /tmp/src \
    && ERR=false && break
done

mkdir -p /tmp/build
cd /tmp/build

# For ROOT version 6.26.00 set `-Druntime_cxxmodules=OFF` (https://github.com/root-project/root/pull/10198)
cmake /tmp/src/ -DCMAKE_INSTALL_PREFIX=/usr $OPTIONS

cmake --build . --target install -- -j$(nproc)



# Upload build artifacts to S3
ARCHIVENAME="build-$IMAGE-$BRANCH-$(uname -m).tar.gz"

tar -czf "$ARCHIVENAME" /tmp/build/*
./uploadartifacts/upload.sh "$ARCHIVENAME"
