#!/bin/bash


SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
ARCHIVE_NAME=$("$SCRIPT_DIR/s3/getbuildname.sh")

# Print debugging info, enable tracing
set -o xtrace
env
date
pwd


# Download and unpack previous build artifacts from S3
"$SCRIPT_DIR/s3/download.sh" "$ARCHIVE_NAME"

mkdir -p /tmp/build
tar -xvf "$ARCHIVE_NAME" -C / && INCREMENTAL=false
echo "INCREMENTAL=$INCREMENTAL"


# Clone, setup and build
for retry in {1..5}; do
    git clone -b "$BRANCH" \
              --single-branch \
              --depth 1 \
              https://github.com/root-project/root.git /tmp/src \
    && ERR=false && break
done

cd /tmp/build || exit 1

# for ROOT version 6.26.00 set `-Druntime_cxxmodules=OFF` (https://github.com/root-project/root/pull/10198)
if [ "$INCREMENTAL" = false ]; then
	cmake /tmp/src/ -DCMAKE_INSTALL_PREFIX=/usr $OPTIONS
fi

cmake --build . --target install -- -j$(nproc)



# Archive and upload build artifacts to S3
tar -Pczf "$ARCHIVE_NAME" /tmp/build/*
"$SCRIPT_DIR/s3/upload.sh" "$ARCHIVE_NAME"
