#!/bin/bash

set -e

mkdir -p /var/lib/dind-docker
docker -d --iptables=false --bridge=none --storage-driver=vfs -g /var/lib/dind-docker &

(( timeout = 60 + SECONDS ))
until [ -S /var/run/docker.sock ]; do
	if (( SECONDS >= timeout )); then
		echo "Timeout while trying to connect to docker"
		rm -rf /var/lib/dind-docker
		exit 1
	fi
	sleep 1
done

if [[ "$MULTIVISOR_PRELOADED_APPS" -ne "1" ]]; then
	echo "MULTIVISOR_PRELOADED_APPS not set to 1, cannot preload"
fi

imageIds=$(echo $MULTIVISOR_PRELOADED_IMAGE_IDS | tr "," "\n")

mkdir -p /usr/src/multivisor/preloaded-images
i=0
for imageId in $imageIds; do
	docker pull $imageId
	docker save $imageId > /usr/src/multivisor/preloaded-images/$i.tar
	docker rmi -f $imageId
done
