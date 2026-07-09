# Headless mitmproxy inspector for agent egress.
# Replaces the Charles inspector: free (Apache-2.0), headless-native, and able
# to decrypt HTTPS (method/path/body), which the previous Charles wiring could
# not. Used as the first-hop inspection proxy in `firewall` egress
# mode, forwarding all traffic to Squid as its enforcement upstream.

# Bump to the latest published mitmproxy/mitmproxy tag when upgrading.
ARG MITMPROXY_VERSION=11.1.3
FROM mitmproxy/mitmproxy:${MITMPROXY_VERSION}

ARG MITMPROXY_VERSION

# Run as root so bind-mounted confdir/flows directories are writable regardless
# of host UID. This is a local sidecar, not a published service.
USER root

COPY addons/ndjson_dump.py /addons/ndjson_dump.py
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

VOLUME ["/flows", "/mitmproxy-confdir"]
EXPOSE 8888

LABEL mitmproxy.version="${MITMPROXY_VERSION}"

ENTRYPOINT ["/entrypoint.sh"]
