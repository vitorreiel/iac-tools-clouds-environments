#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ONOS_DIR="$SCRIPT_DIR/../sdn-topology/fat-tree/onos"
BASE="$SCRIPT_DIR/template_base.yaml"
OUT="$SCRIPT_DIR/template.yaml"

DC_B64=$(base64 -w0 "$ONOS_DIR/docker-compose.yml")
SS_B64=$(base64 -w0 "$ONOS_DIR/start.sh")
TP_B64=$(base64 -w0 "$ONOS_DIR/topology.py")

sed \
  -e "s|__DOCKER_COMPOSE_B64__|$DC_B64|g" \
  -e "s|__START_SH_B64__|$SS_B64|g" \
  -e "s|__TOPOLOGY_PY_B64__|$TP_B64|g" \
  "$BASE" > "$OUT"

echo "Generated: $OUT"
