#!/bin/bash

# OSSM Confidence Score Container Build Script
# Builds and optionally pushes the container to quay.io

set -e

# Configuration
IMAGE_NAME="ossm-confidence"
QUAY_ORG="${QUAY_ORG:-your-org}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
FULL_IMAGE_NAME="quay.io/${QUAY_ORG}/${IMAGE_NAME}:${IMAGE_TAG}"

echo "=== OSSM Confidence Score Container Build ==="
echo "Image: ${FULL_IMAGE_NAME}"
echo ""

# Build the image
echo "🔨 Building container image..."
docker build -t "${IMAGE_NAME}:${IMAGE_TAG}" .
echo "✅ Build complete: ${IMAGE_NAME}:${IMAGE_TAG}"

# Tag for quay.io
echo "🏷️ Tagging for quay.io..."
docker tag "${IMAGE_NAME}:${IMAGE_TAG}" "${FULL_IMAGE_NAME}"
echo "✅ Tagged: ${FULL_IMAGE_NAME}"

# Option to push
if [ "$1" = "push" ]; then
    echo "📤 Pushing to quay.io..."
    docker push "${FULL_IMAGE_NAME}"
    echo "✅ Pushed: ${FULL_IMAGE_NAME}"
elif [ "$1" = "test" ]; then
    echo "🧪 Running test..."
    docker run --rm "${FULL_IMAGE_NAME}" --help
else
    echo ""
    echo "Next steps:"
    echo "  Test:  ./build.sh test"
    echo "  Push:  ./build.sh push"
    echo "  Run:   docker run --rm -e CLAUDE_API_KEY=xxx -e BUILD_ID=xxx -e CHANGE_TYPE=xxx ${FULL_IMAGE_NAME}"
fi

echo ""
echo "Image ready: ${FULL_IMAGE_NAME}"