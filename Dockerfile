FROM gliderlabs/alpine

RUN apk-install \
	binutils \
	ca-certificates \
	docker \
	e2fsprogs \
	g++ \
	iptables \
	lxc \
	make \
	nodejs \
	socat \
	sqlite-dev \
	supervisor

# Copy supervisord configuration files
COPY config/supervisor/ /etc/supervisor/

# Install dependencies
WORKDIR /app
COPY package.json postinstall.sh /app/
RUN JOBS=MAX npm install --unsafe-perm --production --no-optional \
	&& npm dedupe \
	&& npm cache clean \
	&& rm -rf /tmp/*

# Copy source
COPY . /app/
RUN chmod +x /app/entry.sh \
	&& chmod +x /app/wrapdocker

RUN /app/node_modules/.bin/coffee -c /app/src

CMD ["/app/entry.sh"]
