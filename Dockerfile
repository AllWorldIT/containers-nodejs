# Copyright (c) 2022-2025, AllWorldIT.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to
# deal in the Software without restriction, including without limitation the
# rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
# sell copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
# IN THE SOFTWARE.


FROM registry.conarx.tech/containers/alpine/edge AS nodejs-builder


# LTS - https://nodejs.org/en/about/previous-releases
ENV NODEJS_VER=22.13.1


# Copy build patches
#COPY patches build/patches


# Install libs we need
RUN set -eux; \
	true "Installing build dependencies"; \
# from https://git.alpinelinux.org/aports/tree/main/nodejs/APKBUILD
	apk add --no-cache \
		build-base \
		ca-certificates \
		ada-dev \
		base64-dev \
		brotli-dev \
		c-ares-dev \
		icu-dev \
		linux-headers \
		nghttp2-dev \
		nghttp3-dev \
		ngtcp2-dev \
		openssl-dev \
		py3-jinja2 \
		python3 \
		samurai \
		zlib-dev


# Download packages
RUN set -eux; \
	mkdir -p build; \
	cd build; \
	wget "https://nodejs.org/dist/v$NODEJS_VER/node-v$NODEJS_VER.tar.gz"; \
	tar -xf "node-v${NODEJS_VER}.tar.gz"


# Build and install NodeJS
RUN set -eux; \
	cd build; \
	cd "node-v${NODEJS_VER}"; \
# Patching
#	for i in ../patches/*.patch; do \
#		echo "Applying patch $i..."; \
#		patch -p1 < $i; \
#	done; \
	\
# Compiler flags
	export CFLAGS="-D_LARGEFILE_SOURCE -D_FILE_OFFSET_BITS=64"; \
	export CXXFLAGS="-D_LARGEFILE_SOURCE -D_FILE_OFFSET_BITS=64"; \
	export CPPFLAGS="-D_LARGEFILE_SOURCE -D_FILE_OFFSET_BITS=64"; \
	\
	pkgdir="/opt/nodejs-$NODEJS_VER"; \
	./configure \
		--prefix="$pkgdir" \
		--ninja \
		--shared-brotli \
		--shared-cares \
		--shared-nghttp2 \
		--shared-nghttp3 \
		--shared-ngtcp2 \
		--shared-openssl \
		--shared-zlib \
		--openssl-use-def-ca-store \
		--with-icu-default-data-dir=$(icu-config --icudatadir) \
		--with-intl=system-icu \
		"$@"; \
	\
# Build, must build without -j or it will fail
	nice -n 20 make -l 8 BUILDTYPE=Release; \
# Test
	./node -e 'console.log("Hello, world!")'; \
	./node -e "require('assert').equal(process.versions.node, '$NODEJS_VER')"; \
# Install
	make install; \
	\
# Remove cruft
	rm -rfv \
		"$pkgdir"/usr/share \
		"$pkgdir"/usr/lib/node_modules/npm/docs \
		"$pkgdir"/usr/lib/node_modules/npm/man


RUN set -eux; \
	cd "/opt/nodejs-$NODEJS_VER"; \
	scanelf --recursive --nobanner --osabi --etype "ET_DYN,ET_EXEC" .  | awk '{print $3}' | xargs \
		strip \
			--remove-section=.comment \
			--remove-section=.note \
			-R .gnu.lto_* -R .gnu.debuglto_* \
			-N __gnu_lto_slim -N __gnu_lto_v1 \
			--strip-unneeded; \
	du -hs .


FROM registry.conarx.tech/containers/alpine/edge

ARG VERSION_INFO=
LABEL org.opencontainers.image.authors		= "Nigel Kukard <nkukard@conarx.tech>"
LABEL org.opencontainers.image.version		= "edge"
LABEL org.opencontainers.image.base.name	= "registry.conarx.tech/containers/alpine/edge"

# LTS - https://nodejs.org/en/about/previous-releases
ENV NODEJS_VER=22.13.1

ENV FDC_DISABLE_SUPERVISORD=true
ENV FDC_QUIET=true

# Copy in built binaries
COPY --from=nodejs-builder /opt /opt/

# Install libs we need
RUN set -eux; \
	true "Installing build dependencies"; \
# from https://git.alpinelinux.org/aports/tree/main/nodejs/APKBUILD
	apk add --no-cache \
		ca-certificates \
		ada \
		base64 \
		brotli \
		c-ares \
		icu \
		nghttp2 \
		nghttp3 \
		ngtcp2 \
		openssl \
		py3-jinja2 \
		python3 \
		samurai \
		zlib

# Adjust flexible docker containers as this is not a daemon-based image
RUN set -eux; \
	ls -la /opt; \
	# Set up this language so it can be pulled into other images
	echo "# NodeJS $NODEJS_VER" > "/opt/nodejs-$NODEJS_VER/ld-musl-x86_64.path"; \
	echo "/opt/nodejs-$NODEJS_VER/lib" >> "/opt/nodejs-$NODEJS_VER/ld-musl-x86_64.path"; \
	echo "/opt/nodejs-$NODEJS_VER/bin" > "/opt/nodejs-$NODEJS_VER/PATH"; \
	# Set up library search path
	cat "/opt/nodejs-$NODEJS_VER/ld-musl-x86_64.path" >> /etc/ld-musl-x86_64.path; \
	# Remove things we dont need
	rm -f /usr/local/share/flexible-docker-containers/tests.d/40-crond.sh; \
	rm -f /usr/local/share/flexible-docker-containers/tests.d/90-healthcheck.sh

RUN set -eux; \
	true "Test"; \
# Test
	export PATH="$(cat /opt/nodejs-*/PATH):$PATH"; \
	node -e 'console.log("Hello, world!")'; \
	node -e "require('assert').equal(process.versions.node, '$NODEJS_VER')"; \
	du -hs /opt/nodejs-$NODEJS_VER

# NodeJS
COPY usr/local/share/flexible-docker-containers/init.d/41-nodejs.sh /usr/local/share/flexible-docker-containers/init.d
COPY usr/local/share/flexible-docker-containers/tests.d/41-nodejs.sh /usr/local/share/flexible-docker-containers/tests.d
RUN set -eux; \
	true "Flexible Docker Containers"; \
	if [ -n "$VERSION_INFO" ]; then echo "$VERSION_INFO" >> /.VERSION_INFO; fi; \
	true "Permissions"; \
	fdc set-perms
