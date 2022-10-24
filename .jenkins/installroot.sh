#!/bin/bash


stubCMake=false

# Setup environment
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
ARCHIVE_NAME=$("$SCRIPT_DIR/s3/getbuildname.sh")
ARCHIVE_DIR="$HOME/rootci"
doGenerate= ! $INCREMENTAL
mkdir -p $ARCHIVE_DIR


# Print debugging info, enable tracing
set -o xtrace
env | sort -i
date
pwd



# Erase files from previous builds and create subdir for build artifacts
rm -rf /tmp/root/*
mkdir -p "$(dirname "$ARCHIVE_NAME")"



# If incremental build, download and unpack previous build artifacts from S3
if [ "$INCREMENTAL" = true ]; then
    "$SCRIPT_DIR/s3/download.sh" "$ARCHIVE_NAME"

    if ! tar -xf "$ARCHIVE_NAME" -C /; then
        INCREMENTAL=false
    fi
fi

if [ "$INCREMENTAL" = false ]; then
    mkdir -p /tmp/root/build
    mkdir -p /tmp/root/install

    git clone -b "$BRANCH" \
                --single-branch \
                --depth 1 \
                https://github.com/root-project/root.git /tmp/root/src
else
    git --git-dir=/tmp/root/src fetch
    if [ "$(git rev-parse HEAD)" = "$(git rev-parse @{u})" ]; then
        echo "Files are unchanged since last build, exiting"
        exit 0
    else
        git --git-dir=/tmp/root/src pull || exit 1
        doGenerate=true
    fi
fi

if ! $stubCMake; then
    if $doGenerate; then
        cmake -S /tmp/root/src -B /tmp/root/build -DCMAKE_INSTALL_PREFIX=/tmp/root/install || exit 1 # $OPTIONS
    fi
    cmake --build /tmp/root/build --target install -- -j"$(getconf _NPROCESSORS_ONLN)" || exit 1
else
    echo "Stubbing CMake step, writing dummy files to /tmp/root/build and /tmp/root/src"
    echo "build file" > /tmp/root/build/buildfile.txt
    echo "install file" > /tmp/root/install/installfile.txt
fi


# Archive and upload build artifacts to S3
rm -f "$ARCHIVE_NAME"
tar -Pczf "$ARCHIVE_NAME" /tmp/root/build/ /tmp/root/install/ /tmp/root/src/
"$SCRIPT_DIR/s3/upload.sh" "$ARCHIVE_NAME"


