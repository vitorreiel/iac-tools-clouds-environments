#!/bin/bash

echo "Waiting for ONOS REST API on port 8181..."
until python3 -c "import socket; socket.create_connection(('127.0.0.1', 8181), 1).close()" 2>/dev/null; do
    sleep 2
done
echo "ONOS REST API is up."

echo "Waiting for ONOS OpenFlow provider on port 6653..."
until python3 -c "import socket; socket.create_connection(('127.0.0.1', 6653), 1).close()" 2>/dev/null; do
    sleep 2
done
echo "ONOS OpenFlow provider is ready."

echo "Cleaning up previous Mininet state..."
mn -c 2>/dev/null || true
sleep 1

echo "Starting topology..."
exec python3 /containernet/topology.py
