# Agentgateway on Railway: the official upstream image, pinned by version and digest,
# plus a static BusyBox so a small start script can write the config from Railway variables.
FROM busybox:1.37.0-musl@sha256:f6a95d611e0a8780fabdb2aec43e31275b2720dfefa3e41b16835bfc42454478 AS busybox

FROM ghcr.io/agentgateway/agentgateway:v1.7.0@sha256:60216aafb03d37f94e952ff3d51d2f630a65b10ecaebdc0a864882f92610c45b

# The start script runs as root only to own the Railway volume, then drops to UID 65532 (upstream's user).
USER root
COPY --from=busybox /bin/busybox /usr/local/bin/busybox
RUN ["/usr/local/bin/busybox", "mkdir", "-p", "/usr/local/bb"]
RUN ["/usr/local/bin/busybox", "--install", "-s", "/usr/local/bb"]
COPY start.sh /app/start.sh

ENV PATH=/usr/local/bb:/usr/local/sbin:/usr/local/bin:/usr/bin:/usr/sbin:/sbin:/bin
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/busybox", "sh", "/app/start.sh"]
