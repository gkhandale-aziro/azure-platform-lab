#!/bin/bash
set -euo pipefail
IMAGE_NAME="${1:-gkhandale/jenkins-agent:latest}"
CONTEXT_DIR="."
DOCKERFILE_PATH="ci/jenkins/agent/Dockerfile"

echo "Building Jenkins agent image: $IMAGE_NAME"
docker build -t "$IMAGE_NAME" -f "$DOCKERFILE_PATH" "$CONTEXT_DIR"

echo "Build complete: $IMAGE_NAME"
