FROM docker:dind

# Install required packages
RUN apk update && \
    apk add --no-cache xorriso git xz curl ca-certificates iptables cpio bash perl-utils 

WORKDIR /usr/src/app
COPY . .

CMD ["/usr/src/app/iso/scripts/generate_ISO.sh"]
