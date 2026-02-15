#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

void get_file_content(const char *filename, char *buffer, size_t size) {
    FILE *f = fopen(filename, "r");
    if (f) {
        if (fgets(buffer, size, f)) {
            // Remove newline characters
            buffer[strcspn(buffer, "\n")] = 0;
        }
        fclose(f);
    } else {
        printf("Error: Run with sudo to read hardware IDs.\n");
        exit(1);
    }
}

int main() {
    char uuid[128] = {0};
    char sys_serial[128] = {0};
    char board_serial[128] = {0};
    char baseboard_id[256] = {0};
    char command[2048];
    
    // 1. Print Banner
    printf("======================================================\n");
    printf("      juTarget v1.0 - Targeted NGS Analysis\n");
    printf("           Developed by: Dr. Benedict Christopher Paul\n");
    printf("======================================================\n\n");

    // 2. Read Hardware IDs directly from system files
    get_file_content("/sys/class/dmi/id/product_uuid", uuid, sizeof(uuid));
    get_file_content("/sys/class/dmi/id/product_serial", sys_serial, sizeof(sys_serial));
    get_file_content("/sys/class/dmi/id/board_serial", board_serial, sizeof(board_serial));

    // Construct Baseboard ID format: /SystemSerial/BoardSerial/
    snprintf(baseboard_id, sizeof(baseboard_id), "/%s/%s/", sys_serial, board_serial);

    printf("Verifying Hardware License...\n");
    printf("UUID: %s\n", uuid);
    printf("ID:   %s\n\n", baseboard_id);

    // 3. Setup Directories
    system("mkdir -p ~/juTarget_input");
    system("mkdir -p ~/juTarget_output");
    system("mkdir -p ~/juTarget_results");
    
    printf("Press [Enter] to launch application...");
    getchar();

    // 4. Construct the Docker Command (Hidden from user)
    // We pass the IDs we just read into the container
    snprintf(command, sizeof(command), 
        "docker run -it --rm "
        "-p 8000:8000 "
        "-v ~/juTarget_input:/root/juTarget_input "
        "-v ~/juTarget_output:/root/juTarget_output "
        "-v ~/juTarget_results:/root/juTarget_results "
        "-e JUTARGET_HW_UUID=\"%s\" "
        "-e JUTARGET_HW_BASEBOARD=\"%s\" "
        "jutarget_app", uuid, baseboard_id);

    // 5. Execute Docker
    system(command);

    return 0;
}
