#!/bin/bash

echo "Waiting for Ryu on port 6633..."
until python3 -c "import socket; socket.create_connection(('127.0.0.1', 6633), 1).close()" 2>/dev/null; do
    sleep 1
done
echo "Ryu is up."

echo "Cleaning up previous Mininet state..."
mn -c 2>/dev/null || true
sleep 1

echo "Starting topology..."
exec python3 /containernet/topology.py
