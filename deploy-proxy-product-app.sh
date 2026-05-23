#!/bin/bash

# Exit on error
set -e

# Source environment variables
if [ -f "./env.sh" ]; then
  source ./env.sh
else
  echo "Error: env.sh file not found."
  echo "Please create an env.sh file with the following content:"
  echo "export APIGEE_ORG=\"your-gcp-project-id\""
  echo "export APIGEE_ENV=\"your-apigee-env-name\""
  exit 1
fi

if [ -z "$APIGEE_ORG" ] || [ -z "$APIGEE_ENV" ]; then
  echo "Error: Please set APIGEE_ORG and APIGEE_ENV in env.sh."
  exit 1
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed. Please install jq."
    exit 1
fi

# Check if apigeecli is installed
if ! command -v apigeecli &> /dev/null; then
    echo "apigeecli not found. Installing..."
    curl -s https://raw.githubusercontent.com/apigee/apigeecli/main/downloadLatest.sh | bash
    export PATH=$PATH:$HOME/.apigeecli/bin
fi

PROXIES=("hotai-public" "hotai-single" "hotai-protected")

echo "============================================================"
echo "Deploying API Proxies"
echo "Org: $APIGEE_ORG"
echo "Env: $APIGEE_ENV"
echo "============================================================"

for PROXY in "${PROXIES[@]}"; do
  echo "Processing $PROXY..."
  if [ -d "./$PROXY" ]; then
    echo "Creating API Proxy bundle for $PROXY..."
    
    # Pass the actual apiproxy folder to apigeecli
    REV=$(apigeecli apis create bundle -f "./$PROXY/apiproxy" -n "$PROXY" --org "$APIGEE_ORG" --default-token --disable-check | jq -r '.revision')
    
    if [ -z "$REV" ] || [ "$REV" == "null" ]; then
      echo "Error: Failed to create bundle or extract revision for $PROXY."
      exit 1
    fi
    
    echo "Deploying revision $REV of $PROXY..."
    apigeecli apis deploy --wait --name "$PROXY" --ovr --rev "$REV" --org "$APIGEE_ORG" --env "$APIGEE_ENV" --default-token
  else
    echo "Warning: Directory ./$PROXY not found. Skipping."
  fi
done

echo "============================================================"
echo "Creating API Product: hotai-protected-product"
echo "============================================================"

# Create product config JSON
cat <<EOF > product.json
{
  "operationConfigs": [
    {
      "apiSource": "hotai-protected",
      "operations": [
        {
          "resource": "/",
          "methods": [
            "GET"
          ]
        }
      ]
    },
    {
      "apiSource": "hotai-single",
      "operations": [
        {
          "resource": "/",
          "methods": [
            "GET"
          ]
        }
      ]
    }
  ],
  "operationConfigType": "proxy"
}
EOF

# Create product using --opgrp flag and required flags
apigeecli products create \
  --name "hotai-protected-product" \
  --display-name "hotai-protected-product" \
  --opgrp product.json \
  --envs "$APIGEE_ENV" \
  --approval auto \
  --org "$APIGEE_ORG" \
  --default-token

# Clean up product.json
rm product.json

echo "============================================================"
echo "Creating Developer: developer@hotai.com"
echo "============================================================"

apigeecli developers create \
  --email "developer@hotai.com" \
  --first "Hotai" \
  --last "Developer" \
  --user "hotaidev" \
  --org "$APIGEE_ORG" \
  --default-token

echo "============================================================"
echo "Creating Client App: hotai-protected-app"
echo "============================================================"

# Create app and capture output
APP_OUTPUT=$(apigeecli apps create \
  --name "hotai-protected-app" \
  --email "developer@hotai.com" \
  --prods "hotai-protected-product" \
  --org "$APIGEE_ORG" \
  --default-token)

echo "============================================================"
echo "Generated API Key"
echo "============================================================"

# Extract API Key
API_KEY=$(echo "$APP_OUTPUT" | jq -r '.credentials[0].consumerKey')

echo "API Key: $API_KEY"
