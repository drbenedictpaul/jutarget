#!/bin/bash
echo "Installing juTarget..."
echo "--------------------------------"

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "Error: Docker is not running. Please start the Docker service and try again."
    exit 1
fi

# Check if the image file exists
if [ ! -f "jutarget_app.tar.gz" ]; then
    echo "Error: Application file 'jutarget_app.tar.gz' not found!"
    exit 1
fi

echo "Loading Application Image... (This may take a minute or two)"
docker load -i jutarget_app.tar.gz

echo "--------------------------------"
echo "Installation Complete."
echo "You can now run the application using: sudo ./run_jutarget"
