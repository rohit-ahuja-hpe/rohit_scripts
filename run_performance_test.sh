# Clone the repository https://github.com/glcp/ccs-scale and run this script from the root directory of the repository
# This script is used to run performance tests on a mainline or a specific branch of the ccs-scale repository using GitHub Actions.


#!/bin/bash

# Function to check if gh CLI is installed
check_gh() {
    if ! command -v gh &> /dev/null; then
        printf "GitHub CLI (gh) is not installed. Please install it first.\n"
        exit 1
    fi

    # Check if authenticated
    if ! gh auth status &> /dev/null; then
        printf "Please authenticate with GitHub first using 'gh auth login'\n"
        exit 1
    fi
}

# Function to get required input
get_input() {
    local prompt=$1
    local value=""
    while [ -z "$value" ]; do
        read -p "$prompt: " value
        if [ -z "$value" ]; then
            printf "This field is required. Please enter a value.\n"
        fi
    done
    echo "$value"
}

# Function to get the current git branch
get_current_branch() {
    local branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    if [ -z "$branch" ]; then
        branch=$(get_input "Enter branch name")
    fi
    echo "$branch"
}

# Function to get the latest run ID for a specific service
get_latest_run_id() {
    local service_name=$1
    local run_id=""

    # List the runs for the fetch_service_logs.yaml workflow
    runs=$(gh run list --workflow fetch_service_logs.yaml --limit 10 --json databaseId,headBranch --jq '.[] | select(.headBranch == "'$BRANCH'") | .databaseId')

    for id in $runs; do
        # Check the details of each run to find the one with the desired service name
        if gh run view "$id" --log | grep -q "$service_name"; then
            run_id=$id
            break
        fi
    done

    echo "$run_id"
}

get_version() {
    if [ -z "$BRANCH" ]; then
        echo "Branch is not set. Please call get_branch_inputs first."
        return 1
    fi
    run_id=$(gh run list --workflow manual_build.yaml -b "${BRANCH}" --json databaseId --jq '.[0].databaseId')
    if [ -z "$run_id" ]; then
        echo "No runs found for workflow manual_build.yaml on branch ${BRANCH}."
        return 1
    fi
    gh run view "$run_id" --log | grep 'Updating coreupdate updateservicectl package create' | sed -E -n -e 's/.*--version=(.*) --file.*/\1/p'
}

choose_service_name() {
    printf "Choose service name:\n"
    printf "1. use-platform-support-frontend-service-coveo\n"
    printf "2. use-platform-support-frontend-service-feedback\n"
    printf "3. use-support-case-services\n"
    printf "4. Enter service name\n"
    read -p "Enter your choice: " choice
    case $choice in
        1)
            service_name="use-platform-support-frontend-service-coveo"
            ;;
        2)
            service_name="use-platform-support-frontend-service-feedback"
            ;;
        3)
            service_name="use-support-case-services"
            ;;
        4)
            read -p "Enter service name: " service_name
            ;;
        *)
            printf "Invalid choice. Exiting...\n"
            exit 1
            ;;
    esac
}
# Function to continuously watch service logs
watch_service_logs() {
    get_branch_inputs
    choose_service_name
    printf "Starting continuous log monitoring for service: %s\n" "$service_name"
    printf "Press Ctrl+C to stop monitoring logs\n"

    # Trap Ctrl+C
    trap 'printf "\nStopping log monitoring...\n"; exit 0' INT

    # Run the log fetch workflow initially
    gh workflow run fetch_service_logs.yaml \
        --ref "$BRANCH" \
        -f service_name="$service_name"
	
	printf "Sleep for 15 seconds for watch_service_logs to complete"
    sleep 15
	
    # Get the latest run ID for the log fetch workflow
    LOG_RUN_ID=$(get_latest_run_id "$service_name")

    if [ -z "$LOG_RUN_ID" ]; then
        printf "No previous log fetch workflow run found.\n"
        exit 1
    fi

    while true; do
        printf "\nRe-running log fetch workflow at %s...\n" "$(date '+%Y-%m-%d %H:%M:%S')"

        gh run rerun "$LOG_RUN_ID"
        sleep 5
        gh run watch "$LOG_RUN_ID"
        gh run view "$LOG_RUN_ID" --log

        # Wait for 15 seconds before next fetch
        printf "Waiting 15 seconds before next log fetch...\n"
        sleep 15
    done
}

