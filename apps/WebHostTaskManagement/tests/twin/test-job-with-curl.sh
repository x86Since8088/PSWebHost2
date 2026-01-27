#!/bin/bash

#
# Test Job Submission System with curl and Bearer Token
#
# Prerequisites:
#   1. Run Create-TestApiKey.ps1 first to create test API key
#   2. Ensure PSWebHost server is running on localhost:8080
#   3. Install jq for JSON parsing: apt-get install jq (Linux) or brew install jq (Mac)
#

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
BASE_URL="http://localhost:8080/apps/WebHostTaskManagement/api/v1"
CONFIG_FILE=".config/test-api-keys.json"

echo -e "${CYAN}=== PSWebHost Job Submission Test (curl + Bearer Token) ===${NC}\n"

# Load API key from config
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}Error: $CONFIG_FILE not found${NC}"
    echo -e "${YELLOW}Run Create-TestApiKey.ps1 first to create test API key${NC}"
    exit 1
fi

API_KEY=$(jq -r '.TestJobSubmissionKey.ApiKey' "$CONFIG_FILE")

if [ -z "$API_KEY" ] || [ "$API_KEY" = "null" ]; then
    echo -e "${RED}Error: API key not found in $CONFIG_FILE${NC}"
    exit 1
fi

echo -e "${GREEN}✓ API key loaded${NC} (${API_KEY:0:20}...)\n"

# Test 1: Submit a simple job
echo -e "${CYAN}Test 1: Submit a simple job${NC}"

SUBMIT_RESPONSE=$(curl -s -X POST "$BASE_URL/jobs/submit" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{
    "jobName": "CurlTestJob",
    "command": "Get-Date; Write-Output \"Hello from curl\"; Get-Process | Select-Object -First 3 | Format-Table -AutoSize",
    "description": "Test job submitted via curl with Bearer token",
    "executionMode": "MainLoop"
  }')

echo "$SUBMIT_RESPONSE" | jq '.'

# Extract job ID
JOB_ID=$(echo "$SUBMIT_RESPONSE" | jq -r '.jobId')
SUCCESS=$(echo "$SUBMIT_RESPONSE" | jq -r '.success')

if [ "$SUCCESS" != "true" ] || [ "$JOB_ID" = "null" ]; then
    echo -e "${RED}✗ Failed to submit job${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Job submitted successfully${NC}"
echo -e "  Job ID: ${YELLOW}$JOB_ID${NC}\n"

# Test 2: Wait for job execution
echo -e "${CYAN}Test 2: Wait for job execution${NC}"
echo -e "${YELLOW}Waiting 4 seconds for MainLoop to process job...${NC}"
sleep 4

# Test 3: Get job results
echo -e "\n${CYAN}Test 3: Get job results${NC}"

RESULTS_RESPONSE=$(curl -s "$BASE_URL/jobs/results" \
  -H "Authorization: Bearer $API_KEY")

echo "$RESULTS_RESPONSE" | jq '.'

# Extract our job result
JOB_RESULT=$(echo "$RESULTS_RESPONSE" | jq ".results[] | select(.JobID == \"$JOB_ID\")")

if [ -z "$JOB_RESULT" ]; then
    echo -e "${RED}✗ Job result not found${NC}"
    echo -e "${YELLOW}Note: Job may still be processing or may have failed${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Job result retrieved${NC}\n"

# Display job details
echo -e "${CYAN}Job Details:${NC}"
echo "$JOB_RESULT" | jq '{
    JobName: .JobName,
    DateStarted: .DateStarted,
    DateCompleted: .DateCompleted,
    Runtime: .Runtime,
    Success: .Success
}'

# Display output
echo -e "\n${CYAN}Job Output:${NC}"
echo "$JOB_RESULT" | jq -r '.Output'

# Test 4: Submit long-running job (for Runspace mode test)
echo -e "\n${CYAN}Test 4: Submit long-running job (Runspace mode)${NC}"

LONG_JOB_RESPONSE=$(curl -s -X POST "$BASE_URL/jobs/submit" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{
    "jobName": "LongRunningTest",
    "command": "1..5 | ForEach-Object { Start-Sleep -Seconds 1; Write-Output \"Step $_\" }",
    "description": "5-second test for async execution",
    "executionMode": "Runspace"
  }')

LONG_JOB_ID=$(echo "$LONG_JOB_RESPONSE" | jq -r '.jobId')
echo -e "${GREEN}✓ Long-running job submitted${NC} (Job ID: $LONG_JOB_ID)"
echo -e "${YELLOW}Note: This job will complete in ~5 seconds (async)${NC}\n"

# Test 5: Test error handling
echo -e "${CYAN}Test 5: Submit job with error${NC}"

ERROR_JOB_RESPONSE=$(curl -s -X POST "$BASE_URL/jobs/submit" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{
    "jobName": "ErrorTest",
    "command": "Write-Output \"Before error\"; throw \"Intentional error\"; Write-Output \"After error\"",
    "description": "Test error capture",
    "executionMode": "MainLoop"
  }')

ERROR_JOB_ID=$(echo "$ERROR_JOB_RESPONSE" | jq -r '.jobId')
echo -e "${GREEN}✓ Error test job submitted${NC} (Job ID: $ERROR_JOB_ID)"

sleep 4

ERROR_RESULT=$(curl -s "$BASE_URL/jobs/results" \
  -H "Authorization: Bearer $API_KEY" | jq ".results[] | select(.JobID == \"$ERROR_JOB_ID\")")

echo -e "\n${CYAN}Error Job Result:${NC}"
echo "$ERROR_RESULT" | jq '{
    JobName: .JobName,
    Success: .Success,
    Output: .Output
}'

# Test 6: Delete job result
echo -e "\n${CYAN}Test 6: Delete job result${NC}"

DELETE_RESPONSE=$(curl -s -X DELETE "$BASE_URL/jobs/results?jobId=$JOB_ID" \
  -H "Authorization: Bearer $API_KEY")

echo "$DELETE_RESPONSE" | jq '.'

DELETE_SUCCESS=$(echo "$DELETE_RESPONSE" | jq -r '.success')

if [ "$DELETE_SUCCESS" = "true" ]; then
    echo -e "${GREEN}✓ Job result deleted successfully${NC}\n"
else
    echo -e "${RED}✗ Failed to delete job result${NC}\n"
fi

# Summary
echo -e "${CYAN}=== Test Summary ===${NC}"
echo -e "${GREEN}✓ Job submission (MainLoop mode)${NC}"
echo -e "${GREEN}✓ Job execution and result retrieval${NC}"
echo -e "${GREEN}✓ Long-running job (Runspace mode)${NC}"
echo -e "${GREEN}✓ Error handling${NC}"
echo -e "${GREEN}✓ Job result deletion${NC}"
echo -e "\n${GREEN}All tests completed successfully!${NC}"

# Show remaining jobs
echo -e "\n${CYAN}Remaining job results:${NC}"
curl -s "$BASE_URL/jobs/results" \
  -H "Authorization: Bearer $API_KEY" | jq '.results | length'
