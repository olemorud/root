#!/bin/bash


# Setup environment
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
ARCHIVE_NAME=$("$SCRIPT_DIR/s3/getbuildname.sh")
ARCHIVE_DIR="$HOME/rootci"
mkdir -p $ARCHIVE_DIR


# Print debugging info, enable tracing
set -o xtrace
env
date
pwd



# If incremental build, download and unpack previous build artifacts from S3
if [ "$INCREMENTAL" = true ]; then
    cd $ARCHIVE_DIR || exit 1
    "$SCRIPT_DIR/s3/download.sh" "$ARCHIVE_NAME"

    if ! tar -xf "$ARCHIVE_NAME" -C /; then
        INCREMENTAL=false
    fi
fi

if [ "$INCREMENTAL" = false ]; then
    # Make needed dirs only if last step didn't run / failed
    # (we don't want to update timestamps)
    mkdir -p /tmp/root/build
    mkdir -p /tmp/root/install
    rm -rf /tmp/root/src

    git clone -b "$BRANCH" \
                --single-branch \
                --depth 1 \
                https://github.com/root-project/root.git /tmp/root/src
else
    cd /tmp/root/src    || exit 1
    git fetch
    if [ "$(git rev-parse HEAD)" = "$(git rev-parse @{u})" ]; then
        echo "Files are unchanged since last build, exiting"
        exit 0
    else
        git pull || exit 1
    fi
fi

cd /tmp/root/build || exit 1

$INCREMENTAL || cmake -DCMAKE_INSTALL_PREFIX=/tmp/root/install /tmp/root/src/  || exit 1 # $OPTIONS
cmake --build /tmp/root/build --target install -- -j"$(nproc)" || exit 1



# Print script for reproducing
echo "$(cat ${BASH_SOURCE[0]})"


# Archive and upload build artifacts to S3
cd $ARCHIVE_DIR || exit 1
rm -f "$ARCHIVE_NAME"
tar -Pczf "$ARCHIVE_NAME" /tmp/root/build/ /tmp/root/install/ /tmp/root/src/
"$SCRIPT_DIR/s3/upload.sh" "$ARCHIVE_NAME"


