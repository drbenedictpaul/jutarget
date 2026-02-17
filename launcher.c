#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

void get_file_content(const char *filename, char *buffer, size_t size) {
    FILE *f = fopen(filename, "r");
    if (f) {
        if (fgets(buffer, size, f)) {
            buffer[strcspn(buffer, "\n")] = 0;
        }
        fclose(f);
    } else {
        printf("Error: Could not read hardware ID file '%s'. Please run with sudo.\n", filename);
        exit(1);
    }
}

int main() {
    char uuid[128] = {0}, sys_serial[128] = {0}, board_serial[128] = {0}, baseboard_id[256] = {0}, command[2048];
    char homedir[256];

    // --- Sudo-aware home directory detection (without getpwnam) ---
    const char *sudo_user = getenv("SUDO_USER");
    if (sudo_user && strlen(sudo_user) > 0) {
        // If run with sudo, assume home directory is /home/USERNAME
        snprintf(homedir, sizeof(homedir), "/home/%s", sudo_user);
    } else {
        // If not run with sudo, use the standard HOME variable
        const char *home_env = getenv("HOME");
        if (home_env) {
            strncpy(homedir, home_env, sizeof(homedir) - 1);
        } else {
            printf("Error: Could not determine user's home directory.\n");
            exit(1);
        }
    }

    printf("======================================================\n");
    printf("      juTarget v1.0 - Targeted NGS Analysis\n");
    printf("           Developed by: Dr. Benedict Christopher Paul\n");
    printf("======================================================\n\n");
    
    get_file_content("/sys/class/dmi/id/product_uuid", uuid, sizeof(uuid));
    get_file_content("/sys/class/dmi/id/product_serial", sys_serial, sizeof(sys_serial));
    get_file_content("/sys/class/dmi/id/board_serial", board_serial, sizeof(board_serial));
    
    snprintf(baseboard_id, sizeof(baseboard_id), "/%s/%s/", sys_serial, board_serial);
    printf("Verifying Hardware License...\n\n");

    char input_path[512], output_path[512], results_path[512], mkdir_cmd[1024];
    snprintf(input_path, sizeof(input_path), "%s/juTarget_input", homedir);
    snprintf(output_path, sizeof(output_path), "%s/juTarget_output", homedir);
    snprintf(results_path, sizeof(results_path), "%s/juTarget_results", homedir);
    snprintf(mkdir_cmd, sizeof(mkdir_cmd), "mkdir -p %s %s %s", input_path, output_path, results_path);
    system(mkdir_cmd);
    
    printf("Press [Enter] to launch application...");
    getchar();
    
    snprintf(command, sizeof(command), 
        "docker run -it --rm -p 8001:8001 "
        "-v %s:/root/juTarget_input "
        "-v %s:/root/juTarget_output "
        "-v %s:/root/juTarget_results "
        "-e JUTARGET_HW_UUID=\"%s\" "
        "-e JUTARGET_HW_BASEBOARD=\"%s\" "
        "jutarget_app", input_path, output_path, results_path, uuid, baseboard_id);

    system(command);
    return 0;
}
