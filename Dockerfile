FROM gliderlabs/alpine

RUN apk-install \
	binutils \
	ca-certificates \
	device-mapper \
	docker \
	e2fsprogs \
	g++ \
	iptables \
	lxc \
	make \
	nodejs \
	openvpn \
	socat \
	sqlite-dev \
	supervisor

# Copy supervisord configuration files
COPY config/supervisor/ /etc/supervisor/
COPY config/openvpn/ /etc/openvpn/

# Install dependencies
WORKDIR /app
COPY package.json postinstall.sh /app/
RUN JOBS=MAX npm install --unsafe-perm --production --no-optional \
	&& npm dedupe \
	&& npm cache clean \
	&& rm -rf /tmp/* \
	&& cd /app/node_modules/sqlite3 && ./node_modules/.bin/node-pre-gyp install --build-from-source --sqlite=/usr/lib

# Copy source
COPY . /app/
RUN chmod +x /app/entry.sh \
	&& chmod +x /app/wrapdocker

RUN /app/node_modules/.bin/coffee -c /app/src

CMD ["/app/entry.sh"]
