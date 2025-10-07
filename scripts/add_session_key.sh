#!/bin/bash

# Script to add a session key to the account
# Make sure you have starkli installed and configured

set -e

ACCOUNT_ADDRESS=${ACCOUNT_ADDRESS:-""}
SESSION_KEY=${SESSION_KEY:-""}
VALID_UNTIL=${VALID_UNTIL:-$(( $(date +%s) + 86400 ))}  # Default: 24 hours from now
MAX_CALLS=${MAX_CALLS:-"10"}
ENTRYPOINTS=${ENTRYPOINTS:-"[]"}  # Default: allow all entrypoints

if [ -z "$ACCOUNT_ADDRESS" ] || [ -z "$SESSION_KEY" ]; then
    echo "Error: Required environment variables not set"
    echo "Usage: ACCOUNT_ADDRESS=0x... SESSION_KEY=0x... ./scripts/add_session_key.sh"
    echo ""
    echo "Optional variables:"
    echo "  VALID_UNTIL=<timestamp>   (default: 24 hours from now)"
    echo "  MAX_CALLS=<number>        (default: 10)"
    echo "  ENTRYPOINTS=<array>       (default: [] for all entrypoints)"
    exit 1
fi

echo "=== Adding Session Key ==="
echo "Account: $ACCOUNT_ADDRESS"
echo "Session Key: $SESSION_KEY"
echo "Valid Until: $VALID_UNTIL ($(date -r $VALID_UNTIL 2>/dev/null || date -d @$VALID_UNTIL 2>/dev/null || echo 'N/A'))"
echo "Max Calls: $MAX_CALLS"
echo "Allowed Entrypoints: $ENTRYPOINTS"
echo ""

# Note: This needs to be called by the account owner
# You may need to adjust the invoke command based on your setup
echo "Calling add_or_update_session_key..."
starkli invoke $ACCOUNT_ADDRESS add_or_update_session_key \
    $SESSION_KEY \
    $VALID_UNTIL \
    $MAX_CALLS \
    "$ENTRYPOINTS"

echo ""
echo "✓ Session key added successfully!"
echo ""
echo "To verify, run:"
echo "  starkli call $ACCOUNT_ADDRESS get_session_data $SESSION_KEY"

