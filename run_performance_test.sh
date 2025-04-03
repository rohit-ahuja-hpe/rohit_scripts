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

# Function to continuously watch service logs
watch_service_logs() {
    local service_name="use-platform-support-frontend-service-coveo"
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
    gh workflow run "run_use_platform_support_frontend_service_coveo_api_scale.yaml" \
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
        RUN_ID=$(gh run list --workflow "run_use_platform_support_frontend_service_coveo_api_scale.yaml" --limit 1 --json databaseId --jq '.[0].databaseId')

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

            # Start continuous log monitoring
            printf "\nStarting continuous log monitoring...\n"
            watch_service_logs
        else
            printf "Could not get run ID. Please check the workflow status manually.\n"
        fi
    else
        printf "Failed to start workflow\n"
        exit 1
    fi
}

# Check for gh CLI
check_gh

# Get the current branch or ask for it
BRANCH=$(get_current_branch)

# Confirm branch or ask for a different one
printf "Please enter the following required values:\n"
read -p "Do you want to use "$BRANCH" branch? (y/N): " use_different_branch
if [[ $use_different_branch =~ ^[Nn]$ ]]; then
    BRANCH=$(get_input "Enter branch name")
fi

# Get all required inputs
VERSION=$(get_input "Enter version")
REPLICAS=$(get_input "Enter number of replicas")
NUM_USERS=$(get_input "Enter number of users")
SPAWN_RATE=$(get_input "Enter spawn rate")
TEST_DURATION=$(get_input "Enter test duration in seconds")

# Confirm parameters
printf "\nWorkflow will run with these parameters:\n"
printf "Branch: %s\n" "$BRANCH"
printf "Version: %s\n" "$VERSION"
printf "Replicas: %s\n" "$REPLICAS"
printf "Number of Users: %s\n" "$NUM_USERS"
printf "Spawn Rate: %s\n" "$SPAWN_RATE"
printf "Test Duration: %s\n" "$TEST_DURATION"

read -p "Continue? (y/N): " confirm
if [[ $confirm =~ ^[Yy]$ ]]; then
    run_workflow
else
    printf "Cancelled\n"
    exit 0
fi