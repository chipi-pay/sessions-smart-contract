# Session Key Integration Guide

This guide explains how session key validation works and how to integrate it with the account's `__validate__` method.

## Current Implementation Status

### ✅ Completed Components

1. **Session Data Storage**: Session keys are stored with their permissions (expiration, call limits, allowed entrypoints)
2. **Session Management Functions**: 
   - `add_or_update_session_key()` - Add or update a session key
   - `revoke_session_key()` - Revoke a session key
   - `get_session_data()` - Query session key data
3. **Session Validation Logic**: `_validate_session()` internal function that checks:
   - Session expiration timestamp
   - Call count limits
   - Allowed entrypoint restrictions

### 🔄 Integration with `__validate__`

The OpenZeppelin AccountComponent in v2.0.0 provides the standard account validation. To integrate session keys, you have two main approaches:

#### Approach 1: Custom Validation Wrapper (Recommended)

Override or wrap the validation to check for session key signatures:

```cairo
// In your contract implementation
fn __validate__(self: @ContractState, calls: Array<Call>) -> felt252 {
    // Try standard owner validation first
    let owner_validation = self.account.__validate__(calls);
    
    // If owner validation succeeds, return
    if owner_validation == starknet::VALIDATED {
        return owner_validation;
    }
    
    // Otherwise, try session key validation
    // Extract session key from transaction signature
    // Validate against stored session data
    // Check entrypoint permissions
    
    // Pseudo-code for session key validation:
    // let tx_info = get_tx_info();
    // let session_key = extract_session_key_from_signature(tx_info.signature);
    // let call_selector = calls[0].selector;  // Simplified for first call
    // 
    // if self._validate_session(session_key, call_selector) {
    //     return starknet::VALIDATED;
    // }
    
    return 'INVALID';
}
```

#### Approach 2: Outside Execution Pattern

Use session keys with the outside execution pattern:

1. Session key holder creates a signed message
2. Message includes the calls to execute
3. Account contract validates the session key signature
4. If valid and within permissions, execute the calls

This approach works well with the SRC-9 component (if available in your OpenZeppelin version).

## Signature Format for Session Keys

When using session keys, the transaction signature should include:

1. **Session Key Identifier** (felt252): The session key that signed the transaction
2. **Session Signature** (r, s): ECDSA signature from the session key
3. **Call Data**: The function selector and parameters being called

Example signature structure:
```
[session_key_id, signature_r, signature_s, ...]
```

## Validation Flow

```
Transaction Received
    │
    ├─> Try Owner Validation (AccountComponent)
    │   └─> Success? ✓ Execute
    │
    └─> Try Session Key Validation
        │
        ├─> Extract session_key from signature
        ├─> Read session data from storage
        ├─> Check expiration (block_timestamp <= valid_until)
        ├─> Check call limit (calls_used < max_calls)
        ├─> Check entrypoint (is selector allowed?)
        │
        ├─> All checks pass? 
        │   ├─> Increment calls_used
        │   └─> Return VALIDATED ✓
        │
        └─> Any check fails?
            └─> Return INVALID ✗
```

## Implementation Steps

### Step 1: Understand OpenZeppelin v2.0.0 Account Validation

Review the AccountComponent source to understand:
- How `__validate__` is implemented
- How signatures are verified
- How to safely override or extend validation

### Step 2: Implement Custom Validation

Create a custom validation function that:
1. First tries owner validation (preserve existing security)
2. Falls back to session key validation
3. Properly verifies session key signatures
4. Calls `_validate_session()` for permission checks

### Step 3: Add Signature Parsing

Implement logic to:
- Detect if signature is from owner or session key
- Extract session key identifier from signature
- Verify the cryptographic signature against the session key

### Step 4: Testing

Test scenarios:
1. Owner can still execute all transactions
2. Valid session key can execute allowed transactions
3. Expired session key is rejected
4. Session key with exceeded call limit is rejected
5. Session key cannot call restricted entrypoints
6. Revoked session key is rejected

## Security Considerations

1. **Owner Authority**: Owner validation must always work, even if session key logic fails
2. **Signature Verification**: Properly verify cryptographic signatures for session keys
3. **Replay Protection**: Use nonces or transaction hashes to prevent replay attacks
4. **Entrypoint Safety**: Be careful with wildcard entrypoint permissions (empty array)
5. **Time Synchronization**: Ensure block timestamp is a reliable expiration mechanism
6. **Call Counting**: Atomically increment call counter to prevent race conditions

## Example Usage

Once integrated, a session key transaction flow would be:

```bash
# 1. Owner adds session key
starkli invoke $ACCOUNT add_or_update_session_key \
    $SESSION_KEY_ID \
    $EXPIRATION \
    $MAX_CALLS \
    [$SELECTOR1, $SELECTOR2]

# 2. Session key holder signs and sends transaction
# (Using custom signing tool that creates session key signatures)
custom-session-signer \
    --account $ACCOUNT \
    --session-key $SESSION_KEY_PRIVATE \
    --session-id $SESSION_KEY_ID \
    --call transfer \
    --args $RECIPIENT $AMOUNT

# 3. Account validates:
#    - Checks session key signature ✓
#    - Checks expiration ✓
#    - Checks call limit ✓
#    - Checks 'transfer' in allowed entrypoints ✓
#    - Increments call counter
#    - Executes transaction ✓
```

## Next Steps for Full Integration

1. **Study OpenZeppelin v2.0.0 Account Component**
   - Review the validation implementation
   - Understand how to safely extend it

2. **Implement Signature Handling**
   - Create session key signature format
   - Implement signature verification

3. **Override/Extend `__validate__`**
   - Integrate session key validation path
   - Maintain backward compatibility with owner validation

4. **Create Signing Tools**
   - Build tools to create session key signatures
   - Update deployment and testing scripts

5. **Comprehensive Testing**
   - Unit tests for all validation paths
   - Integration tests with real transactions
   - Security audit

## Resources

- [OpenZeppelin Cairo Contracts v2.0.0](https://github.com/OpenZeppelin/cairo-contracts/tree/v2.0.0)
- [Starknet Account Abstraction](https://docs.starknet.io/documentation/architecture_and_concepts/Accounts/introduction/)
- [Cairo Book - Smart Contracts](https://book.cairo-lang.org/ch99-01-02-a-simple-contract.html)

