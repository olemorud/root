#!/bin/bash

# Usage: ./getbuildname.sh <config> <cmake options>

config=$1
optionsum=$(printf '%s' "$2" | cksum)
timestamp=$(date +%F)


echo "$PLATFORM/$BRANCH/$config/$optionsum-$timestamp.tar.gz"