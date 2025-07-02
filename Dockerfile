FROM docker:dind
RUN apk update && \
    apk add --no-cache xorriso git xz curl ca-certificates iptables cpio bash perl-utils && \
    addgroup -S docker && \
    adduser -S docker-user -G docker

WORKDIR /usr/src/app
COPY . .

USER docker-user  # Ensure the container runs as a non-root user

CMD ["/usr/src/app/iso/scripts/generate_ISO.sh"]