# Function to run workflow
run_workflow() {
    # Start the workflow
    printf "Starting workflow on branch %s...\n" "$BRANCH"
    gh workflow run "$WORKFLOW_NAME" \
        --ref "$BRANCH" \
        -f version="$VERSION" \
        -f replicas="$REPLICAS" \
        -f num_users="$NUM_USERS" \
        -f spawn_rate="$SPAWN_RATE" \
        -f test_duration="$TEST_DURATION"

    if [ $? -eq 0 ]; then
        printf "Workflow started successfully!\n"

        # Wait for workflow to appear in list
        printf "Waiting for workflow to start...\n"
        sleep 5

        # Get the run ID of the latest workflow
        RUN_ID=$(gh run list --workflow "$WORKFLOW_NAME" --limit 1 --json databaseId --jq '.[0].databaseId')

        if [ ! -z "$RUN_ID" ]; then
            printf "Run ID: %s\n" "$RUN_ID"
            printf "Branch: %s\n" "$BRANCH"

            # Watch the run
            printf "Showing workflow progress...\n"
            gh run watch "$RUN_ID"

            # Show logs
            printf "\nShowing workflow logs...\n"
            gh run view "$RUN_ID" --log

            # Show final status
            gh run view "$RUN_ID"
        else
            printf "Failed to start workflow\n"
            exit 1
        fi
    else
        printf "Failed to start workflow\n"
        exit 1
    fi

}

ask_workflow_name() {
    # Ask for the workflow name
    printf "\033[1;33mSelect from the available workflows or Enter the workflow name:\033[0m\n"
    printf "1. run_use_platform_support_frontend_service_coveo_api_scale.yaml\n"
    printf "2. run_use_platform_support_frontend_service_feedback_api_scale.yaml\n"
    printf "3. run_use_support_case_services_api_scale.yaml\n"
    printf "4. Enter workflow name\n"
    printf "Enter your choice: "
    read -r choice

    case $choice in
        1)
            WORKFLOW_NAME="run_use_platform_support_frontend_service_coveo_api_scale.yaml"
            ;;
        2)
            WORKFLOW_NAME="run_use_platform_support_frontend_service_feedback_api_scale.yaml"
            ;;
        3)
            WORKFLOW_NAME="run_use_support_case_services_api_scale.yaml"
            ;;
        4)
            # Ask for the workflow name
            printf "Enter workflow name: "
            read -r choice
            if [ -z "$choice" ]; then
                printf "No input received, exiting...\n"
                exit 1
            fi
            # Validate the workflow name
            if [[ ! $choice =~ ^run_.*\.yaml$ ]]; then
                printf "Invalid workflow name format. Exiting...\n"
                exit 1
            fi
            ;;
        *)
            WORKFLOW_NAME="$choice"
            ;;
    esac
}

