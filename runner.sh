#!/bin/bash

# Define variables
IMAGE_NAME="nginx-flask-fileserver"
CONTAINER_NAME="nginx-flask-fileserver"
HOST_PORT=8080
SHARED_DIR="Shared"

# Stop and remove any existing container
if [ "$(docker ps -q -f name=$CONTAINER_NAME)" ]; then
    echo "Stopping and removing existing container $CONTAINER_NAME..."
    docker stop $CONTAINER_NAME && docker rm $CONTAINER_NAME
fi

# Create shared directory if not exists
mkdir -p "$SHARED_DIR"

docker build -t $IMAGE_NAME .

docker run -d --rm \
    -p $HOST_PORT:80 \
    --name $CONTAINER_NAME \
    -v $SHARED_DIR:/shared_files \
    $IMAGE_NAME
