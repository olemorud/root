#!/usr/bin/env bash

# shellcheck source=s3/utils.sh
# shellcheck source=s3/auth.sh

stubCMake=false

this=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
s3token=$("$this/s3/auth.sh")
cmakeOptionsHash=$(printf '%s' "$OPTIONS" | shasum | cut -d ' ' -f 1)
archiveNamePrefix="$PLATFORM/$BRANCH/$CONFIG/$cmakeOptionsHash/"
uploadName="$archiveNamePrefix$(date +%F).tar.gz"

mkdir -p /tmp/workspace/
cd /tmp/workspace/       || exit 1
rm -rf /tmp/workspace/*

# utils.sh defines downloadArchive(), getArchiveNamePrefix(), searchArchive(), 
# uploadArchive()
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
    cd /tmp/workspace || exit 1
        local downloadName
        downloadName=$(searchArchive "$s3token" "$archiveNamePrefix" |tail -n 1)
        downloadArchive "$s3token" "$downloadName"
        tar -xf "$downloadName"  || return 1
        # ^^ tar will fail if any previous step fails

        ls -la ./src || return 1
        # if the tar file doesn't contain required files this command fails
    cd - || exit 1

    cd /tmp/workspace/src || exit 1
        git fetch

        # shellcheck disable=SC1083
        if [ "$(git rev-parse HEAD)" = "$(git rev-parse @{u})" ]; then
            echo "Files are unchanged since last build, exiting"
            exit 0
        fi

        git merge FETCH_HEAD || return 1
    cd - || exit 1
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
        cmake -S /tmp/workspace/src \
              -B /tmp/workspace/build \
              -DCMAKE_INSTALL_PREFIX=/tmp/workspace/install $OPTIONS || exit 1
    fi

    cmake --build /tmp/workspace/build \
          --target install \
          -- -j"$(getconf _NPROCESSORS_ONLN)" || exit 1
else
    # Stubbing CMake lets you test changes to the script without
    # waiting 30 minutes for CMake to build ROOT
    echo "Stubbing CMake step"
    echo "build file"   > /tmp/workspace/build/buildfile.txt
    echo "install file" > /tmp/workspace/install/installfile.txt
fi


# archive and upload
cd /tmp/workspace/ || exit $?
    mkdir -p "$(dirname "$uploadName")"
    rm -f "$uploadName"
    tar -czf "$uploadName" build install src 

    # Even though CMake is completely dependent on absolute paths, I have to do
    # this relative path terribleness. There is no portable syntax with 
    # absolute paths
    uploadArchive "$s3token" "$uploadName"
cd - || exit $?