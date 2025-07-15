#!/bin/bash
# tidal-connect/build_docker.sh

DOCKER_HOST=${DOCKER_HOST:-"tidal"}
CONTAINER_NAME=${CONTAINER_NAME:-"moskakos/tidal-connect"}
CONTAINER_DIR=${CONTAINER_DIR:-"tidal-connect-docker"}

# SSH into the Docker host and stop & remove the container
ssh "$DOCKER_HOST" "cd '$CONTAINER_DIR' && \
                    docker-compose down --rmi all || true"

# Build the Docker image and transfer it to the Docker host
docker build --no-cache -f Dockerfile -t "$CONTAINER_NAME" .
docker image save "$CONTAINER_NAME" | pv | ssh "$DOCKER_HOST" "docker load"