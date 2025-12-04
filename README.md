# 🎮 Starknet Session Account

> **Gasless, delegated transactions on Starknet** — Enable users to interact with your dApp without paying gas fees or signing every transaction.

A production-ready Cairo smart contract that combines **session keys** with **SNIP-9 v2 Outside Execution** and **Paymaster support**, enabling seamless Web3 UX on Starknet.

---

## ✨ What This Enables

```
┌─────────────────────────────────────────────────────────────────────┐
│                                                                     │
│  User clicks "Play" → Backend sponsors gas → Transaction executes   │
│                                                                     │
│  • No wallet popup                                                  │
│  • No gas fees for user                                             │
│  • Delegated, time-limited access                                   │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Key Features:**
- 🔑 **Session Keys** — Temporary, restricted access delegation
- ⛽ **Gasless Transactions** — Backend sponsors gas via paymasters
- 🔄 **Outside Execution** — Third parties submit transactions on user's behalf
- 🛡️ **Production Security** — Battle-tested, audited code with comprehensive tests

---

## 🚀 Production Deployment

| Field | Value |
|-------|-------|
| **Class Hash** | `0x2de1565226d5215a38b68c4d9a4913989b54edff64c68c45e453c417b44cd83` |
| **Network** | Starknet Mainnet |
| **Version** | v28 (Production Cleaned) |
| **Starkscan** | [View Contract Class](https://starkscan.co/class/0x02de1565226d5215a38b68c4d9a4913989b54edff64c68c45e453c417b44cd83) |

---

## 📖 Table of Contents

- [Why Custom SNIP-9?](#-why-we-built-our-own-snip-9)
- [Paymaster Integration](#-paymaster-integration)
- [Security Architecture](#-security-architecture)
- [Test Suite](#-comprehensive-test-suite)
- [Real-World Use Cases](#-real-world-use-cases)
- [Quick Start](#-quick-start)
- [API Reference](#-api-reference)

---

## 🤔 Why We Built Our Own SNIP-9

### The Problem with Existing Implementations

OpenZeppelin's `SRC9Component` uses **SNIP-12 Revision 0** for typed data hashing. However:

1. **Starknet.js uses Revision 1** — The official JavaScript library computes hashes using SNIP-12 Rev 1
2. **Hash mismatch = failed signatures** — Frontend-signed messages don't match what the contract expects
3. **No session key support** — Standard implementations only validate owner signatures

### Our Solution

We implemented a **custom SNIP-9 v2 component** with:

```cairo
// SNIP-12 Revision 1 Type Hashes (matching starknet.js)
STARKNET_DOMAIN_TYPE_HASH = 0x1ff2f602e42168014d405a94f75e8a93d640751d71d16311266e140d8b0a210
CALL_TYPE_HASH = 0x3635c7f2a7ba93844c0d064e18e487f35ab90f7c39d00f186a781fc3f0c2ca9
OUTSIDE_EXECUTION_TYPE_HASH = 0x5a4b49e17039355cd95d1f0981d75901191d1319b1f4b05a9a791d218d7e0c
```

**Key Differences from OpenZeppelin:**

| Feature | OpenZeppelin SRC9 | Our Implementation |
|---------|-------------------|-------------------|
| SNIP-12 Version | Revision 0 | **Revision 1** ✅ |
| starknet.js Compatible | ❌ Hash mismatch | ✅ Perfect match |
| Session Signatures | ❌ Owner only | ✅ Owner + Sessions |
| Array Hashing | Inline | **Pre-hashed** (Rev 1 spec) |
| Version Encoding | Shortstring `'2'` | **Numeric `2`** |

### Technical Details

**SNIP-12 Rev 1 requires pre-hashing arrays:**

```cairo
// Our implementation (correct for Rev 1)
fn _hash_call(call: Call) -> felt252 {
    let calldata_hash = poseidon_hash_span(call.calldata);  // Pre-hash array
    poseidon_hash_span([CALL_TYPE_HASH, call.to, call.selector, calldata_hash])
}

