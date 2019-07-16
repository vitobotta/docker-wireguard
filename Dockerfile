FROM alpine

RUN apk add --no-cache bash build-base linux-vanilla-dev libmnl-dev wireguard-tools wget xz elfutils-libelf \
  && wget -O /wireguard.tar.xz https://git.zx2c4.com/WireGuard/snapshot/WireGuard-0.0.20190702.tar.xz \
  && cd / \
  && tar -xf /wireguard.tar.xz

COPY entrypoint.sh /
COPY start.sh /

ENV INTERFACE wg0
ENV LISTEN_PORT 51820

WORKDIR /WireGuard-0.0.20190702/src

ENTRYPOINT [ "/entrypoint.sh" ]

# CMD [ "/start.sh" ]
