#!/bin/bash

# Deployment script for Session Key Account Contract
# Make sure you have starkli installed and configured

set -e

echo "=== Session Key Account Deployment ==="
echo ""

# Configuration
NETWORK=${NETWORK:-"sepolia"}
OWNER_PUBLIC_KEY=${OWNER_PUBLIC_KEY:-""}

if [ -z "$OWNER_PUBLIC_KEY" ]; then
    echo "Error: OWNER_PUBLIC_KEY environment variable must be set"
    echo "Usage: OWNER_PUBLIC_KEY=0x... ./scripts/deploy.sh"
    exit 1
fi

echo "Network: $NETWORK"
echo "Owner Public Key: $OWNER_PUBLIC_KEY"
echo ""

# Step 1: Declare the contract
echo "Step 1: Declaring contract..."
CLASS_HASH=$(starkli declare target/dev/sessions_smart_contract_Account.contract_class.json --network $NETWORK 2>&1 | grep -o '0x[0-9a-fA-F]*' | head -1)

if [ -z "$CLASS_HASH" ]; then
    echo "Error: Failed to declare contract"
    exit 1
fi

echo "✓ Contract declared with class hash: $CLASS_HASH"
echo ""

# Step 2: Deploy the contract
echo "Step 2: Deploying contract..."
DEPLOY_OUTPUT=$(starkli deploy $CLASS_HASH $OWNER_PUBLIC_KEY --network $NETWORK 2>&1)
ACCOUNT_ADDRESS=$(echo "$DEPLOY_OUTPUT" | grep -o '0x[0-9a-fA-F]*' | head -1)

if [ -z "$ACCOUNT_ADDRESS" ]; then
    echo "Error: Failed to deploy contract"
    echo "$DEPLOY_OUTPUT"
    exit 1
fi

echo "✓ Contract deployed at: $ACCOUNT_ADDRESS"
echo ""

echo "=== Deployment Complete ==="
echo ""
echo "Save these values:"
echo "  CLASS_HASH=$CLASS_HASH"
echo "  ACCOUNT_ADDRESS=$ACCOUNT_ADDRESS"
echo ""
echo "Next steps:"
echo "  1. Fund the account: starkli invoke <ETH_CONTRACT> transfer $ACCOUNT_ADDRESS <AMOUNT>"
echo "  2. Add session keys using the session management functions"
echo ""

