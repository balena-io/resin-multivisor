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

# Move preloaded apps
if [[ "$MULTIVISOR_PRELOADED_APPS" -eq "1" ]] && [ -d /var/lib/dind-docker ]; then
	cp -R /var/lib/dind-docker /var/lib/docker
	rm -rf /var/lib/dind-docker
fi

/bin/sh $(which dind) docker -d --storage-driver=vfs -g /var/lib/docker &

(( timeout = 60 + SECONDS ))
until [ -S /var/run/docker.sock ]; do
	if (( SECONDS >= timeout )); then
		echo "Timeout while trying to connect to docker"
		rm -rf /var/lib/dind-docker
		exit 1
	fi
	sleep 1
done

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

if [[ "$@" -ne "" ]]; then
	CMD=$(which $1)
	shift
	$CMD $@
fi

while true; do
	echo "Container still running"
	sleep 120
done
