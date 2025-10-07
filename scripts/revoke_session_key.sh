#!/bin/bash

# Script to revoke a session key from the account
# Make sure you have starkli installed and configured

set -e

ACCOUNT_ADDRESS=${ACCOUNT_ADDRESS:-""}
SESSION_KEY=${SESSION_KEY:-""}

if [ -z "$ACCOUNT_ADDRESS" ] || [ -z "$SESSION_KEY" ]; then
    echo "Error: Required environment variables not set"
    echo "Usage: ACCOUNT_ADDRESS=0x... SESSION_KEY=0x... ./scripts/revoke_session_key.sh"
    exit 1
fi

echo "=== Revoking Session Key ==="
echo "Account: $ACCOUNT_ADDRESS"
echo "Session Key: $SESSION_KEY"
echo ""

# Note: This needs to be called by the account owner
echo "Calling revoke_session_key..."
starkli invoke $ACCOUNT_ADDRESS revoke_session_key $SESSION_KEY

echo ""
echo "✓ Session key revoked successfully!"
echo ""
echo "To verify, run:"
echo "  starkli call $ACCOUNT_ADDRESS get_session_data $SESSION_KEY"

