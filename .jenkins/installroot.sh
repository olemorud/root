#!/usr/bin/env bash

# shellcheck source=s3/utils.sh
# shellcheck source=s3/auth.sh

stubCMake=false # Skips generation and build when set to true

this=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# ======Load build options from files ======================
declare -A config

# Load global options from file
while IFS='=' read -r key value; do
	if [ ! -z "$key" ] && [ ! -z "$value" ]; then
		config[$key]=$value
	fi
done < "$this/buildconfig/global.txt"

# Overwrite with platform-specific options from file
while IFS='=' read -r key value; do
	if [ ! -z "$key" ] && [ ! -z "$value" ]; then
		config[$key]=$value
	fi
done < "$this/buildconfig/$PLATFORM.txt"

# Use dictionary to populate cmake options
buildOptions=""
for key in "${!config[@]}"; do
    buildOptions+="-D$key=${config[$key]} "
done

# Sort options to make hashing consistent, generate hash of options
buildOptions=$(echo "$buildOptions" | tr " " "\n" | sort -i | tr "\n" " ")
buildOptionsHash=$(printf '%s' "$buildOptions" | shasum | cut -d ' ' -f 1)



# ======== Set s3 related variables and functions ==========
s3token=$("$this/s3/auth.sh")
archiveNamePrefix="$PLATFORM/$BRANCH/$CONFIG/$buildOptionsHash/"
uploadName="$archiveNamePrefix$(date +%F).tar.gz"
# utils.sh defines downloadArchive(), getArchiveNamePrefix(), searchArchive(), 
# uploadArchive()
source "$this/s3/utils.sh"



# ======== Download+pull or clone, generate and install ====
mkdir -p /tmp/workspace/
cd /tmp/workspace/       || exit 1
rm -rf /tmp/workspace/*

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
    local downloadName
    downloadName=$(searchArchive "$s3token" "$archiveNamePrefix" |tail -n 1)
    downloadArchive "$s3token" "$downloadName"
    tar -xf "$downloadName"  || return 1
    # ^^ tar will fail if any previous step fails

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
              -DCMAKE_INSTALL_PREFIX=/tmp/workspace/install $buildOptions || exit 1
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



# ======== Upload build artifacts to s3 ====================
cd /tmp/workspace/ || exit $?
    mkdir -p "$(dirname "$uploadName")"
    rm -f "$uploadName"
    tar -czf "$uploadName" build install src 

    # Even though CMake is completely dependent on absolute paths, I have to do
    # this relative path terribleness. There is no portable syntax with 
    # absolute paths
    uploadArchive "$s3token" "$uploadName"
cd - || exit $?
