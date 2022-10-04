#!/bin/bash


# Print debugging info
env
date


SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
ARCHIVE_NAME=$($SCRIPT_DIR/s3/getbuildname.sh)


# Download and unpack previous build artifacts from S3
$SCRIPT_DIR/s3/download.sh $ARCHIVE_NAME

mkdir -p /tmp/build
if [ -f $ARCHIVE_NAME ]; then
    tar -xvf $ARCHIVE_NAME
fi


# Clone, setup and build
for retry in {1..5}; do
    git clone -b $BRANCH \
              --single-branch \
              --depth 1 \
              https://github.com/root-project/root.git /tmp/src \
    && ERR=false && break
done

cd /tmp/build

# for ROOT version 6.26.00 set `-Druntime_cxxmodules=OFF` (https://github.com/root-project/root/pull/10198)
cmake /tmp/src/ -DCMAKE_INSTALL_PREFIX=/usr $OPTIONS

cmake --build . --target install -- -j$(nproc)



# Upload build artifacts to S3
tar -czf "$ARCHIVE_NAME" /tmp/build/*
$SCRIPT_DIR/s3/upload.sh "$ARCHIVE_NAME"
