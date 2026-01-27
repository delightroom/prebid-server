#!/bin/bash
#
# Deploy Prebid Server by updating prebid-server-deploy repository
#
# Usage:
#   ./scripts/deploy.sh --tag <image_tag> [--target <environment>] [--strategy <strategy>]
#
# Examples:
#   ./scripts/deploy.sh --tag abc12345
#   ./scripts/deploy.sh --tag abc12345 --target use2.dev --strategy rollingUpdate
#
# Prerequisites:
#   - Git configured with credentials to push to delightroom/prebid-server-deploy
#

set -euo pipefail

# Configuration
DEPLOY_REPO="https://github.com/delightroom/prebid-server-deploy.git"
DEFAULT_TARGET="use2.dev"
DEFAULT_STRATEGY="rollingUpdate"

# Parse arguments
IMAGE_TAG=""
TARGET="${DEFAULT_TARGET}"
STRATEGY="${DEFAULT_STRATEGY}"

while [[ $# -gt 0 ]]; do
    case $1 in
        --tag)
            IMAGE_TAG="$2"
            shift 2
            ;;
        --target)
            TARGET="$2"
            shift 2
            ;;
        --strategy)
            STRATEGY="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 --tag <image_tag> [--target <environment>] [--strategy <strategy>]"
            echo ""
            echo "Options:"
            echo "  --tag       Image tag to deploy (required)"
            echo "  --target    Target environment (default: use2.dev)"
            echo "              Options: use2.dev"
            echo "  --strategy  Deployment strategy (default: rollingUpdate)"
            echo "              Options: rollingUpdate, canary"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Validate required arguments
if [[ -z "${IMAGE_TAG}" ]]; then
    echo "Error: --tag is required"
    echo "Usage: $0 --tag <image_tag> [--target <environment>] [--strategy <strategy>]"
    exit 1
fi

# Validate target
case "${TARGET}" in
    use2.dev)
        ;;
    *)
        echo "Error: Invalid target '${TARGET}'"
        echo "Valid targets: use2.dev"
        exit 1
        ;;
esac

# Validate strategy
case "${STRATEGY}" in
    rollingUpdate|canary)
        ;;
    *)
        echo "Error: Invalid strategy '${STRATEGY}'"
        echo "Valid strategies: rollingUpdate, canary"
        exit 1
        ;;
esac

echo "============================================"
echo "Prebid Server Deployment"
echo "============================================"
echo "Image Tag:  ${IMAGE_TAG}"
echo "Target:     ${TARGET}"
echo "Strategy:   ${STRATEGY}"
echo "============================================"

# Create temporary directory for deploy repo
TEMP_DIR=$(mktemp -d)
trap "rm -rf ${TEMP_DIR}" EXIT

echo ""
echo "Cloning prebid-server-deploy repository..."
git clone --depth 1 "${DEPLOY_REPO}" "${TEMP_DIR}"

cd "${TEMP_DIR}"

# Verify values file exists
VALUES_FILE="chart/values.${TARGET}.yaml"
if [[ ! -f "${VALUES_FILE}" ]]; then
    echo "Error: Values file not found: ${VALUES_FILE}"
    exit 1
fi

echo ""
echo "Updating ${VALUES_FILE}..."

# Update image tag
sed -i.bak "s/^  tag: .*/  tag: \"${IMAGE_TAG}\"/" "${VALUES_FILE}"
rm "${VALUES_FILE}.bak"

# Update strategy
sed -i.bak "s/strategyType: .*/strategyType: ${STRATEGY}/" "${VALUES_FILE}"
rm "${VALUES_FILE}.bak"

# Show changes
echo ""
echo "Changes to ${VALUES_FILE}:"
git diff "${VALUES_FILE}" || true

# Commit and push
echo ""
echo "Committing and pushing changes..."
git config user.email "local-deploy@delightroom.com"
git config user.name "Local Deploy Script"
git add -A

if git diff-index --quiet HEAD; then
    echo "No changes to commit (image tag and strategy already set)"
else
    git commit -m "deploy ${TARGET}: update image to ${IMAGE_TAG} with ${STRATEGY} strategy"
    git push origin main
    echo ""
    echo "============================================"
    echo "Deployment triggered!"
    echo "============================================"
    echo "ArgoCD will automatically sync the changes."
    echo ""
    echo "Monitor deployment:"
    echo "  argocd app get prebid-server-${TARGET//./-}"
    echo "  kubectl --context=daro-use2-dev -n daro get pods -l app=prebid-server"
    echo "============================================"
fi
