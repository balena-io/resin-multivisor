#!/bin/bash

set -e

[ -d /dev/net ] ||
    mkdir -p /dev/net
[ -c /dev/net/tun ] ||
    mknod /dev/net/tun c 10 200

mkdir -p /data/vpn
mkdir -p /var/run/openvpn
mkdir -p /data/docker
ln -s /data/docker /var/lib/docker

cd /usr/src/multivisor

rm /var/run/docker.pid || true

/bin/sh $(which dind) docker -d --storage-driver=vfs -g /var/lib/docker &

(( timeout = 60 + SECONDS ))
until [ -S /var/run/docker.sock ]; do
	if (( SECONDS >= timeout )); then
		echo "Timeout while trying to connect to docker"
		exit 1
	fi
	sleep 1
done

# Move preloaded apps
if [[ "$MULTIVISOR_PRELOADED_APPS" -eq "1" ]] && [ -d /usr/src/multivisor/preloaded-images ]; then
	docker load < /usr/src/multivisor/preloaded-images/*.tar
	rm -rf /usr/src/multivisor/preloaded-images
	rm -rf /var/lib/dind-docker
fi

DATA_DIRECTORY=/data

mkdir -p /var/log/supervisor && touch /var/log/supervisor/supervisord.log
mkdir -p /var/run/resin
mount -t tmpfs -o size=1m tmpfs /var/run/resin

/usr/bin/supervisord -c /etc/supervisor/supervisord.conf

supervisorctl -c /etc/supervisor/supervisord.conf start resin-supervisor

tail -f /var/log/supervisor/supervisord.log &

while [ ! -f /var/log/resin_supervisor_stdout.log ]; do
	sleep 1
done
tail -fn 1000 /var/log/resin_supervisor_stdout.log &

if [ -n "$1" ]; then
	CMD=$(which $1)
	shift
	$CMD $@
fi

while true; do
	echo "Container still running"
	sleep 120
done
