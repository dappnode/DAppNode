FROM docker:dind

# Install required packages
RUN apk update && \
    apk add --no-cache xorriso git xz curl ca-certificates iptables cpio bash perl-utils && \
    # Add user to the existing docker group
    adduser -S docker-user && \
    addgroup docker-user docker

WORKDIR /usr/src/app
COPY . .

USER docker-user  # Ensure the container runs as a non-root user

CMD ["/usr/src/app/iso/scripts/generate_ISO.sh"]
