#!/bin/bash

# --- juTarget Launcher (Final Shell Script Version) ---

# --- Sudo-aware Home Directory Detection ---
# This ensures that when run with 'sudo', we still find the original user's home directory.
if [ -n "$SUDO_USER" ]; then
    # If run with sudo, get the home directory of the user who invoked sudo
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
    # If not run with sudo, just use the normal HOME variable
    USER_HOME=$HOME
fi

# Check if we successfully found a home directory
if [ -z "$USER_HOME" ]; then
    echo "ERROR: Could not determine the user's home directory."
    exit 1
fi

echo "======================================================"
echo "      juTarget v1.0 - Targeted NGS Analysis"
echo "           Developed by: Dr. Benedict Christopher Paul"
echo "======================================================"
echo ""

# --- Hardware ID Detection (Linux) ---
if [ -f /sys/class/dmi/id/product_uuid ]; then
    UUID=$(cat /sys/class/dmi/id/product_uuid)
    SYS_SERIAL=$(cat /sys/class/dmi/id/product_serial)
    BOARD_SERIAL=$(cat /sys/class/dmi/id/board_serial)
    BASEBOARD_ID="/$SYS_SERIAL/$BOARD_SERIAL/"
else
    echo "Error: Could not detect Hardware IDs. Please run with sudo."
    exit 1
fi

echo "Verifying Hardware License..."
echo ""

# --- Setup Directories on the Host ---
# Use the correctly detected user's home directory
mkdir -p "$USER_HOME/juTarget_input"
mkdir -p "$USER_HOME/juTarget_output"
mkdir -p "$USER_HOME/juTarget_results"

echo "Press [Enter] to launch the juTarget server..."
read

# --- Launch Docker Container ---
# Mount volumes using the correctly detected user's home directory
docker run -it --rm \
  -p 8001:8001 \
  -v "$USER_HOME/juTarget_input:/root/juTarget_input" \
  -v "$USER_HOME/juTarget_output:/root/juTarget_output" \
  -v "$USER_HOME/juTarget_results:/root/juTarget_results" \
  -e JUTARGET_HW_UUID="$UUID" \
  -e JUTARGET_HW_BASEBOARD="$BASEBOARD_ID" \
  jutarget_app
