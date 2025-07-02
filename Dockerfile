FROM docker:dind

# Install required packages
RUN apk update && \
    apk add --no-cache xorriso git xz curl ca-certificates iptables cpio bash perl-utils && \
    # Create user 'docker-user' and add it to the 'docker' group
    adduser -S -D -H docker-user && \
    addgroup docker-user docker

WORKDIR /usr/src/app
COPY . .

# Switch to 'docker-user' to run as a non-root user
USER docker-user

CMD ["/usr/src/app/iso/scripts/generate_ISO.sh"]
