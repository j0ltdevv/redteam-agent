FROM alpine:3.19

RUN apk add --no-cache tor proxychains-ng curl

# Default torrc: SOCKS on 0.0.0.0:9050 inside the container.
# T16: DNSPort moved to 0.0.0.0:5353 and published to HOST LOOPBACK ONLY
# (127.0.0.1:53053/udp in docker-compose.yml — host port differs from 5353
# to avoid the mDNS/Avahi wildcard bind on 0.0.0.0:5353) so nmap --dns-servers can
# resolve via Tor — nmap's internal DNS engine speaks raw UDP, which
# proxychains cannot hook (the query would leak to the local resolver).
# Client-side no_proxy loopback bypass is handled in scripts/tor-wrap.sh.
# Never publish these ports beyond loopback in docker-compose.yml.
RUN echo "SocksPort 0.0.0.0:9050" > "/etc/tor/torrc" && \
    echo "DNSPort 0.0.0.0:5353" >> "/etc/tor/torrc" && \
    echo "AutomapHostsOnResolve 1" >> "/etc/tor/torrc" && \
    echo "Log notice stdout" >> "/etc/tor/torrc"

# proxychains config that routes everything through the local Tor SOCKS5
RUN echo "strict_chain" > "/etc/proxychains.conf" && \
    echo "proxy_dns" >> "/etc/proxychains.conf" && \
    echo "tcp_read_time_out 15000" >> "/etc/proxychains.conf" && \
    echo "tcp_connect_time_out 8000" >> "/etc/proxychains.conf" && \
    echo "socks5 127.0.0.1 9050" >> "/etc/proxychains.conf"

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 9050

ENTRYPOINT ["/entrypoint.sh"]
