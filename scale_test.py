import paramiko
import logging
from paramiko import SSHClient, ProxyCommand
from datetime import datetime 
import os

logging.basicConfig(level=logging.INFO)
logging.getLogger("paramiko").setLevel(logging.WARNING)

JUMP_HOST = "10.245.236.176"
JUMP_USER = "ubuntu"
TARGET_HOST = "10.245.236.191"
TARGET_USER = "ubuntu"
KEY_PATH = "~/.ssh/other_vm_key"

Tests = {
    "1": ("unified_support_hub_tests.json", "Platform_Support_Frontend_Service_Coveo_API"),
    "2": ("unified_support_hub_feedback_service_api_tests.json", "Platform_Support_Frontend_Service_Feedback_Service_API"),
    "3": ("unified_support_hub_platform_chat_proxy_service_tests.json", "Platform_Chat_Proxy_Service"),
    "4": ("support_case_services.json", "Support_Case_Services_API")
}

def print_available_tests():
    print("Select the test:")
    for key, value in Tests.items():
        print(f"{key}. {value[1]}")

def get_test_details(choice):
    if choice in Tests:
        return Tests[choice]
    else:
        print("Invalid choice, exiting...")
        exit(1)

def run_commands_on_vm(jump_host, jump_user, target_host, target_user, key_path, commands, output_file):
    try:
        # Create an SSH client
        client = SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())

        # Create a proxy command for the jump host
        proxy_command = f"ssh -i {key_path} -W {target_host}:22 {jump_user}@{jump_host}"
        proxy = ProxyCommand(proxy_command)

        # Connect to the target VM through the jump host
        logging.info(f"Connecting to {target_host} via {jump_host} as {target_user}")
        client.connect(target_host, username=target_user, sock=proxy)
        logging.info("Connection successful")

        with open(output_file, 'w') as f:
            # Run each command
            for command in commands:
                logging.info(f"Running command: {command}")
                stdin, stdout, stderr = client.exec_command(command, get_pty=True)
                
                # Read and log the output in real-time
                while True:
                    line = stdout.readline()
                    if not line:
                        break
                    logging.info(line.strip())
                    f.write(line)
                
                # Read and log any errors
                stderr_output = stderr.read().decode()
                if stderr_output:
                    logging.error(stderr_output)
                    f.write(stderr_output)

        # Close the connection
        client.close()
        logging.info("Connection closed")

    except Exception as e:
        logging.error(f"An error occurred: {e}")

def get_json_file_and_users_and_time():
    print_available_tests()
    choice = input("Enter the number of your choice: ")
    json_file, test_name = get_test_details(choice)
    num_users = input("Enter the number of users to simulate: ")
    duration = input("Enter the duration of the test in seconds: ")
    return json_file, num_users, duration, test_name

def main():
    json_file, num_users, duration, test_name = get_json_file_and_users_and_time()
    commands = [
        f"docker exec -it f8cfb046a842 bash -c 'cd /home/dev/repo/ws/stash.arubanetworks.com/ccs/ccs-scale/ && git pull && poetry run python locustfile.py -u users.json -t test_jsons/{json_file} -s task -n {num_users} -d {duration}'"
    ]

    timestamp = datetime.now().strftime("%d-%m-%Y_%I.%M%p")
    desktop_path = os.path.join(os.path.expanduser("~"), "Desktop")
    output_file = os.path.join(desktop_path, f"{test_name}_{timestamp}.log")
    run_commands_on_vm(JUMP_HOST, JUMP_USER, TARGET_HOST, TARGET_USER, KEY_PATH, commands, output_file)

if __name__ == "__main__":
    main()