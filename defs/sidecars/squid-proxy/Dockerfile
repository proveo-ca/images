FROM ubuntu/squid:latest

# Use a non-root user if possible (ubuntu/squid runs as proxy by default)
# Add custom squid.conf for policy enforcement
COPY squid.conf /etc/squid/squid.conf
COPY firehol-blocked-nets.conf /etc/squid/firehol-blocked-nets.conf
COPY firehol-ipset.conf /etc/squid/firehol-ipset.conf
COPY update-firehol-ipsets.sh /usr/local/bin/update-firehol-ipsets
RUN chmod +x /usr/local/bin/update-firehol-ipsets

# Expose standard Squid port
EXPOSE 3128

# Default command runs squid in foreground
CMD ["squid", "-f", "/etc/squid/squid.conf", "-NYC"]
