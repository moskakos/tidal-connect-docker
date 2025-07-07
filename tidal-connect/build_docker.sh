#!/bin/bash
# tidal-connect/build_docker.sh

DOCKER_HOST=${DOCKER_HOST:-"tidal"}
CONTAINER_NAME=${CONTAINER_NAME:-"moskakos/tidal-connect"}

# SSH into the Docker host and stop & remove the container
ssh "$DOCKER_HOST" "docker stop $CONTAINER_NAME || true && docker rm $CONTAINER_NAME || true"

# Build the Docker image and transfer it to the Docker host
docker build --no-cache -f Dockerfile -t "$CONTAINER_NAME" .
docker image save "$CONTAINER_NAME" | pv | ssh "$DOCKER_HOST" "docker load"