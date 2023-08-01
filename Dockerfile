ARG NGINX_VERSION=1.24.0
ARG NGINX_RTMP_VERSION=1.2.11
ARG FFMPEG_VERSION=5.1

##############################
# Build the NGINX-build image.
FROM alpine:3.18 as build-nginx
ARG NGINX_VERSION
ARG NGINX_RTMP_VERSION
ARG MAKEFLAGS="-j4"

# Build dependencies.
RUN apk add --no-cache \
  build-base \
  ca-certificates \
  curl \
  gcc \
  libc-dev \
  libgcc \
  linux-headers \
  make \
  musl-dev \
  openssl \
  openssl-dev \
  pcre \
  pcre-dev \
  pkgconf \
  pkgconfig \
  zlib-dev

WORKDIR /tmp

# Get nginx source.
RUN wget https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz && \
  tar zxf nginx-${NGINX_VERSION}.tar.gz && \
  rm nginx-${NGINX_VERSION}.tar.gz

# Get nginx-http-flv module.
RUN wget https://github.com/winshining/nginx-http-flv-module/archive/v${NGINX_RTMP_VERSION}.tar.gz && \
  tar zxf v${NGINX_RTMP_VERSION}.tar.gz && \
  rm v${NGINX_RTMP_VERSION}.tar.gz

# Compile nginx with nginx-rtmp module.
WORKDIR /tmp/nginx-${NGINX_VERSION}
RUN \
  ./configure \
  --prefix=/usr/local/nginx \
  --add-module=/tmp/nginx-http-flv-module-${NGINX_RTMP_VERSION} \
  --conf-path=/etc/nginx/nginx.conf \
  --with-threads \
  --with-file-aio \
  --with-http_ssl_module \
  --with-debug \
  --with-http_stub_status_module \
  --with-cc-opt="-Wimplicit-fallthrough=0" && \
  make && \
  make install

###############################
# Build the FFmpeg-build image.
#FROM alpine:3.18 as build-ffmpeg
#ARG FFMPEG_VERSION
#ARG PREFIX=/usr/local
#ARG MAKEFLAGS="-j4"
#
## FFmpeg build dependencies.
#RUN apk add --no-cache \
#  build-base \
#  coreutils \
#  freetype-dev \
#  lame-dev \
#  libogg-dev \
#  libass \
#  libass-dev \
#  libvpx-dev \
#  libvorbis-dev \
#  libwebp-dev \
#  libtheora-dev \
#  openssl-dev \
#  opus-dev \
#  pkgconf \
#  pkgconfig \
#  rtmpdump-dev \
#  wget \
#  x264-dev \
#  x265-dev \
#  yasm
#
#RUN echo http://dl-cdn.alpinelinux.org/alpine/edge/community >> /etc/apk/repositories
#RUN apk add --no-cache fdk-aac-dev
#
#WORKDIR /tmp

# Get FFmpeg source.
#RUN wget http://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.gz && \
#  tar zxf ffmpeg-${FFMPEG_VERSION}.tar.gz && \
#  rm ffmpeg-${FFMPEG_VERSION}.tar.gz
#
## Compile ffmpeg.
#WORKDIR /tmp/ffmpeg-${FFMPEG_VERSION}
#RUN \
#  ./configure \
#  --prefix=${PREFIX} \
#  --enable-version3 \
#  --enable-gpl \
#  --enable-nonfree \
#  --enable-small \
#  --enable-libmp3lame \
#  --enable-libx264 \
#  --enable-libx265 \
#  --enable-libvpx \
#  --enable-libtheora \
#  --enable-libvorbis \
#  --enable-libopus \
#  --enable-libfdk-aac \
#  --enable-libass \
#  --enable-libwebp \
#  --enable-postproc \
#  --enable-libfreetype \
#  --enable-openssl \
#  --disable-debug \
#  --disable-doc \
#  --disable-ffplay \
#  --extra-libs="-lpthread -lm" && \
#  make && \
#  make install && \
#  make distclean
#
## Cleanup.
#RUN rm -rf /var/cache/* /tmp/*

##########################
# Build the release image.

FROM alpine:3.18
LABEL MAINTAINER=starmetal<info@starmetal.com.cn>

# Set default ports.
ENV HTTP_PORT 80
ENV HTTPS_PORT 443
ENV RTMP_PORT 1935

ARG TARGETARCH
RUN echo $TARGETARCH && wget https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-${TARGETARCH}-static.tar.xz && \
    tar xvf ffmpeg-release-${TARGETARCH}-static.tar.xz && cp ffmpeg*/ff* /usr/local/bin/
    
RUN apk add --no-cache \
  ca-certificates \
  gettext \
  openssl openssl-dev\
  pcre \
  lame \
  libogg \
  curl \
  libass \
  libvpx \
  libvorbis \
  libwebp \
  libtheora \
  opus \
  rtmpdump \
  x264-dev \
  x265-dev \
   fdk-aac-dev

COPY --from=build-nginx /usr/local/nginx /usr/local/nginx
COPY --from=build-nginx /etc/nginx /etc/nginx
COPY --from=build-nginx /usr/lib/libfdk* /usr/lib
COPY --from=build-nginx /usr/local/bin/ff* /usr/local/bin/
#COPY --from=build-nginx /usr/local/bin/ffmpeg /usr/local/bin/
#COPY --from=build-ffmpeg /usr/local /usr/local
#COPY --from=build-ffmpeg /usr/lib/libfdk-aac.so.2 /usr/lib/libfdk-aac.so.2

# Add NGINX path, config and static files.
ENV PATH "${PATH}:/usr/local/nginx/sbin"
COPY nginx.conf /etc/nginx/nginx.conf.template
RUN mkdir -p /opt/data && mkdir /www
COPY static /www/static

EXPOSE 1935
EXPOSE 80
EXPOSE 443

CMD envsubst "$(env | sed -e 's/=.*//' -e 's/^/\$/g')" < \
  /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf && \
  nginx
