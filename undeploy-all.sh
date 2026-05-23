#!/bin/bash

# Exit on error
set -e

# Source environment variables
if [ -f "./env.sh" ]; then
  source ./env.sh
else
  echo "Error: env.sh file not found."
  exit 1
fi

if [ -z "$APIGEE_ORG" ] || [ -z "$APIGEE_ENV" ]; then
  echo "Error: Please set APIGEE_ORG and APIGEE_ENV in env.sh."
  exit 1
fi

# Check if apigeecli is installed
if ! command -v apigeecli &> /dev/null; then
    echo "apigeecli not found. Installing..."
    curl -s https://raw.githubusercontent.com/apigee/apigeecli/main/downloadLatest.sh | bash
    export PATH=$PATH:$HOME/.apigeecli/bin
fi

echo "============================================================"
echo "Deleting Client App: hotai-protected-app"
echo "============================================================"
# Fetch developer ID to use for app deletion if possible
DEV_ID=$(apigeecli developers get --email "developer@hotai.com" --org "$APIGEE_ORG" --default-token | jq -r '.developerId' 2>/dev/null || echo "")
if [ -n "$DEV_ID" ]; then
  apigeecli apps delete --name "hotai-protected-app" --id "$DEV_ID" --org "$APIGEE_ORG" --default-token || true
else
  apigeecli apps delete --name "hotai-protected-app" --org "$APIGEE_ORG" --default-token || true
fi

echo "============================================================"
echo "Deleting Developer: developer@hotai.com"
echo "============================================================"
apigeecli developers delete --email "developer@hotai.com" --org "$APIGEE_ORG" --default-token || true

echo "============================================================"
echo "Deleting API Product: hotai-protected-product"
echo "============================================================"
apigeecli products delete --name "hotai-protected-product" --org "$APIGEE_ORG" --default-token || true

PROXIES=("hotai-public" "hotai-single" "hotai-protected")

echo "============================================================"
echo "Undeploying and Deleting API Proxies"
echo "============================================================"

for PROXY in "${PROXIES[@]}"; do
  echo "Processing $PROXY..."
  
  echo "Undeploying $PROXY from $APIGEE_ENV..."
  apigeecli apis undeploy --name "$PROXY" --env "$APIGEE_ENV" --org "$APIGEE_ORG" --default-token || true
  
  echo "Deleting $PROXY..."
  apigeecli apis delete --name "$PROXY" --org "$APIGEE_ORG" --default-token || true
done

echo "Undeploy all completed."
