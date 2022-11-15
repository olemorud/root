#!/usr/bin/env bash

# shellcheck source=s3/utils.sh
# shellcheck source=s3/auth.sh

stubCMake=false

this=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
s3token=$("$this/s3/auth.sh")
cmakeOptionsHash=$(printf '%s' "$OPTIONS" | shasum | cut -d ' ' -f 1)
archiveNamePrefix="$PLATFORM/$BRANCH/$CONFIG/$cmakeOptionsHash/"
uploadName="$archiveNamePrefix$(date +%F).tar.gz"

mkdir /tmp/workspace/
cd /tmp/workspace/
rm -rf /tmp/workspace/*

# utils.sh defines downloadArchive(), getArchiveNamePrefix(), searchArchive(), uploadArchive()
source "$this/s3/utils.sh"

cloneFromGit() {
    INCREMENTAL=false

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
    cd /tmp/workspace
        local downloadName=$(searchArchive "$s3token" "$archiveNamePrefix" | tail -n 1)
        downloadArchive "$s3token" "$downloadName"
        tar -xf "$downloadName"  || return 1
        # ^^ tar will fail if any previous step fails
        ls -la ./src
    cd -

    cd /tmp/workspace/src
        git fetch

        # shellcheck disable=SC1083
        if [ "$(git -C /tmp/workspace/src rev-parse HEAD)" = "$(git -C /tmp/workspace/src rev-parse @{u})" ]; then
            echo "Files are unchanged since last build, exiting"
            cd -
            exit 0
        fi

        git merge FETCH_HEAD || return 1
    cd -
}


# debugging
set -o xtrace
env | sort -i
date
pwd


# fetch files
if $INCREMENTAL; then
    downloadAndGitPull || cloneFromGit || exit 0
else
    cloneFromGit || exit 0
fi


# generate+build
if ! $stubCMake; then
    if ! $INCREMENTAL; then
        cmake -S /tmp/workspace/src -B /tmp/workspace/build -DCMAKE_INSTALL_PREFIX=/tmp/workspace/install $OPTIONS || exit 1
    fi
    cmake --build /tmp/workspace/build --target install -- -j"$(getconf _NPROCESSORS_ONLN)" || exit 1
else
    echo "Stubbing CMake step, writing dummy files to /tmp/workspace/build and /tmp/workspace/src"
    echo "build file" > /tmp/workspace/build/buildfile.txt
    echo "install file" > /tmp/workspace/install/installfile.txt
fi


# archive and upload
cd /tmp/workspace/
    mkdir -p $(dirname "$uploadName")
    rm -f "$uploadName"
    tar -czf "$uploadName" build install src
    uploadArchive "$s3token" "$uploadName"
cd -