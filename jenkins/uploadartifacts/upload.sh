#!/bin/zsh

# author: Ole Morud, ole.kristian.morud@cern.ch

if test $# -eq 0; then
  echo "Usage: $0 <file>"
  exit 1
fi

FILE=$1
URL=https://s3.cern.ch/swift/v1/ROOT-build-artifacts
TOKEN=$(./get-token.sh)

echo "curl -i \"$URL/$FILE\" -X PUT -T \"$FILE\" -H \"X-Auth-Token: $TOKEN\""

curl \
	-i "$URL/$FILE" \
	-X PUT \
	-T "$FILE" \
	-H "X-Auth-Token: $TOKEN"