// The OutsideExecution hash also pre-hashes the calls array
let calls_array_hash = poseidon_hash_span(call_hashes.span());
```

This ensures signatures computed by starknet.js match exactly what the contract validates.

---

## ⛽ Paymaster Integration

### How Gasless Transactions Work

```
┌──────────────┐    1. Sign      ┌──────────────┐    2. Submit     ┌──────────────┐
│    User      │ ─────────────→  │   Backend    │ ───────────────→ │  Paymaster   │
│  (no STRK)   │   (session)     │  (relayer)   │   (sponsored)    │   (AVNU)     │
└──────────────┘                 └──────────────┘                  └──────────────┘
                                                                          │
                                       3. Execute via SNIP-9               │
                                                                          ▼
                                                                   ┌──────────────┐
                                                                   │   Account    │
                                                                   │  Contract    │
                                                                   └──────────────┘
```

### Integration Steps

**1. User creates a session (once):**
```typescript
// Owner signs to add session key
await account.execute({
  contractAddress: accountAddress,
  entrypoint: 'add_or_update_session_key',
  calldata: [sessionPubKey, validUntil, maxCalls, ...allowedSelectors]
});
```

**2. User signs session messages (gas-free):**
```typescript
// Session key signs the operation (no gas needed)
const signature = signWithSessionKey(messageHash, sessionPrivateKey);
```

**3. Backend submits via paymaster:**
```typescript
// Backend calls execute_from_outside_v2 with sponsored gas
const outsideExecution = {
  caller: relayerAddress,  // or 0 for any caller
  nonce: randomNonce,
  execute_after: now,
  execute_before: now + 3600,
  calls: userCalls
};

await paymaster.executeFromOutside(accountAddress, outsideExecution, signature);
```
---

## 🛡️ Security Architecture

### Multi-Layer Protection

```
┌─────────────────────────────────────────────────────────────────┐
│                     SECURITY LAYERS                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  1. ACCESS CONTROL                                               │
│     └─ Owner-only: add/revoke sessions, upgrade contract         │
│                                                                  │
│  2. SESSION RESTRICTIONS                                         │
│     ├─ Time-limited (valid_until timestamp)                      │
│     ├─ Call-limited (max_calls counter)                          │
│     └─ Function-limited (allowed_entrypoints whitelist)          │
│                                                                  │
│  3. CRYPTOGRAPHIC SECURITY                                       │
│     ├─ ECDSA signature verification (Stark curve)                │
│     ├─ Poseidon hash for message integrity                       │
│     └─ Nonce-based replay protection                             │
│                                                                  │
│  4. SNIP-9 PROTECTIONS                                           │
│     ├─ Timestamp bounds (execute_after, execute_before)          │
│     ├─ Caller restrictions (specific address or any)             │
│     └─ One-time nonce consumption                                │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Signature Validation Flow

**Owner Signatures (2 elements):**
```
[r, s] → Validate via OpenZeppelin → Full account control
```

**Session Signatures (4 elements):**
```
[session_pubkey, r, s, valid_until]
    ↓
1. Check session exists (valid_until > 0)
2. Check not expired (block_timestamp ≤ valid_until)
3. Check calls remaining (calls_used < max_calls)
4. Check selector allowed (if whitelist exists)
5. Verify ECDSA signature
6. Increment calls_used counter
    ↓
Transaction authorized
```

### Security Guarantees

| Protection | How It Works |
|------------|--------------|
| **No Replay Attacks** | Nonces are consumed on use; each signature is single-use |
| **No Cross-Chain Replay** | Chain ID included in message hash |
| **No Account Confusion** | Account address included in message hash |
| **No Privilege Escalation** | Sessions can only call whitelisted functions |
| **No Indefinite Access** | Sessions have mandatory expiration |
| **No Runaway Usage** | Call limits prevent abuse of compromised keys |

### What We Removed in v28

We removed debug events for production cleanliness:
- ❌ `DebugEvent`, `SignatureValidation`, `SessionValidationResult`
- ❌ `ExecutionStarted`, `CallExecuted`, `OutsideExecutionValidation`
- ✅ Kept essential events: `SessionKeyAdded`, `SessionKeyRevoked`, `OutsideExecutionExecuted`

---

## 🧪 Comprehensive Test Suite

### Test Results: 44/44 Passing ✅

