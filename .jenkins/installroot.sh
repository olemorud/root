#!/usr/bin/env bash

# shellcheck source=s3/utils.sh
# shellcheck source=s3/auth.sh

stubCMake=true

this=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
s3token=$("$this/s3/auth.sh")
doGenerate=! $INCREMENTAL

optionsum=$(printf '%s' "$OPTIONS" | shasum | cut -d ' ' -f 1)
archiveNamePrefix="$PLATFORM/$BRANCH/$CONFIG/$optionsum/"
uploadName="$archiveNamePrefix$(date +%F).tar.gz"


# utils.sh defines downloadArchive(), getArchiveNamePrefix(), searchArchive(), uploadArchive()
source "$this/s3/utils.sh"


# Print debugging info, enable tracing
set -o xtrace
env | sort -i
date
pwd


# Check for previous build artifacts
downloadName=$(searchArchive "$s3token" "$archiveNamePrefix" | head -n 1)
if [ -z "$downloadName" ]; then
    INCREMENTAL=false
fi


cloneFromGit() {
    mkdir -p /tmp/workspace/build
    mkdir -p /tmp/workspace/install

    git clone -b "$BRANCH" \
                    --single-branch \
                    --depth 1 \
                    https://github.com/root-project/root.git \
                    /tmp/workspace/src
    
    return $?
}


downloadAndGitPull() {
    downloadArchive "$s3token" "$downloadName"
    tar -xf "$archiveNamePrefix" -C / || return 1
    # ^^ tar will fail if any previous step fails

    git --git-dir=/tmp/workspace/src fetch

    # shellcheck disable=SC1083
    if [ "$(git rev-parse HEAD)" = "$(git rev-parse @{u})" ]; then
        echo "Files are unchanged since last build, exiting"
        exit 0
    else
        git --git-dir=/tmp/workspace/src pull || return 1
        doGenerate=true
    fi
}


# If incremental build, download and unpack previous build artifacts from S3
rm -rf /tmp/workspace/*
if $INCREMENTAL; then
    downloadAndGitPull || cloneFromGit
else
    cloneFromGit
fi


# Generate if needed and install
if ! $stubCMake; then
    if $doGenerate; then
        cmake -S /tmp/workspace/src -B /tmp/workspace/build -DCMAKE_INSTALL_PREFIX=/tmp/workspace/install || exit 1 # $OPTIONS
    fi
    cmake --build /tmp/workspace/build --target install -- -j"$(getconf _NPROCESSORS_ONLN)" || exit 1
else
    echo "Stubbing CMake step, writing dummy files to /tmp/workspace/build and /tmp/workspace/src"
    echo "build file" > /tmp/workspace/build/buildfile.txt
    echo "install file" > /tmp/workspace/install/installfile.txt
fi


# Archive and upload build artifacts to S3
mkdir -p $(dirname "$uploadName")
rm -f "$uploadName"
tar -Pczf "$uploadName" /tmp/workspace/build/ /tmp/workspace/install/ /tmp/workspace/src/
uploadArchive "$s3token" "$uploadName"


