#!/bin/bash
# Stop and remove the container. Your work, the Vivado install and the license stay on disk.
. "$(dirname "$0")/docker/common.sh"

load_env || die "No .env yet. Run ./install.sh first."
ensure_docker
docker compose down
