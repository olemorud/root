#!/bin/bash

# Usage: ./getbuildname.sh <config> <cmake options>

optionsum=$(printf '%s' "$1" | shasum | cut -d ' ' -f 1)
timestamp=$(date +%F)


echo "$PLATFORM/$BRANCH/$CONFIG/$optionsum-$timestamp.tar.gz"
