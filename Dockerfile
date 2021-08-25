FROM docker:dind
# hadolint ignore=DL3018
RUN apk update && \
    apk add --no-cache xorriso git xz curl ca-certificates iptables cpio bash perl-utils \
    docker-compose && \
    rm -rf /var/cache/apk/* 

#RUN apk add -U --repository http://dl-cdn.alpinelinux.org/alpine/edge/testing aufs-util

RUN addgroup -g 2999 docker

# Create app directory
WORKDIR /usr/src/app
COPY . .

CMD ["/usr/src/app/iso/scripts/generate_ISO.sh"] 