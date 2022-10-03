#!/usr/bin/zsh


source rc.sh

curl -v -s \
	-X POST "$OS_AUTH_URL/auth/tokens?nocatalog" \
	-H "Content-Type: application/json" \
	-d '{"auth": {"identity": {"methods": ["application_credential"],"application_credential": {"id": "'"$OS_APPLICATION_CREDENTIAL_ID"'","secret": "'"$OS_APPLICATION_CREDENTIAL_SECRET"'"}}}}' \
	2> /dev/stdout 1> /dev/null | grep X-Subject-Token: | cut -d" " -z -f3 | tr -d $'\r' # extract the token, cut sometimes adds a <CR> character which must be removed
