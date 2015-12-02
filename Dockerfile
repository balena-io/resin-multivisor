FROM docker:1.6.2-dind

RUN apk add --update \
	bash \
	binutils \
	ca-certificates \
	e2fsprogs \
	g++ \
	iptables \
	make \
	nodejs \
	openvpn \
	socat \
	sqlite-dev \
	supervisor \
	&& rm -rf /var/cache/apk/*

# Copy supervisord configuration files
COPY config/supervisor/ /etc/supervisor/
COPY config/openvpn/ /etc/openvpn/

COPY package.json postinstall.sh /usr/src/multivisor/
RUN cd /usr/src/multivisor \
	&& JOBS=MAX npm install --unsafe-perm --production --no-optional \
	&& cd /usr/src/multivisor/node_modules/sqlite3 && ./node_modules/.bin/node-pre-gyp install --build-from-source --sqlite=/usr/lib \
	&& npm dedupe \
	&& npm cache clean \
	&& rm -rf /tmp/*

# Copy source
COPY . /usr/src/multivisor/
RUN chmod +x /usr/src/multivisor/entry.sh \
	&& chmod +x /usr/src/multivisor/preload.sh \
	&& ln -s /usr/src/multivisor/preload.sh /bin/preload-multivisor

RUN /usr/src/multivisor/node_modules/.bin/coffee -c /usr/src/multivisor/src

ENTRYPOINT ["/usr/src/multivisor/entry.sh"]
