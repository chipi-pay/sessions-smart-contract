# Starknet Session Account

A Cairo smart contract that extends OpenZeppelin's account standard with session key functionality, enabling temporary, restricted access delegation on Starknet.

## 🚀 Deployed Contract

**Starknet Mainnet (Production Version v23 - SNIP-9 Compatible):**
- **Class Hash**: `0x00cd7618e5f407ad85458398815cf47dd63f06cd5249733e2bf987d13823f2e9`
- **Transaction Hash**: `0x03a69f9011522c301159ee6c8ecbe54c85536882581dce87f46ab5516fd81a00`
- **Test Instance**: `0x74dfd305e27e8365979ab327f1a1ba8a1d23af47b10fb5190f2118973549c20`
- **Network**: Starknet Mainnet
- **Compiler**: Cairo 2.11.4
- **SNIP-9**: v2 Compatible ✅
- **Paymaster**: Supported ✅
- **Deployed**: October 16, 2025

**Test Results** (Mainnet Integration Tests):
- ✅ Owner Signature (2 elements): [TX](https://starkscan.co/tx/0x28790c854466656bb87cd25fb704d6f55a386d08fec8a58131d50dfae340eb5)
- ✅ Session Signature (4 elements): [TX](https://starkscan.co/tx/0x38ece01cc093fde34d53f95b78b1fc2cfe55c1dfc937c2e17055aebfa31a779)
- ✅ Session Keys: Add, retrieve, validate working
- ✅ SNIP-9 v2: Verified on-chain

**Previous Production Version (v22):**
- **Class Hash**: `0x00097c307b5e2869713d376309a4e43028b6ef17061499022103304b482c7298`
- **Contract Address**: `0x01821ff8d12daa4f4406daea573a0f7bcba8aae62b90632384176a6b780c15fd`
- **Reference Implementation**: `0x01b0b06255f6960219dc358114779fda563c3b817d2df3fbd214e67c3572fd7f`
- **Deployed**: January 11, 2025

**Starknet Mainnet (Debug Version - FOR DEBUGGING ONLY):**
- **Class Hash**: `0x052458a2546699d1c175eccc31ac8ff6ccfa284ab7c7c384d37ceaf96abf4cb0`
- **Contract Address**: `0x06573411e4181fb6b43e2800fb8f2936bbe592f925c7c66e04858565f23a2b25`
- **Network**: Starknet Mainnet
- **Compiler**: Cairo 2.11.4
- **Deployed**: January 11, 2025
- **Source**: `src/debug_account.cairo` (separate from main production contract)

> ⚠️ **CRITICAL WARNING**: The debug version contains `compute_session_message_hash_offchain` and `debug_validate_session_signature` functions that allow forced nonce and chain_id parameters. **DO NOT USE IN PRODUCTION** as this creates serious security vulnerabilities including replay attacks and cross-chain replay attacks. Use only for debugging and testing purposes.

> ⚠️ **Note**: The reference implementation is provided as an example. For production use, deploy your own instance with your owner's public key.

### What's New in This Version (v23 - SNIP-9 Compatible)

🚀 **SNIP-9 v2 (Outside Execution) Support** - Full Paymaster compatibility:
- **Added SRC9Component**: OpenZeppelin's Outside Execution implementation integrated
- **execute_from_outside**: Enables meta-transactions and sponsored gas fees
- **get_snip9_version()**: Returns 2 for SNIP-9 v2 compatibility verification
- **Paymaster Ready**: Works with all Paymaster services (AVNU, Nimbora, etc.)
- **Session + Paymaster**: Users can execute transactions with $0 in wallet while backend sponsors gas
- **Production Safe**: Zero debug vulnerabilities, all production-grade security maintained
- **Backward Compatible**: All existing session key functionality preserved
- **Documentation**: Complete SNIP-9 usage guide, deployment instructions, and security comparison

🔒 **Security Enhancements**:
- Verified compatible with [Starknet.js Outside Execution](https://starknetjs.com/docs/guides/outsideExecution)
- Verified compatible with [Starknet.js Paymaster](https://starknetjs.com/docs/guides/paymaster)
- No debug functions in production contract
- Uses real transaction info for all validations
- Protected session management with assert_only_self

✅ **Testing**:
- All 18 tests passing (15 original + 3 new SNIP-9 tests)
- SNIP-9 compatibility verified
- Paymaster integration tested
- Session + Outside Execution combination validated

### Previous Version Features (v22 - Production Secure)

🔒 **Enhanced Security Architecture** - Implemented improved validation flow with better security guarantees:
- **Pure Validation First**: Added `_is_session_allowed_for_calls()` for non-mutating validation checks
- **Secure Counter Management**: Added `_consume_session_call()` that only increments after successful signature verification
- **Improved Validation Flow**: Session validation now uses pure checks before signature verification
- **Security Enhancement**: Counter only increments after valid signature verification, preventing state corruption
- **All Tests Passing**: 15/15 tests pass with enhanced security
- **Production Ready**: Secure contract deployed and verified on Starkscan

🔧 **Fixed Session Validation for Zero Entrypoints** - Resolved critical bug where sessions with `allowed_entrypoints_len = 0` were being rejected:
- **Problem**: Sessions created with no entrypoint restrictions (`allowed_entrypoints_len = 0`) were failing validation
- **Root Cause**: The deployed contract's validation logic wasn't properly handling the "allow all entrypoints" case
- **Solution**: Deployed new contract with corrected validation logic that properly allows all entrypoints when `allowed_entrypoints_len = 0`
- **Impact**: Sessions can now be created with no restrictions and will work correctly for any function call

🔍 **Enhanced Production Functions** - Added safe debugging tools and standard compatibility:
- **New Function**: `compute_session_message_hash()` - Returns exact hash the contract computes (uses real tx_info, safe)
- **New Function**: `is_valid_signature()` - ERC-1271 compatible signature validation for external contracts
- **New Functions**: `get_session_allowed_entrypoints_len()` and `get_session_allowed_entrypoint_at()` - Read-only session inspection
- **New Function**: Added `get_contract_info()` for version tracking and contract identification
- **Backward Compatible**: No breaking changes to existing functionality

### Previous Version Features (v17 - Security Hardening Fix)

🔒 **Fixed Critical Security Vulnerability** - Resolved potential bypass vulnerability in empty signature handling:
- **Problem**: Empty signatures were accepted without proper caller validation, potentially allowing external bypass
- **Root Cause**: Missing caller validation for empty signatures in `__validate__` function
- **Solution**: Added caller validation to ensure empty signatures only accepted for legitimate self-calls
- **Security Enhancement**: External callers can no longer use empty signatures to bypass validation
- **Zero Impact**: Owner and session signatures work exactly as before
- **All Tests Passing**: 15/15 tests still pass with enhanced security

### Previous Version Features (v16 - Session Validation Fix)

🔧 **Fixed Session Key Existence Validation** - Resolved critical security issue where non-existent session keys could be used for transactions:
- **Problem**: Session keys that were never added to the contract could still pass validation
- **Root Cause**: Default storage values (all zeros) passed validation checks incorrectly
- **Solution**: Added session existence check (`valid_until > 0`) in `_validate_session_for_calls`
- **Security Enhancement**: Only properly added session keys can now be used for transactions
- **All Tests Passing**: 15/15 tests still pass with improved validation
- **Minimal Change**: Only adds missing existence check without affecting other functionality

### Previous Version Features (v15 - Tx V3 & Name Shadowing Fix)

🚀 **Tx V3 Compatibility** - Updated `__validate__` function for optimal transaction version 3 support:
- **Removed nonce parameter** - Simplified function signature for better compatibility
- **Enhanced validation flow** - Improved comments and structure for clarity
- **Self-call optimization** - "Self-calls routed via __execute__ carry no tx signature"
- **Owner path delegation** - "2-elt signature → delegate to OZ (handles tx v3 hashing)"
- **Session path clarity** - "4-elt signature [session_pubkey, r, s, valid_until]"
- **Frontend matching** - "Match the front-end's poseidon message layout"

🔧 **Fixed Name Shadowing** - Resolved potential recursion issues in external session functions:
- **Explicit impl calls** - External functions now call `SessionKeyManagerImpl::` methods
- **No more recursion** - Prevents accidental self-calls in external entry points
- **Cleaner architecture** - Clear separation between external and internal implementations
- **All session functions** - Applied to `add_or_update_session_key`, `revoke_session_key`, `get_session_data`

🔧 **Fixed Self-Call Handling** - Resolved "Account: unauthorized" errors for internal function calls:
- **Proper caller validation** - Now checks both signature length AND caller address for self-calls
- **Self-call support** - Account can now call its own functions through `__execute__` without validation errors
- **Enhanced security** - Only allows self-calls when caller is the account itself AND signature is empty

✨ **Fixed Session Functions ABI** - Resolved session functions not being exposed as external entry points:
- **Fixed ABI compilation issue** - Session functions now properly exposed as external entry points
- **All session functions callable** - `add_or_update_session_key`, `get_session_data`, `revoke_session_key`
- **Resolves frontend integration issues** - Functions now discoverable in contract ABI
- **Verified functionality** - All session operations tested and working
- **Production ready** - Session functions confirmed working in deployed contract

✨ **Fixed Session Message Hash** - Corrected `_session_message_hash` to match frontend computation:
- **Fixed hash computation order** - Now matches frontend exactly
- **Added missing nonce** - Includes transaction nonce in hash
- **Added calldata length** - Includes calldata length before elements
- **Uses contract address** - Uses `get_contract_address()` instead of `transaction_hash`
- **Resolves "Account: unauthorized" errors** for session key transactions

🔧 **Frontend Nonce Management Fix** - Resolved "Invalid transaction nonce: undefined" errors:
- **Starknet.js 7.x Bug** - Library reports incorrect nonce values
- **Force Nonce Increment** - Workaround: increment reported nonce by 1
- **Known Issue** - This is a documented bug in Starknet.js 7.x versions
- **Production Solution** - Always fetch fresh nonce before transactions
- **Alternative Methods Failed** - Manual construction, different RPCs, raw fetch all had same issue
- **Perfect frontend compatibility** - Hash computation now identical

✨ **Enhanced Validation Logic** - Improved `__validate__` function with better error handling:
- Enhanced comments and documentation for each validation path
- Explicit rejection of invalid signature lengths (1, 3, 5+, etc.)
- **Improved debugging** with clearer validation flow
- **Resolves all "Account: unauthorized" issues** for proper usage patterns
- Maintains all security guarantees with comprehensive validation

✨ **Self-Call Support** - Fixed "Account: unauthorized" errors for internal calls:
- Added proper handling for self-calls (when account calls itself through `__execute__`)
- Empty signatures now accepted for internal account operations
- **Resolves frontend integration issues** with session key management
- Maintains all security guarantees with `assert_only_self()` protection
- **All 15 tests passing** including comprehensive validation scenarios

✨ **OpenZeppelin V3 Transaction Validation** - Owner validation delegates to OZ component:
- Owner signatures (2-element) use `self.account.validate_transaction()`
- Delegates to OpenZeppelin's AccountComponent for proper V3 tx hash computation
- **100% compatible with starknet.js, Argent, Braavos, and all standard wallets**
- Handles fee estimation vs execution hash differences automatically
- Session key validation (4-element) remains unchanged with custom logic
- `__validate_deploy__` and `__validate_declare__` also use OZ validation

### Previous Version Features

✨ **Predictable Session Signatures** - Fixed the chicken-and-egg problem! Session signatures now use only values known *before* transaction submission:
- Uses `account_address`, `chain_id`, `nonce`, `valid_until`, and call data
- **No longer requires `transaction_hash`** (which was unknown pre-submission)
- Enables true off-chain signature generation
- Maintains full security with replay protection via nonce

### Verify on Starkscan
- [View Class (V23 SNIP-9 Compatible)](https://starkscan.co/class/0x00cd7618e5f407ad85458398815cf47dd63f06cd5249733e2bf987d13823f2e9)
- [View Declaration Transaction (V23)](https://starkscan.co/tx/0x03a69f9011522c301159ee6c8ecbe54c85536882581dce87f46ab5516fd81a00)
- [View Class (V22 Previous)](https://starkscan.co/class/0x00097c307b5e2869713d376309a4e43028b6ef17061499022103304b482c7298)
- [View Contract (V22 Production)](https://starkscan.co/contract/0x01821ff8d12daa4f4406daea573a0f7bcba8aae62b90632384176a6b780c15fd)
- [View Class (V22 Debug)](https://starkscan.co/class/0x052458a2546699d1c175eccc31ac8ff6ccfa284ab7c7c384d37ceaf96abf4cb0)
- [View Contract (V22 Debug)](https://starkscan.co/contract/0x06573411e4181fb6b43e2800fb8f2936bbe592f925c7c66e04858565f23a2b25)

---

## 📜 License

MIT License

Copyright (c) 2025

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

---

## 🌟 Features

### Dual Signature Validation
- **Owner Path**: Standard ECDSA signature validation using the account's master public key
- **Session Path**: Temporary key validation with configurable restrictions

### Session Key Restrictions
- ⏰ **Expiration Time**: Sessions automatically expire after a specified timestamp
- 🔢 **Call Limits**: Maximum number of transactions allowed per session
- 🎯 **Selector Allowlist**: Restrict sessions to specific function selectors (or allow all)
- 🔐 **Cryptographic Security**: ECDSA signature verification using Stark curve

### Security Features
- ✅ Owner-only session management (add/revoke requires master key)
- ✅ Owner-only upgrades (preserves security model)
- ✅ Events emitted for session lifecycle (add/revoke)
- ✅ Automatic session invalidation on expiry
- ✅ Per-session call tracking
- ✅ Compatible with paymasters and transaction fee mechanisms

---

## 🏗️ Architecture

### Contract Structure

```
SessionAccount (extends OpenZeppelin AccountComponent)
├── Owner Validation (unchanged)
│   └── Standard 2-element signature [r, s]
├── Session Validation (new)
│   └── 4-element signature [session_pubkey, r, s, valid_until]
└── Session Management
    ├── add_or_update_session_key()
    ├── revoke_session_key()
    └── get_session_data()
```

### Signature Formats

**Owner Signature** (standard validation):
```
[r, s]
```
- Standard 2-element ECDSA signature
- Validated using OpenZeppelin's `validate_transaction()`
- Compatible with starknet.js and all standard wallets
- Signature computed over transaction hash

**Session Signature** (custom validation):
```
[session_pubkey, r, s, valid_until]
```
- `session_pubkey`: Public key of the temporary session
- `r, s`: ECDSA signature components (signed by session private key)
- `valid_until`: Expiration timestamp (must match stored session)
- Uses custom poseidon hash for signature validation

### Session Message Hash Algorithm

The session signature is computed over a hash of **predictable, off-chain-computable values only**:

```cairo
fn _session_message_hash(
    calls: Span<Call>,
    valid_until: u64
) -> felt252 {
    let hash_data = [
        get_contract_address(),     // Account address (binding)
        tx_info.chain_id,           // Network identifier
        tx_info.nonce,              // Replay protection
        valid_until,                // Expiration
        // For each call:
        call.to,                    // Target contract
        call.selector,              // Function selector
        ...call.calldata            // All arguments (flattened)
    ];
    
    poseidon_hash_span(hash_data)
}
```

**Key Properties:**
- ✅ **No transaction_hash** - All values known before submission
- ✅ **Nonce prevents replay** - Each signature is single-use
- ✅ **Account binding** - Can't be used on different accounts
- ✅ **Chain binding** - Can't be replayed on other networks
- ✅ **Complete integrity** - Covers all call parameters

### Validation Flow

```mermaid
graph TD
    A[Transaction Received] --> B{Signature Length?}
    B -->|2 elements| C[Owner Validation]
    B -->|4 elements| D[Session Validation]
    C --> C1[Call OZ validate_transaction]
    C1 --> E{Valid Owner Sig?}
    E -->|Yes| F[VALIDATED]
    E -->|No| G[REJECTED]
    D --> H{Session Exists?}
    H -->|No| G
    H -->|Yes| I{Session Expired?}
    I -->|Yes| G
    I -->|No| J{Calls Exceeded?}
    J -->|Yes| G
    J -->|No| K{Selector Allowed?}
    K -->|No| G
    K -->|Yes| L{Valid Session Sig?}
    L -->|No| G
    L -->|Yes| M[Increment calls_used]
    M --> F
```

---

## 📦 Installation

### Prerequisites

- [Scarb](https://docs.swmansion.com/scarb/) v2.11.4+
- [Starknet Foundry](https://foundry-rs.github.io/starknet-foundry/) v0.50.0+

### Setup

```bash
# Clone the repository
git clone https://github.com/yourusername/starknet-session-account.git
cd starknet-session-account

# Build the contract
scarb build

# Run tests
snforge test
```

---

## 🚀 Usage Examples

### 1. Deploy the Account

```bash
# Declare the contract
sncast declare --contract-name Account --network mainnet

# Deploy with owner's public key
sncast deploy \
  --class-hash 0x<CLASS_HASH> \
  --constructor-calldata 0x<OWNER_PUBLIC_KEY> \
  --network mainnet
```

### 2. Add a Session Key (Owner Only)

```cairo
// From the owner's perspective
use session_account::{ISessionKeyManagerDispatcher, ISessionKeyManagerDispatcherTrait};

let account = ISessionKeyManagerDispatcher { contract_address };

// Create a session that:
// - Expires in 1 day
// - Allows up to 10 transactions
// - Restricts to transfer() and approve() functions only
account.add_or_update_session_key(
    session_public_key: 0x987654...,
    valid_until: get_block_timestamp() + 86400,  // 1 day
    max_calls: 10,
    allowed_entrypoints: array![
        0x83afd3f4...  // transfer selector
        0x219209e0...  // approve selector
    ]
);
```

### 3. Use a Session Key

```python
# Off-chain: Sign with session private key
from starknet_py.net.account.account import Account
from starknet_py.hash.selector import get_selector_from_name
from starknet_py.hash.hash_method import poseidon_hash_many

# Fetch current nonce (predictable value)
nonce = await account.get_nonce()

# Build the message hash with predictable values ONLY
# This can be computed BEFORE sending the transaction
hash_data = [
    account_address,          # Account contract address
    chain_id,                 # Network chain ID
    nonce,                    # Current nonce (fetch from account)
    valid_until,              # Session expiration timestamp
    # Flatten all call data
    call.to,                  # Target contract
    call.selector,            # Function selector
    *call.calldata            # Function arguments
]

message_hash = poseidon_hash_many(hash_data)

# Sign with session private key
r, s = sign_message(message_hash, session_private_key)

# Construct the signature
signature = [session_public_key, r, s, valid_until]

# Execute transaction with session signature
await account.execute(
    calls=[Call(
        to=token_address,
        selector=get_selector_from_name("transfer"),
        calldata=[recipient, amount_low, amount_high]
    )],
    signature=signature,
    nonce=nonce  # Use the same nonce we hashed
)
```

### 4. Revoke a Session (Owner Only)

```cairo
account.revoke_session_key(session_public_key: 0x987654...);
```

### 5. Query Session Data

```cairo
let session_data = account.get_session_data(session_public_key: 0x987654...);

// Returns:
// - valid_until: u64
// - max_calls: u32
// - calls_used: u32
// - allowed_entrypoints_len: u32
```

---

## 🧪 Testing

The project includes a comprehensive test suite with 15 tests covering all functionality.

### Run All Tests

```bash
snforge test
```

### Run Specific Tests

```bash
# Test owner validation
snforge test test_owner_signature_valid

# Test session expiration
snforge test test_session_expired

# Test call limits
snforge test test_session_max_calls

# Test selector restrictions
snforge test test_session_not_allowed_selector
```

### Test Coverage

| Category | Tests | Coverage |
|----------|-------|----------|
| Owner Validation | 1 | ✅ Owner signature validation |
| Session Validation | 5 | ✅ Valid, expired, max calls, invalid sig, selector restrictions |
| Session Management | 3 | ✅ Add, revoke, no restrictions, multiple calls |
| Authorization | 2 | ✅ Add/revoke unauthorized |
| Events | 1 | ✅ Event emissions |
| Upgrades | 1 | ✅ Owner-only upgrades |

### Sample Test Output

```
Collected 15 test(s) from sessions_smart_contract package
Running 15 test(s) from tests/
[PASS] test_owner_signature_valid
[PASS] test_session_signature_valid
[PASS] test_session_expired
[PASS] test_session_max_calls
[PASS] test_session_not_allowed_selector
[PASS] test_session_invalid_signature
[PASS] test_session_revoke
[PASS] test_session_with_no_restrictions
[PASS] test_session_multiple_calls_in_transaction
[PASS] test_add_session_unauthorized
[PASS] test_revoke_session_unauthorized
[PASS] test_session_events_emitted
[PASS] test_upgrade_still_owner_only
[PASS] test_invalid_signature_length_3_elements
[PASS] test_empty_signature_fails
Tests: 15 passed, 0 failed, 0 ignored, 0 filtered out
```

---

## 🔐 Security Considerations

### ✅ Implemented Protections

1. **Owner Authority**
   - Only the account owner (via `assert_only_self()`) can add/revoke sessions
   - Owner can upgrade the contract implementation
   - Owner validation path remains unchanged from OpenZeppelin standard

2. **Session Isolation**
   - Each session has its own public key and usage tracking
   - Sessions cannot modify other sessions
   - Expired sessions are automatically rejected

3. **Cryptographic Integrity**
   - ECDSA signature verification on Stark curve
   - Message hash includes: account address, chain ID, nonce, valid_until, and full call data
   - **Nonce-based replay protection**: Each signature is single-use (tied to account nonce)
   - **Predictable pre-signing**: All hash components known before transaction submission
   - Prevents replay attacks across accounts, chains, and transactions

4. **Time-Based Security**
   - Sessions have mandatory expiration timestamps
   - No indefinite access delegation
   - Expiration checked on every validation

5. **Call Limiting**
   - Maximum calls enforced per session
   - Prevents abuse of compromised session keys
   - Usage tracked in storage

6. **Selector Restrictions**
   - Optional function allowlist
   - Prevents sessions from calling unintended functions
   - Empty allowlist = unrestricted (explicit choice)

### ⚠️ Known Limitations

1. **Session Key Management**
   - No on-chain session key revocation by session holder (only owner can revoke)
   - Consider off-chain key rotation strategies

2. **Gas Considerations**
   - Session validation adds gas overhead (~470k gas for signature check)
   - Consider this in fee estimation

3. **Selector Allowlist Size**
   - Large allowlists increase gas costs linearly
   - Recommend limiting to 10-20 selectors per session

4. **No Partial Revocation**
   - Revoking a session invalidates all remaining calls
   - Cannot reduce max_calls or modify restrictions after creation

### 🛡️ Best Practices

1. **Principle of Least Privilege**
   ```cairo
   // ✅ Good: Restrictive session
   add_session_key(
       session_key,
       valid_until: now + 1_hour,
       max_calls: 5,
       allowed_entrypoints: array![specific_selector]
   );
   
   // ❌ Bad: Overly permissive
   add_session_key(
       session_key,
       valid_until: now + 30_days,
       max_calls: 1000,
       allowed_entrypoints: array![]  // Unrestricted!
   );
   ```

2. **Short-Lived Sessions**
   - Mobile apps: 1-24 hours
   - Games: 1-7 days
   - Automated bots: 1 hour
   - Never exceed 30 days

3. **Appropriate Call Limits**
   - Batch operations: 50-100 calls
   - Daily usage: 10-20 calls
   - Single operation: 1-5 calls

4. **Key Storage**
   - Store session private keys in secure enclaves
   - Never expose session keys in client-side code
   - Implement key rotation

5. **Monitor and Audit**
   - Watch for `SessionKeyAdded` and `SessionKeyRevoked` events
   - Track unusual session usage patterns
   - Implement off-chain monitoring

---

## 🎯 Use Cases

### 1. Mobile Gaming
- Create session keys for game sessions
- Allow players to make in-game transactions without constant wallet confirmation
- Restrict to game contract functions only
- Auto-expire after play session

### 2. DeFi Trading Bots
- Delegate limited trading authority to automated strategies
- Restrict to DEX swap functions
- Set call limits to prevent runaway trading
- Short expiration for reduced risk

### 3. Subscription Services
- One-time session creation for recurring payments
- Restrict to payment contract
- Limit number of payments
- Expire after subscription period

### 4. Web3 Social Apps
- Background posting/liking without popups
- Restrict to social contract functions
- Daily usage limits
- Short-lived for security

### 5. Gasless Onboarding
- Sponsor new users with session keys
- Limited transactions for initial exploration
- Expire after trial period
- Upgrade to full account later

---

## 📚 API Reference

### ISessionKeyManager Interface

#### `add_or_update_session_key`

Adds a new session key or updates an existing one. **Owner-only**.

```cairo
fn add_or_update_session_key(
    ref self: TContractState,
    session_key: felt252,           // Public key of the session
    valid_until: u64,               // Expiration timestamp
    max_calls: u32,                 // Maximum number of calls
    allowed_entrypoints: Array<felt252>  // Allowed function selectors (empty = all)
);
```

**Emits**: `SessionKeyAdded(session_key, valid_until, max_calls)`

**Reverts**: If caller is not the account owner

---

#### `revoke_session_key`

Revokes a session key, making it immediately invalid. **Owner-only**.

```cairo
fn revoke_session_key(
    ref self: TContractState,
    session_key: felt252            // Public key to revoke
);
```

**Emits**: `SessionKeyRevoked(session_key)`

**Reverts**: If caller is not the account owner

---

#### `get_session_data`

Queries session information. **Public read**.

```cairo
fn get_session_data(
    self: @TContractState,
    session_key: felt252
) -> SessionData;

// Returns:
struct SessionData {
    valid_until: u64,              // 0 if session doesn't exist
    max_calls: u32,
    calls_used: u32,
    allowed_entrypoints_len: u32
}
```

---

#### `get_contract_info`

Returns contract version information. **Public read**.

```cairo
fn get_contract_info(
    self: @TContractState
) -> felt252;

// Returns: 'v22_production_secure' (version identifier)
```

---

### Debug Functions (DEBUG VERSION ONLY)

> ⚠️ **SECURITY WARNING**: These functions are only available in the debug version and should **NEVER** be used in production. They allow forced nonce and chain_id parameters which create serious security vulnerabilities.

#### `compute_session_message_hash_offchain`

Computes session message hash with forced nonce and chain_id. **DEBUG ONLY**.

```cairo
fn compute_session_message_hash_offchain(
    self: @ContractState,
    calls: Array<starknet::account::Call>,
    valid_until: u64,
    forced_nonce: felt252,        // ⚠️ SECURITY RISK: Allows replay attacks
    forced_chain_id: felt252      // ⚠️ SECURITY RISK: Allows cross-chain replay
) -> felt252;
```

**Security Risks**:
- **Replay Attacks**: Forced nonce allows signature reuse
- **Cross-Chain Replay**: Forced chain_id allows signature replay across networks
- **Nonce Manipulation**: Bypasses single-use protection

#### `debug_validate_session_signature`

Validates session signature with forced parameters. **DEBUG ONLY**.

```cairo
fn debug_validate_session_signature(
    self: @ContractState,
    session_key: felt252,
    calls: Array<starknet::account::Call>,
    valid_until: u64,
    forced_nonce: felt252,        // ⚠️ SECURITY RISK: Allows replay attacks
    forced_chain_id: felt252,     // ⚠️ SECURITY RISK: Allows cross-chain replay
    r: felt252,
    s: felt252
) -> (felt252, bool);            // Returns (message_hash, is_valid)
```

**Security Risks**: Same as above - allows bypassing critical security mechanisms.

---

### SRC-6 Interface (Account)

#### `__validate__`

Validates transaction signatures. Supports both owner and session signatures.

```cairo
fn __validate__(ref self: ContractState, calls: Array<Call>) -> felt252;
```

**Returns**: `starknet::VALIDATED` (1) if valid, 0 if invalid

**Signature Formats**:
- Owner: `[r, s]`
- Session: `[session_pubkey, r, s, valid_until]`

---

#### `__execute__`

Executes an array of calls after validation.

```cairo
fn __execute__(ref self: ContractState, calls: Array<Call>) -> Array<Span<felt252>>;
```

---

### Events

#### `SessionKeyAdded`

```cairo
struct SessionKeyAdded {
    #[key]
    session_key: felt252,
    valid_until: u64,
    max_calls: u32,
}
```

#### `SessionKeyRevoked`

```cairo
struct SessionKeyRevoked {
    #[key]
    session_key: felt252,
}
```

---

## 🔧 Development

### Project Structure

```
starknet-session-account/
├── src/
│   ├── lib.cairo              # Module exports
│   └── account.cairo          # Main contract + session logic
├── tests/
│   └── test_session_validation.cairo  # Full test suite
├── scripts/
│   ├── add_session_key.sh     # Example: Add session
│   └── revoke_session_key.sh  # Example: Revoke session
├── Scarb.toml                 # Project config
└── README.md                  # This file
```

### Dependencies

```toml
[dependencies]
starknet = ">=2.8.0"
openzeppelin = { git = "https://github.com/OpenZeppelin/cairo-contracts.git", tag = "v2.0.0" }
snforge_std_deprecated = { git = "https://github.com/foundry-rs/starknet-foundry.git", tag = "v0.50.0" }
```

### Building

```bash
# Development build
scarb build

# Clean build
scarb clean && scarb build

# Format code
scarb fmt
```

### Testing

```bash
# Run all tests
snforge test

# Run with gas profiling
snforge test --detailed-resources

# Run specific test
snforge test test_name

# Verbose output
snforge test -v
```

---

## 🔧 Troubleshooting

### Frontend Integration Issues

#### "Invalid transaction nonce: undefined" Error

**Problem**: Your frontend gets nonce-related errors when calling session functions.

**Root Cause**: Starknet.js 7.x has a bug where it reports incorrect nonce values.

**Solution**: Force nonce increment in your frontend:

```typescript
// ❌ This fails with "Invalid transaction nonce: undefined"
const result = await account.execute({
  contractAddress: ozAddr,
  entrypoint: 'add_or_update_session_key',
  calldata: calldata
});

// ✅ This works - force nonce increment
const currentNonce = await account.getNonce();
const result = await account.execute({
  contractAddress: ozAddr,
  entrypoint: 'add_or_update_session_key',
  calldata: calldata
}, undefined, {
  nonce: currentNonce + 1  // Force increment to bypass library bug
});
```

**Why Other Methods Failed**:
- `account.signInvoke` - Method doesn't exist in current Starknet.js version
- Different RPC providers - CORS issues and version incompatibility
- Raw RPC with fetch - Same `signInvoke` issue
- BigInt nonce - Same underlying nonce bug
- Wait and retry - Same underlying nonce bug

#### "Account: unauthorized" for Session Transactions

**Problem**: Session key transactions fail with authorization errors.

**Root Cause**: Message hash computation mismatch between frontend and contract.

**Solution**: Ensure your frontend computes the message hash exactly as the contract does:

```typescript
// Contract's _session_message_hash order:
// 1. Contract address (ozAddr)
// 2. Chain ID
// 3. Nonce
// 4. Valid until timestamp
// 5. For each call: contract address, selector, calldata length, calldata elements

const sessionMsgHash = hash.computeHashOnElements([
  ozAddr,                    // Contract address
  chainId,                   // Chain ID
  nonce,                     // Transaction nonce
  session.validUntil.toString(), // Valid until timestamp
  CONTRACT_ADDRESS,          // Target contract
  hash.getSelectorFromName("wave").toString(), // Function selector
  msgFelts.length.toString(), // Calldata length
  ...msgFelts                // Calldata elements
]);
```

#### Session Functions Not Found

**Problem**: `add_or_update_session_key`, `revoke_session_key`, or `get_session_data` functions not found.

**Root Cause**: Contract not properly deployed or ABI compilation issue.

**Solution**: 
1. Verify contract is deployed with correct class hash: `0x32008071322d9ef668e4308886f76fdc77679dc5e213127d5378b42c77bf5a5`
2. Check contract ABI includes session functions
3. Ensure you're using the latest deployed version (v22)
4. Use the new contract address: `0x01821ff8d12daa4f4406daea573a0f7bcba8aae62b90632384176a6b780c15fd`

#### "Account: invalid signature" for Sessions with Zero Entrypoints

**Problem**: Sessions created with `allowed_entrypoints_len = 0` (no restrictions) fail with "Account: invalid signature".

**Root Cause**: The old contract (v18 and earlier) had a bug in validation logic for zero entrypoints.

**Solution**: Use the new contract (v22) which properly handles sessions with no entrypoint restrictions:
- **New Class Hash**: `0x32008071322d9ef668e4308886f76fdc77679dc5e213127d5378b42c77bf5a5`
- **New Contract Address**: `0x01821ff8d12daa4f4406daea573a0f7bcba8aae62b90632384176a6b780c15fd`
- **Fix**: Sessions with `allowed_entrypoints_len = 0` now correctly allow all entrypoints

### Smart Contract Issues

#### Tests Failing

**Problem**: `snforge test` fails with compilation or runtime errors.

**Solution**:
```bash
# Clean and rebuild
scarb clean && scarb build

# Run tests with verbose output
snforge test -v

# Check for specific test failures
snforge test test_name
```

#### Deployment Issues

**Problem**: Contract deployment fails with various errors.

**Solution**:
```bash
# Ensure sufficient balance
# Check network connectivity
# Verify class hash is declared
# Use correct network (mainnet vs testnet)
```

---

## 🤝 Contributing

Contributions are welcome! Please follow these guidelines:

1. **Fork** the repository
2. **Create** a feature branch (`git checkout -b feature/amazing-feature`)
3. **Write** tests for new functionality
4. **Ensure** all tests pass (`snforge test`)
5. **Format** code (`scarb fmt`)
6. **Commit** changes (`git commit -m 'Add amazing feature'`)
7. **Push** to branch (`git push origin feature/amazing-feature`)
8. **Open** a Pull Request

### Code Style

- Follow Cairo best practices
- Add comments for complex logic
- Write comprehensive tests
- Update documentation

---

## 📖 Additional Resources

- [Starknet Documentation](https://docs.starknet.io/)
- [Cairo Book](https://book.cairo-lang.org/)
- [OpenZeppelin Cairo Contracts](https://github.com/OpenZeppelin/cairo-contracts)
- [Starknet Foundry](https://foundry-rs.github.io/starknet-foundry/)
- [Account Abstraction on Starknet](https://docs.starknet.io/documentation/architecture_and_concepts/Accounts/introduction/)

---

## ⚖️ Disclaimer

This software is provided "as is", without warranty of any kind. Use at your own risk. Always audit smart contracts before deploying to mainnet with real funds.

---

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/yourusername/starknet-session-account/issues)
- **Discussions**: [GitHub Discussions](https://github.com/yourusername/starknet-session-account/discussions)

---

Made with ❤️ for the Starknet ecosystem
