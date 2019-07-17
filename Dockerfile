FROM ubuntu:18.04

RUN apt-get update -qq \
  && apt-get install -y -qq software-properties-common \
  && add-apt-repository ppa:wireguard/wireguard \
  && apt-get update -qq \
  && apt-get install -y -qq wireguard libmnl-dev libelf-dev build-essential pkg-config wget iproute2 net-tools \
  && wget -O /wireguard.tar.xz https://git.zx2c4.com/WireGuard/snapshot/WireGuard-0.0.20190702.tar.xz \
  && cd / \
  && tar -xf /wireguard.tar.xz

COPY entrypoint.sh /
COPY start.sh /

ENV INTERFACE wg0
ENV LISTEN_PORT 51820

WORKDIR /WireGuard-0.0.20190702/src

ENTRYPOINT [ "/entrypoint.sh" ]

CMD [ "/start.sh" ]