get_branch_inputs() {
    # Get the current branch or ask for it
    BRANCH=$(get_current_branch)

    # Prompt the user to confirm or enter a different branch
    printf "\033[1;34mPlease enter the following required values:\033[0m\n"
    printf "\033[1;33mPress Enter to use \"%s\" branch or type a different branch name: \033[0m" "$BRANCH"
    read -r user_input

    # If the user presses Enter, keep the current branch
    if [ -n "$user_input" ]; then
        BRANCH="$user_input"
    fi
}
get_inputs() {

    get_branch_inputs
     # Fetch the version
    echo "Fetching version..."
    version=$(get_version)
    if [ $? -ne 0 ] || [ -z "$version" ]; then
        echo "Failed to fetch version automatically. Please enter the version manually."
        version=$(get_input "$(printf "\033[1;33mEnter version\033[0m")")
    fi

    # Prompt the user to confirm or enter a different version
    printf "\033[1;33mPress Enter to use \"%s\" version or type a different version: \033[0m" "$version"
    read -r use_different_version
    if [ -n "$use_different_version" ]; then
        version="$use_different_version"
    fi

    # If version is still empty, prompt the user again
    if [ -z "$version" ]; then
        printf "Version is required. Exiting...\n"
        exit 1
    fi

    VERSION="$version"
    printf "\033[1;36mVersion:\033[0m %s\n" "$VERSION"
    REPLICAS=$(get_input "$(printf "\033[1;33mEnter number of replicas\033[0m")")
    NUM_USERS=$(get_input "$(printf "\033[1;33mEnter number of users\033[0m")")
    SPAWN_RATE=$(get_input "$(printf "\033[1;33mEnter spawn rate\033[0m")")
    TEST_DURATION=$(get_input "$(printf "\033[1;33mEnter test duration in seconds\033[0m")")

    # Confirm parameters
    printf "\n\033[1;32mWorkflow will run with these parameters:\033[0m\n"
    printf "\033[1;36mBranch:\033[0m %s\n" "$BRANCH"
    printf "\033[1;36mWorkflow Name:\033[0m %s\n" "$WORKFLOW_NAME"
    printf "\033[1;36mVersion:\033[0m %s\n" "$VERSION"
    printf "\033[1;36mReplicas:\033[0m %s\n" "$REPLICAS"
    printf "\033[1;36mNumber of Users:\033[0m %s\n" "$NUM_USERS"
    printf "\033[1;36mSpawn Rate:\033[0m %s\n" "$SPAWN_RATE"
    printf "\033[1;36mTest Duration:\033[0m %s\n" "$TEST_DURATION"
    printf "\n\033[1;33mDo you want to proceed with these parameters? (y/N): \033[0m"
    read -r proceed
    if [[ $proceed =~ ^[Nn]$ ]]; then
        printf "Exiting...\n"
        exit 0
    fi
}

get_deployments_and_pods() {
    printf "\033[1;33mSelect from the available services or Enter the service name\033[0m\n"
    printf "\033[1;33mPlease enter service name as all if you want to get all deployments and pods\033[0m\n"
    choose_service_name

    printf "Fetching deployments and pods information for service: %s...\n" "$service_name"

    # Run the workflow to get deployments and pods
    gh workflow run get_deployments_and_pods.yaml

    if [ $? -eq 0 ]; then
        printf "Workflow started successfully!\n"

        # Wait for workflow to appear in list
        printf "Waiting for workflow to start...\n"
        sleep 5

        # Get the run ID of the latest workflow
        RUN_ID=$(gh run list --workflow get_deployments_and_pods.yaml --limit 1 --json databaseId --jq '.[0].databaseId')

        if [ ! -z "$RUN_ID" ]; then
            printf "Run ID: %s\n" "$RUN_ID"

            # Watch the run
            printf "Showing workflow progress...\n"
            gh run watch "$RUN_ID"

            # Show logs
            printf "\nShowing workflow logs...\n"
            if [ "$service_name" == "all" ]; then
                gh run view "$RUN_ID" --log
            else
                gh run view "$RUN_ID" --log | grep "$service_name"
            fi
        else
            printf "Failed to start workflow\n"
            exit 1
        fi
    else
        printf "Failed to start workflow\n"
        exit 1
    fi

    exit 0
}
show_menu() {
    printf "Please select an option:\n"
    printf "1. Run Performance Test\n"
    printf "2. Watch Service Logs\n"
    printf "3. Stop Performance Test\n"
    printf "4. Get Deployments and Pods\n"
    printf "5. Exit\n"
    read -p "Enter your choice: " choice

    case $choice in
        1)  
            ask_workflow_name
            get_inputs
            run_workflow
            ;;
        2)
            watch_service_logs
            ;;
        3) 
            ask_workflow_name
            get_branch_inputs
            VERSION=$(get_input "$(printf "\033[1;33mEnter version\033[0m")")
            REPLICAS="0"
            NUM_USERS="1"
            SPAWN_RATE="1"
            TEST_DURATION="1"
            # Confirm parameters
            printf "\n\033[1;32mStopping workflow with these parameters:\033[0m\n"
            printf "\033[1;36mBranch:\033[0m %s\n" "$BRANCH"
            printf "\033[1;36mWorkflow Name:\033[0m %s\n" "$WORKFLOW_NAME"
            printf "\033[1;36mVersion:\033[0m %s\n" "$VERSION"
            printf "\033[1;36mReplicas:\033[0m %s\n" "$REPLICAS"
            printf "\033[1;36mNumber of Users:\033[0m %s\n" "$NUM_USERS"
            printf "\033[1;36mSpawn Rate:\033[0m %s\n" "$SPAWN_RATE"
            printf "\033[1;36mTest Duration:\033[0m %s\n" "$TEST_DURATION"
            printf "\n\033[1;33mDo you want to proceed with these parameters? (y/N): \033[0m"

            read -r proceed
            if [[ $proceed =~ ^[Nn]$ ]]; then
            printf "Exiting...\n"
            exit 0
            fi
            
            run_workflow

            printf "\033[1;32mPerformance test stopped.\033[0m\n"
            exit 0
            ;;
        4)
            get_deployments_and_pods
            ;;
        5)
            printf "Exiting...\n"
            exit 0
            ;;
        *)
            printf "Invalid choice. Please try again.\n"
            show_menu
            ;;
    esac
}

# Check for gh CLI
check_gh

while true; do
    show_menu
done

