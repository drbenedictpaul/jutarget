#!/bin/bash
echo "Installing juTarget..."
echo "--------------------------------"
if ! docker info > /dev/null 2>&1; then
    echo "Error: Docker is not running. Please start the Docker service."
    exit 1
fi
if [ ! -f "jutarget_app.tar.gz" ]; then
    echo "Error: Application file 'jutarget_app.tar.gz' not found!"
    exit 1
fi
echo "Loading Application Image..."
docker load -i jutarget_app.tar.gz
chmod +x run_jutarget.sh
echo "--------------------------------"
echo "Installation Complete."
echo "You can now run the application using: sudo ./run_jutarget.sh"
