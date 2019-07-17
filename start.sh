#!/bin/bash

function cleanup() {
  wg-quick down $INTERFACE
  echo "Wireguard stopped"
  exit 0
}

trap cleanup SIGTERM

wg-quick up $INTERFACE
echo "Wireguard started"

while true; do
  sleep 1 &
  wait $!
done