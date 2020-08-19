FROM alpine:3.12.0

RUN apk add --no-cache -U wireguard-tools

COPY entrypoint.sh /
COPY start.sh /

ENV INTERFACE wg0
ENV LISTEN_PORT 51820

WORKDIR /WireGuard-0.0.20190702/src

ENTRYPOINT [ "/entrypoint.sh" ]

CMD [ "/start.sh" ]
