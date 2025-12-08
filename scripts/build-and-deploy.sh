#!/bin/bash
set -e

echo "PostgreSQL pgBackRest Build and Deploy Script"
echo "=============================================="

# Variables
IMAGE_NAME="postgres-pgbackrest"
IMAGE_TAG="latest"
REGISTRY="${REGISTRY:-ghcr.io}"
GITHUB_USER="${GITHUB_USER:-your-username}"

# Function to build image locally
build_local() {
    echo "Building Docker image locally..."
    docker build -t ${IMAGE_NAME}:${IMAGE_TAG} .
    
    if [ $? -eq 0 ]; then
        echo "✓ Image built successfully: ${IMAGE_NAME}:${IMAGE_TAG}"
    else
        echo "✗ Build failed"
        exit 1
    fi
}

# Function to test image
test_image() {
    echo "Testing Docker image..."
    
    # Check if image exists
    if ! docker image inspect ${IMAGE_NAME}:${IMAGE_TAG} > /dev/null 2>&1; then
        echo "✗ Image not found. Build it first."
        exit 1
    fi
    
    echo "✓ Image exists"
    
    # You can add more tests here
    # For example, run a test container
}

# Function to push to GitHub Container Registry
push_github() {
    echo "Pushing to GitHub Container Registry..."
    
    # Check if logged in
    echo "Make sure you're logged in to GitHub Container Registry:"
    echo "  echo \$GITHUB_TOKEN | docker login ghcr.io -u ${GITHUB_USER} --password-stdin"
    read -p "Are you logged in? (y/n) " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Please log in first and try again."
        exit 1
    fi
    
    # Tag image for GitHub Container Registry
    docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${REGISTRY}/${GITHUB_USER}/${IMAGE_NAME}:${IMAGE_TAG}
    
    # Push image
    docker push ${REGISTRY}/${GITHUB_USER}/${IMAGE_NAME}:${IMAGE_TAG}
    
    if [ $? -eq 0 ]; then
        echo "✓ Image pushed successfully to ${REGISTRY}/${GITHUB_USER}/${IMAGE_NAME}:${IMAGE_TAG}"
    else
        echo "✗ Push failed"
        exit 1
    fi
}

# Function to create and push a version tag
tag_version() {
    VERSION=$1
    
    if [ -z "$VERSION" ]; then
        echo "Usage: $0 tag-version <version>"
        echo "Example: $0 tag-version v1.0.0"
        exit 1
    fi
    
    echo "Creating and pushing version tag: ${VERSION}"
    
    # Git tag
    git tag ${VERSION}
    git push origin ${VERSION}
    
    echo "✓ Git tag created and pushed"
    echo "GitHub Actions will automatically build and push the image"
}

# Main menu
case "$1" in
    build)
        build_local
        ;;
    test)
        test_image
        ;;
    push)
        push_github
        ;;
    tag-version)
        tag_version $2
        ;;
    all)
        build_local
        test_image
        push_github
        ;;
    *)
        echo "Usage: $0 {build|test|push|tag-version|all}"
        echo ""
        echo "Commands:"
        echo "  build        - Build Docker image locally"
        echo "  test         - Test the Docker image"
        echo "  push         - Push image to GitHub Container Registry"
        echo "  tag-version  - Create and push a version tag (triggers CI/CD)"
        echo "  all          - Build, test, and push"
        echo ""
        echo "Examples:"
        echo "  $0 build"
        echo "  $0 tag-version v1.0.0"
        echo "  GITHUB_USER=myuser $0 push"
        exit 1
        ;;
esac

echo ""
echo "Done!"
