#!/bin/bash

if test $# -eq 0; then
  echo "Usage: $0 <file>"
  exit 1
fi

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
FILENAME=$1
URL=https://s3.cern.ch/swift/v1/ROOT-build-artifacts
TOKEN=$("$SCRIPT_DIR/auth.sh")

echo "curl -i \"$URL/$FILENAME\" -X GET -H \"X-Auth-Token: $TOKEN\""

curl \
	"$URL/$FILENAME" \
	-X GET \
	-H "X-Auth-Token: $TOKEN" \
	--output "$FILENAME"
