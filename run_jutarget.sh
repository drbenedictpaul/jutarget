#!/bin/bash

# --- juTarget Launcher ---

echo "======================================================"
echo "      juTarget v1.0 - Targeted NGS Analysis"
echo ""
echo "           Developed by: Dr. Benedict Christopher Paul"
echo "           Website: http://www.drpaul.cc"
echo "======================================================"
echo ""

# 1. Hardware ID Detection (Ubuntu/Linux)
# We try to read DMI data from /sys/class/dmi/id/
if [ -f /sys/class/dmi/id/product_uuid ]; then
    UUID=$(cat /sys/class/dmi/id/product_uuid)
    SYS_SERIAL=$(cat /sys/class/dmi/id/product_serial)
    BOARD_SERIAL=$(cat /sys/class/dmi/id/board_serial)
    
    # Construct the ID in the format: /SystemSerial/BoardSerial/
    BASEBOARD_ID="/$SYS_SERIAL/$BOARD_SERIAL/"
else
    echo "Error: Could not detect Hardware IDs. Please run with sudo."
    echo "Usage: sudo ./run_jutarget.sh"
    exit 1
fi

echo "Detected UUID: $UUID"
echo "Detected ID:   $BASEBOARD_ID"
echo "Verifying license..."
echo ""

# 2. Setup Directories on Host
mkdir -p ~/juTarget_input
mkdir -p ~/juTarget_output
mkdir -p ~/juTarget_results

echo "Directories initialized in your Home folder."
echo "Press [Enter] to launch the juTarget server..."
read

# 3. Launch Docker Container
# We pass the constructed BASEBOARD_ID and UUID to the Julia application
docker run -it --rm \
  -p 8000:8000 \
  -v ~/juTarget_input:/root/juTarget_input \
  -v ~/juTarget_output:/root/juTarget_output \
  -v ~/juTarget_results:/root/juTarget_results \
  -e JUTARGET_HW_UUID="$UUID" \
  -e JUTARGET_HW_BASEBOARD="$BASEBOARD_ID" \
  jutarget_app
