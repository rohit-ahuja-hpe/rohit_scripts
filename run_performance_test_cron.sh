#!/bin/bash

#echo "yourtoken" | /opt/homebrew/bin/gh auth login --with-token

# Function to check if gh CLI is installed
check_gh() {
    if ! command -v /opt/homebrew/bin/gh &> /dev/null; then
        printf "GitHub CLI (gh) is not installed. Please install it first.\n"
        exit 1
    fi

    # Check if authenticated
    if ! /opt/homebrew/bin/gh auth status &> /dev/null; then
        printf "Please authenticate with GitHub first using 'gh auth login'\n"
        exit 1
    fi
}

# Function to run workflow
run_workflow() {
    printf "Starting workflow on branch %s...\n" "$BRANCH"
    /opt/homebrew/bin/gh workflow run "$WORKFLOW_NAME" \
        --ref "$BRANCH" \
        -f version="$VERSION" \
        -f replicas="$REPLICAS" \
        -f num_users="$NUM_USERS" \
        -f spawn_rate="$SPAWN_RATE" \
        -f test_duration="$TEST_DURATION"

    if [ $? -eq 0 ]; then
        printf "Workflow started successfully!\n"
    else
        printf "Failed to start workflow\n"
        exit 1
    fi
}

# Function to start performance test
start_performance_test() {
    BRANCH=$1
    WORKFLOW_NAME=$2
    VERSION=$3
    REPLICAS=$4
    NUM_USERS=$5
    SPAWN_RATE=$6
    TEST_DURATION=$7

    printf "Starting performance test with the following parameters:\n"
    printf "Branch: %s\nWorkflow Name: %s\nVersion: %s\nReplicas: %s\nNumber of Users: %s\nSpawn Rate: %s\nTest Duration: %s\n" \
        "$BRANCH" "$WORKFLOW_NAME" "$VERSION" "$REPLICAS" "$NUM_USERS" "$SPAWN_RATE" "$TEST_DURATION"

    run_workflow
}

# Function to stop performance test
stop_performance_test() {
    BRANCH=$1
    WORKFLOW_NAME=$2
    VERSION=$3

    printf "Stopping performance test with the following parameters:\n"

    REPLICAS="0"
    NUM_USERS="1"
    SPAWN_RATE="1"
    TEST_DURATION="1"
     printf "Branch: %s\nWorkflow Name: %s\nVersion: %s\nReplicas: %s\nNumber of Users: %s\nSpawn Rate: %s\nTest Duration: %s\n" \
        "$BRANCH" "$WORKFLOW_NAME" "$VERSION" "$REPLICAS" "$NUM_USERS" "$SPAWN_RATE" "$TEST_DURATION"

    run_workflow
}

# Check for gh CLI
check_gh

# Main script logic
ACTION=$1
shift

if [ "$ACTION" == "start" ]; then
    start_performance_test "$@"
elif [ "$ACTION" == "stop" ]; then
    stop_performance_test "$@"
else
    printf "Invalid action. Use 'start' or 'stop'.\n"
    exit 1
fi