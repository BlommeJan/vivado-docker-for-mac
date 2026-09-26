#!/bin/bash
# Open a bash shell in the running container (Vivado on PATH). Extra args run as a command:
#   ./shell.sh vivado -version
. "$(dirname "$0")/docker/common.sh"

load_env || die "No .env yet. Run ./install.sh first."
ensure_docker
running || die "Container is not running; run ./start.sh first."
if [ $# -gt 0 ]; then
    exec docker compose exec -w /home/user/lab vivado bash -lc "$*"
fi
exec docker compose exec -it -w /home/user/lab vivado bash -l
