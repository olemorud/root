#!/bin/bash

# this prorgam prints s3 token to stdout

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

source $SCRIPT_DIR/rc.sh

# auth token is only printed in verbose output
curl --verbose \
	 --silent \
	 -X POST "$OS_AUTH_URL/auth/tokens?nocatalog" \
	 -H "Content-Type: application/json" \
	 -d '{"auth": {"identity": {"methods": ["application_credential"],"application_credential": {"id": "'"$OS_APPLICATION_CREDENTIAL_ID"'","secret": "'"$OS_APPLICATION_CREDENTIAL_SECRET"'"}}}}' \
	2> /dev/stdout | grep X-Subject-Token: | cut -d" " -z -f3 | tr -d "\r\n\0 "

