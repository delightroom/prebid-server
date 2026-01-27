#!/bin/bash
#
# Build and push Prebid Server image to ECR (us-east-2)
#
# Usage:
#   ./scripts/build_image.sh [--skip-tests] [--no-latest]
#
# Prerequisites:
#   - AWS CLI configured with credentials that can push to ECR
#   - Docker running
#
# Environment variables (optional):
#   IMAGE_TAG - Override the image tag (default: git commit SHA, 8 chars)
#

set -euo pipefail

# Configuration
AWS_REGION="us-east-2"
AWS_ACCOUNT_ID="954592026118"
ECR_REPOSITORY="daro/prebid-server"
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

# Parse arguments
SKIP_TESTS="false"
TAG_LATEST="true"

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-tests)
            SKIP_TESTS="true"
            shift
            ;;
        --no-latest)
            TAG_LATEST="false"
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--skip-tests] [--no-latest]"
            exit 1
            ;;
    esac
done

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${PROJECT_ROOT}"

# Get version from git commit SHA
if [[ -z "${IMAGE_TAG:-}" ]]; then
    IMAGE_TAG=$(git rev-parse HEAD | cut -c1-8)
fi

echo "============================================"
echo "Prebid Server Image Build"
echo "============================================"
echo "Region:      ${AWS_REGION}"
echo "Repository:  ${ECR_REPOSITORY}"
echo "Image Tag:   ${IMAGE_TAG}"
echo "Skip Tests:  ${SKIP_TESTS}"
echo "Tag Latest:  ${TAG_LATEST}"
echo "============================================"

# Login to ECR
echo ""
echo "Logging in to ECR..."
aws ecr get-login-password --region "${AWS_REGION}" | \
    docker login --username AWS --password-stdin "${ECR_REGISTRY}"

# Build image
echo ""
echo "Building Docker image..."
FULL_IMAGE="${ECR_REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}"

if [[ "${SKIP_TESTS}" == "true" ]]; then
    TEST_ARG="false"
else
    TEST_ARG="true"
fi

# The Dockerfile downloads go1.24.0.linux-amd64, so we must build for amd64.
# On Apple Silicon Macs, this uses QEMU emulation via Docker Desktop.
docker build \
    --platform linux/amd64 \
    --build-arg TEST="${TEST_ARG}" \
    -t "${FULL_IMAGE}" \
    -f Dockerfile \
    .

# Tag as latest if requested
if [[ "${TAG_LATEST}" == "true" ]]; then
    LATEST_IMAGE="${ECR_REGISTRY}/${ECR_REPOSITORY}:latest"
    echo ""
    echo "Tagging as latest..."
    docker tag "${FULL_IMAGE}" "${LATEST_IMAGE}"
fi

# Push images
echo ""
echo "Pushing image: ${FULL_IMAGE}"
docker push "${FULL_IMAGE}"

if [[ "${TAG_LATEST}" == "true" ]]; then
    echo "Pushing image: ${LATEST_IMAGE}"
    docker push "${LATEST_IMAGE}"
fi

echo ""
echo "============================================"
echo "Build complete!"
echo "============================================"
echo "Image Name: ${ECR_REGISTRY}/${ECR_REPOSITORY}"
echo "Image Tag:  ${IMAGE_TAG}"
echo ""
echo "To deploy, run:"
echo "  ./scripts/deploy.sh --tag ${IMAGE_TAG}"
echo "============================================"
