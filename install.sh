#!/bin/bash
echo "Installing juTarget..."

# Check if Docker is installed
if ! command -v docker &> /dev/null
then
    echo "Docker could not be found. Please install Docker first."
    exit 1
fi

# Build the image
echo "Building Docker Image (this may take a few minutes)..."
docker build -t jutarget_app .

echo "Installation Complete."
echo "You can now run the application using ./run_jutarget.sh"
