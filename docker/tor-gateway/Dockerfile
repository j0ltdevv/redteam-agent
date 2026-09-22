FROM alpine:3.19

RUN apk add --no-cache tor proxychains-ng curl

# Default torrc: SOCKS on 0.0.0.0:9050 inside the container
RUN echo 'SocksPort 0.0.0.0:9050' > /etc/tor/torrc && \
    echo 'Log notice stdout' >> /etc/tor/torrc

# proxychains config that routes everything through the local Tor SOCKS5
RUN echo 'strict_chain' > /etc/proxychains.conf && \
    echo 'proxy_dns' >> /etc/proxychains.conf && \
    echo 'tcp_read_time_out 15000' >> /etc/proxychains.conf && \
    echo 'tcp_connect_time_out 8000' >> /etc/proxychains.conf && \
    echo 'socks5 127.0.0.1 9050' >> /etc/proxychains.conf

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 9050

ENTRYPOINT ["/entrypoint.sh"]
