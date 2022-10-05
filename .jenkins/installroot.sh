#!/bin/bash


# Setup environment
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
ARCHIVE_NAME=$("$SCRIPT_DIR/s3/getbuildname.sh")



# Print debugging info, enable tracing
set -o xtrace
env
date
pwd



# If incremental build, download and unpack previous build artifacts from S3
if [ "$INCREMENTAL" = true ]; then
    "$SCRIPT_DIR/s3/download.sh" "$ARCHIVE_NAME"

    # if first few bytes of file is 'NoSuchKey', skip incremental build
    failmsg='NoSuchKey'
    failmsglen=$(echo "$failmsg" | wc -c)
    if [ "$(head -c $failmsglen "$ARCHIVE_NAME")" = $failmsg ]; then
        INCREMENTAL=false
    else
        if ! tar -xvf "$ARCHIVE_NAME" -C /; then
            INCREMENTAL=false
        fi
    fi
fi

mkdir -p /tmp/root/build
mkdir -p /tmp/root/install


# Clone, generate and build
for retry in {1..5}; do
    git clone -b "$BRANCH" \
              --single-branch \
              --depth 1 \
              https://github.com/root-project/root.git /tmp/root/src \
    && ERR=false && break
done

cd /tmp/root/build || exit 1

#if [ "$INCREMENTAL" = false ]; then
cmake -DCMAKE_INSTALL_PREFIX=/tmp/root/install /tmp/root/src/ || exit 1 # $OPTIONS
#fi

cmake --build /tmp/root/build --target install -- -j$(nproc) || exit 1



# Archive and upload build artifacts to S3
rm -f "$ARCHIVE_NAME" || true
tar -Pczf "$ARCHIVE_NAME" /tmp/root/build/ /tmp/root/install/
"$SCRIPT_DIR/s3/upload.sh" "$ARCHIVE_NAME"
