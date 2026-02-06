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
| **Class Hash** | `0x53f4f8791ed5bed0fddaa553d180c664e32cfaf8316bb232ae77bb08f459f2a` |
| **Network** | Starknet Mainnet |
| **Version** | v29 (Audit-Compliant) |
| **Audit** | Nethermind AuditAgent — January 2026 |
| **Starkscan** | [View Contract Class](https://starkscan.co/class/0x053f4f8791ed5bed0fddaa553d180c664e32cfaf8316bb232ae77bb08f459f2a) |

---

## 🔍 Security Audit

This contract was audited by **Nethermind AuditAgent** in January 2026. The audit identified 10 findings across the session key and outside execution logic. All valid findings have been fixed in this version:

| Severity | Findings | Status |
|----------|----------|--------|
| High | 5 | 3 fixed, 1 disputed (sequencer architecture), 1 accepted tradeoff |
| Medium | 2 | 1 invalid (false positive), 1 by design |
| Low | 1 | Fixed |
| Best Practice | 2 | Fixed |

**Key fixes applied**: session whitelist enforcement across all entry points, call-limit reset protection, session self-revocation guard, safe felt252-to-u64 conversion, and stale entrypoint cleanup.

Full report: [audit/nethermind-audit-2026-01.pdf](audit/nethermind-audit-2026-01.pdf)
Detailed responses: [AUDIT_RESPONSE.md](AUDIT_RESPONSE.md)

---

## 📖 Table of Contents

- [Security Audit](#-security-audit)
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

We use OpenZeppelin's `SRC9Component` but override `execute_from_outside_v2` with a **custom inline implementation** that adds session key support and SNIP-12 Rev 1 hashing:

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
4. Block admin selectors (upgrade, add/revoke session)
5. Check selector allowed (if whitelist exists)
6. Verify ECDSA signature
7. Increment calls_used counter
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
| **No Admin Access** | Sessions blocked from upgrade/add/revoke selectors regardless of whitelist |
| **No Indefinite Access** | Sessions have mandatory expiration |
| **No Runaway Usage** | Call limits prevent abuse of compromised keys |

### Non-Atomic Multicall (By Design)

The `__execute__` function uses best-effort execution: if a subcall fails, it returns an empty span for that call and continues. This is intentional — callers should check the results array for empty spans to detect partial failures. This differs from the atomic all-or-nothing pattern used by some account implementations.

### Production Hardening (v29)

- All Nethermind audit fixes applied (findings #1-#4, #8-#10)
- Debug events and debug contract removed
- Essential events only: `SessionKeyAdded`, `SessionKeyRevoked`, `OutsideExecutionExecuted`

---

## 🧪 Comprehensive Test Suite

### Test Results: 36/36 Passing

```bash
$ snforge test

Collected 36 test(s) from sessions_smart_contract package
Running 36 test(s) from tests/

# Session Validation Tests (15)
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

# Session Validation Edge Cases (6)
[PASS] test_session_max_calls_zero_immediately_exhausted
[PASS] test_double_revoke_same_session
[PASS] test_update_session_resets_calls_used
[PASS] test_multiple_concurrent_sessions_independent
[PASS] test_signature_length_5_returns_zero
[PASS] test_session_valid_at_exact_expiration_boundary

# Audit Fix Regression Tests (12)
[PASS] test_audit1_execute_rejects_unauthorized_caller
[PASS] test_audit1_execute_allows_self_caller
[PASS] test_audit2_validate_blocks_disallowed_selector
[PASS] test_audit3_session_blocked_from_upgrade
[PASS] test_audit3_session_blocked_from_add_session
[PASS] test_audit5_is_valid_signature_session_expired_returns_zero
[PASS] test_audit6_is_valid_signature_does_not_consume_calls
[PASS] test_audit7_execute_continues_after_failed_subcall
[PASS] test_audit8_session_blocked_from_revoke
[PASS] test_audit9_overflow_valid_until_returns_zero
[PASS] test_audit9_is_valid_signature_overflow_returns_zero
[PASS] test_audit10_update_session_clears_old_entrypoints

# SNIP-9 Compatibility Tests (3)
[PASS] test_snip9_version_returns_v2
[PASS] test_contract_info_shows_snip9_compatible
[PASS] test_session_keys_still_work_with_snip9

Tests: 36 passed, 0 failed, 0 ignored, 0 filtered out
```

### Test Categories

| Category | Tests | What It Covers |
|----------|-------|----------------|
| **Session Validation** | 15 | Add, revoke, expiry, limits, selectors, signatures, events |
| **Session Edge Cases** | 6 | Zero max_calls, double revoke, update reset, concurrent sessions, invalid sig lengths, expiration boundary |
| **Audit Fix Regressions** | 12 | One+ test per Nethermind finding: `__execute__` caller check, admin blocklist, whitelist enforcement, `is_valid_signature` read-only, non-atomic multicall, safe `try_into()`, stale entrypoint cleanup |
| **SNIP-9 Compatibility** | 3 | Version checks, interface detection, session+SNIP-9 integration |

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
git clone https://github.com/chipi-pay/sessions-smart-contract.git
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
  --class-hash 0x53f4f8791ed5bed0fddaa553d180c664e32cfaf8316bb232ae77bb08f459f2a \
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
    allowed_entrypoints: Array<felt252> // Whitelisted selectors (empty = all non-admin)
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
4. Ensure all 36 tests pass
5. Submit a pull request

---

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/chipi-pay/sessions-smart-contract/issues)

---

<p align="center">
  Built with ❤️ for the Starknet ecosystem
</p>
