#!/bin/bash

# This program prints s3 token to stdout.
# It is dependent on OpenStack application credentials saved as rc.sh.

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

source "$SCRIPT_DIR/rc.sh"

read -r -d '' REQUEST << EOF
	{
		"auth": {
			"identity": {
				"methods": ["application_credential"],
				"application_credential": {
					"id": "$OS_APPLICATION_CREDENTIAL_ID",
					"secret": "$OS_APPLICATION_CREDENTIAL_SECRET"
				}
			}
		}
	}
EOF

# auth token is only printed in verbose output
curl --verbose \
	 --silent \
	 -X POST "$OS_AUTH_URL/auth/tokens?nocatalog" \
	 -H "Content-Type: application/json" \
	 -d "$REQUEST" \
2>/dev/stdout | grep X-Subject-Token: | cut -d" " -f3 | tr -d "\r\n\0 "