```bash
$ snforge test

Collected 44 test(s) from sessions_smart_contract package
Running 44 test(s) from tests/

# Session Validation Tests (21)
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
[PASS] test_compute_session_message_hash_matches_manual
[PASS] test_outside_execution_hash_matches_manual
[PASS] test_validate_session_expired_returns_zero
[PASS] test_validate_session_blocks_disallowed_selector
[PASS] test_is_valid_signature_owner_vs_session_paths
[PASS] test_outside_execution_nonce_default_and_invalid_signature

# SNIP-9 Compatibility Tests (3)
[PASS] test_snip9_version_returns_v2
[PASS] test_contract_info_shows_snip9_compatible
[PASS] test_session_keys_still_work_with_snip9

# Hash Computation Tests (7)
[PASS] test_starknet_domain_type_hash_is_correct
[PASS] test_call_type_hash_is_correct
[PASS] test_outside_execution_type_hash_is_correct
[PASS] test_outside_execution_hash_deterministic
[PASS] test_outside_execution_hash_changes_with_nonce
[PASS] test_outside_execution_hash_changes_with_caller
[PASS] test_outside_execution_nonce_validity

# Outside Execution Tests (13)
[PASS] test_fresh_nonce_is_valid
[PASS] test_zero_nonce_is_valid
[PASS] test_message_hash_computation
[PASS] test_message_hash_includes_calls
[PASS] test_message_hash_includes_timestamps
[PASS] test_message_hash_with_multiple_calls
[PASS] test_message_hash_with_empty_calls
[PASS] test_any_caller_address_is_zero
[PASS] test_session_key_added_for_outside_execution
[PASS] test_timestamp_boundary_execute_after_equals_current
[PASS] test_timestamp_boundary_execute_before_equals_current
[PASS] test_large_nonce_value
[PASS] test_large_calldata

Tests: 44 passed, 0 failed, 0 ignored, 0 filtered out
```

### Test Categories

| Category | Tests | What It Covers |
|----------|-------|----------------|
| **Session Validation** | 21 | Add, revoke, expiry, limits, selectors, signatures |
| **SNIP-9 Compatibility** | 3 | Version checks, interface detection |
| **Hash Computation** | 7 | SNIP-12 type hashes, determinism |
| **Outside Execution** | 13 | Nonces, timestamps, callers, boundaries |

---

## 🎯 Real-World Use Cases

### 1. 🎮 **Gasless Gaming**

**Scenario:** Players make in-game moves without paying gas or confirming each action.

```typescript
// Game creates session for player
await gameContract.createPlayerSession(playerAccount, {
  validUntil: Date.now() + 24 * 60 * 60 * 1000,  // 24 hours
  maxCalls: 1000,                                  // Many moves allowed
  allowedSelectors: [MAKE_MOVE, CLAIM_REWARD]      // Only game functions
});

// Player signs moves with session key (instant, free)
const moveSignature = player.signWithSession(moveData);

// Game backend submits via paymaster (player pays nothing)
await paymaster.submitMove(playerAccount, moveData, moveSignature);
```

**Benefits:**
- ⚡ Instant gameplay (no wallet popups)
- 💰 Free for players (game sponsors gas)
- 🔒 Limited to game functions only

---

### 2. 🏦 **DeFi Automation**

**Scenario:** Yield optimizer executes strategies on user's behalf.

```typescript
// User authorizes yield optimizer
await account.addSessionKey({
  sessionKey: optimizerKey,
  validUntil: oneWeekFromNow,
  maxCalls: 100,
  allowedSelectors: [DEPOSIT, WITHDRAW, HARVEST]  // Only yield functions
});

// Optimizer executes when conditions are met
await paymaster.executeStrategy(userAccount, {
  calls: [harvestCall, compoundCall],
  signature: optimizerSignature
});
```

