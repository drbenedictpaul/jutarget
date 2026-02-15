# juTarget - User Installation Guide

This guide provides instructions for installing and running the juTarget application.

---

### **Prerequisites: Docker**

Before you begin, you must have Docker installed and running on your system.

*   **On Ubuntu / Debian:**
    If you don't have Docker, open a terminal and run these commands:
    ```bash
    sudo apt-get update
    sudo apt-get install -y docker.io
    sudo systemctl start docker
    ```

*   **On Fedora:**
    If you don't have Docker, open a terminal and run these commands:
    ```bash
    sudo dnf install -y docker
    sudo systemctl start docker
    ```

---

### **1. One-Time Installation**

1.  **Extract the Archive:**
    Open a terminal and run this command:
    ```bash
    tar -xzvf juTarget_Distribution.tar.gz
    ```

2.  **Navigate into the Directory:**
    ```bash
    cd juTarget_Distribution
    ```

3.  **Run the Installer Script:**
    This loads the application into Docker. You must use `sudo`.
    ```bash
    sudo ./install_jutarget.sh
    ```

---

### **2. Running juTarget**

To start the application any time after installation:

1.  **Navigate to the `juTarget_Distribution` directory** in your terminal.

2.  **Execute the Launcher with `sudo`:**
    ```bash
    sudo ./run_jutarget
    ```

3.  **Launch Server:**
    Press the **[Enter]** key to start the server.

---

### **3. Using the Application**

1.  **Place Data:** Copy your Nanopore FASTQ files into the `~/juTarget_input` folder in your Home directory.

2.  **Open Browser:** Open your web browser (e.g., Firefox, Chrome) and go to:
    **http://localhost:8000**

3.  **Analyze:** Click the "Start Analysis" button.

Final results are saved permanently in `~/juTarget_results`. You can also view and print them from the "View Results" tab.

---
*For support, please contact Dr. Paul ([www.drpaul.cc](http://www.drpaul.cc)).*
