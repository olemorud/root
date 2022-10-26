#!/usr/bin/env bash


# downloadArchive <token> <archivename>
downloadArchive() {
	if test $# -ne 2; then
		echo "Usage: $0 <file>" > /dev/stderr
		return 1
	fi

	local token=$1
	local filename=$2
	local url=https://s3.cern.ch/swift/v1/ROOT-build-artifacts

	# someone could maybe make a file called
	# a/../../../../bin/sh
	# to inject a virus but i havent tested this
	mkdir -p $(dirname "$filename")

	curl \
		"$url/$filename" \
		-X GET \
		-H "X-Auth-Token: $token" \
		--output "$filename"
}


# uploadArchive <token> <archivename>
uploadArchive(){
	if test $# -ne 2; then
		echo "Usage: $0 <file>" > /dev/stderr
		return 1
	fi

	local token=$1
	local filename=$2
	local url=https://s3.cern.ch/swift/v1/ROOT-build-artifacts

	curl \
		-i "$url/$filename" \
		-X PUT \
		-T "$filename" \
		-H "X-Auth-Token: $token"
}


# searchArchive <token> <file-prefix>
searchArchive(){
	if test $# -ne 2; then
		echo "Usage: $0 <token> <file-prefix>" > /dev/stderr
		return 1
	fi

	local token=$1
	local prefix=$2

	curl \
		"https://s3.cern.ch/swift/v1/ROOT-build-artifacts?prefix=$prefix" \
		-X GET \
		-H "X-Auth-Token: $token"
}