**Benefits:**
- 🤖 Automated execution without user presence
- ⏰ Time-limited authorization
- 🎯 Function-restricted (can't drain wallet)

---

### 3. 📱 **Social dApps**

**Scenario:** Users post, like, and interact without wallet friction.

```typescript
// User logs in and creates session
const session = await socialApp.createSession(userAccount, {
  validUntil: Date.now() + 7 * 24 * 60 * 60 * 1000,  // 1 week
  maxCalls: 500,
  allowedSelectors: [POST, LIKE, COMMENT, FOLLOW]
});

// Every interaction is instant and free
await socialApp.post("Hello Starknet!", session.signature);
await socialApp.like(postId, session.signature);
```

**Benefits:**
- 🚀 Web2-like UX (no interruptions)
- 📊 High-frequency interactions
- 🔐 Can't transfer tokens or NFTs

---

### 4. 🎪 **Event Ticketing & Airdrops**

**Scenario:** Mass distribution without requiring users to have gas.

```typescript
// Event organizer sets up sponsored claims
for (const attendee of attendees) {
  const claimSession = await createClaimSession(attendee);
  
  // Send claim link (user needs no STRK)
  await sendEmail(attendee, {
    claimUrl: `https://event.com/claim/${claimSession.token}`
  });
}

// User clicks link → backend sponsors claim
await paymaster.claimTicket(attendeeAccount, ticketId, sessionSignature);
```

**Benefits:**
- 🎁 Zero-friction claiming
- 💵 Organizer pays all gas
- ⏳ Time-limited claim windows

---

### 5. 🛒 **Subscription & Recurring Payments**

**Scenario:** Monthly subscriptions without manual approval each time.

```typescript
// User approves subscription
await account.addSessionKey({
  sessionKey: subscriptionServiceKey,
  validUntil: oneYearFromNow,
  maxCalls: 12,  // 12 monthly payments
  allowedSelectors: [TRANSFER]  // Only payment function
});

// Service charges monthly (user approved once)
await paymaster.chargeSubscription(userAccount, {
  to: USDC_ADDRESS,
  selector: TRANSFER,
  calldata: [serviceAddress, subscriptionAmount]
});
```

**Benefits:**
- 🔄 Automated recurring payments
- 🎯 Capped at specific amount/frequency
- ❌ Auto-expires after subscription period

---

## 🚀 Quick Start

### Prerequisites

```bash
# Install Scarb (Cairo compiler)
curl --proto '=https' --tlsv1.2 -sSf https://docs.swmansion.com/scarb/install.sh | sh

# Install Starknet Foundry
curl -L https://raw.githubusercontent.com/foundry-rs/starknet-foundry/master/scripts/install.sh | sh
snfoundryup
```

### Build & Test

```bash
# Clone repository
git clone https://github.com/your-repo/sessions-smart-contract.git
cd sessions-smart-contract

# Build
scarb build

# Run tests
snforge test
```

### Deploy

```bash
# Declare on mainnet
sncast declare --contract-name Account --network mainnet

# Deploy with your public key
sncast deploy \
  --class-hash 0x2de1565226d5215a38b68c4d9a4913989b54edff64c68c45e453c417b44cd83 \
  --constructor-calldata YOUR_PUBLIC_KEY \
  --network mainnet
```

---

## 📚 API Reference

### Session Management

```cairo
// Add or update a session key (owner only)
fn add_or_update_session_key(
    session_key: felt252,              // Public key of session
    valid_until: u64,                  // Expiration timestamp
    max_calls: u32,                    // Maximum transactions
    allowed_entrypoints: Array<felt252> // Whitelisted selectors (empty = all)
);

// Revoke a session key (owner only)
fn revoke_session_key(session_key: felt252);

// Query session data (public)
fn get_session_data(session_key: felt252) -> SessionData;
```

### Outside Execution (SNIP-9 v2)

```cairo
// Execute calls on behalf of the account
fn execute_from_outside_v2(
    outside_execution: OutsideExecution,
    signature: Array<felt252>
) -> Array<Span<felt252>>;

// Check if nonce is available
fn is_valid_outside_execution_nonce(nonce: felt252) -> bool;

// Compute message hash for signing
fn get_outside_execution_message_hash_rev_1(
    outside_execution: OutsideExecution
) -> felt252;
```

### Signature Formats

| Type | Format | Use Case |
|------|--------|----------|
| **Owner** | `[r, s]` | Full account control |
| **Session** | `[session_pubkey, r, s, valid_until]` | Delegated access |

---

## 📄 License

MIT License — see [LICENSE](LICENSE) for details.

---

## 🤝 Contributing

Contributions welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Write tests for new functionality
4. Ensure all 38 tests pass
5. Submit a pull request

---

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/chipi-pay/sessions-smart-contract/issues)

---

<p align="center">
  Built with ❤️ for the Starknet ecosystem
</p>
