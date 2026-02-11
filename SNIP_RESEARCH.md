# Session Keys on Starknet: An Ecosystem Position Paper

**Authors**: Chipi Pay
**Date**: February 6, 2026
**Repository**: [github.com/chipi-pay/sessions-smart-contract](https://github.com/chipi-pay/sessions-smart-contract)

---

## 1. Introduction

### What Chipi Pay Built

Chipi Pay has built and deployed a **full-stack production system** for gasless, delegated transactions on Starknet:

- **Session Account Contract** (Cairo) — On-chain session key validation with time limits, call limits, and selector whitelists
- **Modified Paymaster Backend** (Rust) — Forked from AVNU's paymaster, adapted for OpenZeppelin-based session accounts
- **Forwarder Contract** (Cairo) — Whitelisted relayer that routes sponsored transactions

The system is live on Starknet mainnet with class hash `0x35a2251aca25daba18a5d8950deffa8372a7d84774554e75283cb85552eebc9` (v32), audited four times by Nethermind (January and February 2026, final scan: 0 findings), and backed by 46 passing tests.

### The Full Stack

```
┌──────────┐   session sig   ┌──────────┐   SNIP-9 v2    ┌──────────┐
│   User   │ ─────────────→  │ Backend  │ ────────────→   │ Paymaster│
│ (no gas) │                 │ (relayer)│                  │  (AVNU)  │
└──────────┘                 └──────────┘                  └──────────┘
                                                                │
                                    execute_from_outside_v2     │
                                                                ▼
                                                          ┌──────────┐
                                                          │ Session  │
                                                          │ Account  │
                                                          └──────────┘
                                                                │
                                                          ┌──────────┐
                                                          │  Target  │
                                                          │ Contract │
                                                          └──────────┘
```

### Why This Research Exists

Every standard we depend on — SNIP-5, SNIP-6, SNIP-9, SNIP-12, SNIP-29 — has a story, authors, and trade-offs. Building production software on top of these standards revealed gaps that no single standard addresses: the interaction between session keys and paymasters. This document maps the ecosystem, identifies the gap, and makes the case for a unified standard.

---

## 2. The Standards Behind This Contract

### 2.1 SNIP-5 (SRC-5) — Interface Detection

| | |
|---|---|
| **What** | Standard interface detection, analogous to EIP-165 on Ethereum |
| **Authors** | OpenZeppelin |
| **Status** | Final |
| **How we use it** | `SRC5Component` declares support for SRC-6 and ISRC9_V2, enabling paymasters and dApps to discover account capabilities at runtime |

Our contract registers SNIP-5 interface IDs during construction via OpenZeppelin's `SRC5Component`. Any external contract can call `supports_interface(interface_id)` to determine whether the account supports session keys, outside execution, or standard account operations.

**Why it's necessary**: Without interface detection, paymasters cannot programmatically discover whether an account supports session signatures or SNIP-9 v2. They would have to hardcode class hashes — exactly the fragility a standard should prevent.

### 2.2 SNIP-6 (SRC-6) — Standard Account Interface

| | |
|---|---|
| **What** | Defines `__validate__`, `__execute__`, `__validate_deploy__`, `__validate_declare__`, and `is_valid_signature` |
| **Authors** | Starknet core contributors (reference implementation by OpenZeppelin) |
| **Status** | Final |
| **How we use it** | Custom `__validate__` with dual-path signature validation (owner 2-element, session 4-element); custom `__execute__` with caller check |

This is the foundation of Starknet's account abstraction. Every account contract implements SRC-6. Our implementation extends it with session key logic:

```cairo
fn __validate__(ref self: ContractState, calls: Array<Call>) -> felt252 {
    let signature = get_tx_info().unbox().signature;

    if signature.len() == 4 {
        // Session path: [session_pubkey, r, s, valid_until]
        // → check expiry → check permissions → verify ECDSA → increment counter
    }

    if signature.len() == 2 {
        // Owner path: [r, s] → delegate to OpenZeppelin
    }

    0 // Invalid format
}
```

We intentionally do NOT embed OpenZeppelin's `SRC6Impl` — we replace it entirely to intercept validation with session logic while delegating owner signatures to the underlying `AccountComponent`.

### 2.3 SNIP-9 — Outside Execution

| | |
|---|---|
| **What** | Allows a third party to submit transactions on behalf of an account, with the account's signature |
| **Authors** | Argent Labs (Julien Niset), AVNU, Braavos (delaaxe) |
| **Status** | Final (September 2023) |
| **How we use it** | Custom `execute_from_outside_v2` override with session whitelist enforcement and dual SNIP-12 hash support |

SNIP-9 is what makes gasless transactions possible. The paymaster constructs an `OutsideExecution` struct containing the user's calls, signs it with the session key, and submits it to the account. The account validates the signature and executes the calls.

**Our custom implementation adds three critical features**:

1. **Session whitelist enforcement before signature validation** — A session key cannot bypass selector restrictions by going through the SNIP-9 path
2. **Dual hash format support** — Tries OpenZeppelin's u128-timestamp hash first, falls back to our felt-timestamp format for forward compatibility
3. **Call consumption after validation** — The session call counter increments only after successful signature verification (audit fix)

```cairo
fn execute_from_outside_v2(ref self: ContractState, outside_execution: OutsideExecution, signature: Span<felt252>) {
    // 1. Validate caller (0 or ANY_CALLER)
    // 2. Validate execution time bounds
    // 3. Consume nonce (replay protection)
    // 4. SECURITY: Enforce session whitelist BEFORE signature check
    // 5. Try OZ hash → try felt hash → validate signature
    // 6. Consume session call AFTER validation
    // 7. Execute calls
}
```

### 2.4 SNIP-12 — Typed Data Hashing

| | |
|---|---|
| **What** | Off-chain typed data signing and on-chain hash verification, analogous to EIP-712 |
| **Authors** | — |
| **Status** | Final |
| **How we use it** | Dual hash computation: u128-timestamp format (OpenZeppelin / ecosystem standard) tried first, felt-timestamp format as fallback |

SNIP-12 is where the most painful incompatibility lives. Both OpenZeppelin's `SRC9Component` and our contract use SNIP-12 Revision 1. The difference is in how timestamp fields are typed in the TypedData struct:

- **u128 format** (OpenZeppelin / ecosystem standard): "Execute After" and "Execute Before" typed as `u128`
- **felt format** (early development / starknet.js): Same fields typed as `felt252`

Different field types produce different struct type hashes, which produce different message hashes, which break signature validation.

When a user signs an `OutsideExecution` message with one format's encoding and the contract validates with the other, the hashes don't match and the signature fails. This was the root cause of the initial integration difficulty: the account contract initially used `felt` for timestamps (producing a different struct type hash), while Argent/Braavos/standard OZ accounts only accept `u128`. The fix was switching the account's hash format to U128 (matching the OZ standard) and keeping dual-hash support in the contract as a compatibility bridge.

**The contract's solution**: Compute both hashes and try each:

```cairo
// Try OZ standard hash first (u128 timestamps — matches AVNU paymaster and all standard accounts)
let oz_hash = outside_execution.get_message_hash(get_contract_address());
let is_valid_oz = is_valid_signature(@self, oz_hash, sig_copy1);

// If OZ hash fails, try felt-timestamp format (forward compatibility)
if !is_valid_signature {
    let felt_hash = self._compute_outside_execution_hash(@outside_execution);
    // ... validate with this hash
}
```

The OZ hash (U128 timestamps) is tried first because it matches the current ecosystem standard. The felt-timestamp fallback exists for forward compatibility and for any future SNIP that standardizes felt-based timestamps.

**Our SNIP-12 felt-timestamp type hashes** (computed via `starknetKeccak`, used in the fallback path):

| Constant | Value |
|----------|-------|
| `OUTSIDE_EXECUTION_TYPE_HASH_REV1` | `0x5a4b49e17039355cd95d1f0981d75901191d1319b1f4b05a9a791d218d7e0c` |
| `CALL_TYPE_HASH_REV1` | `0x3635c7f2a7ba93844c0d064e18e487f35ab90f7c39d00f186a781fc3f0c2ca9` |
| `STARKNET_DOMAIN_TYPE_HASH_REV1` | `0x1ff2f602e42168014d405a94f75e8a93d640751d71d16311266e140d8b0a210` |

### 2.5 SNIP-29 — Paymaster Standard

| | |
|---|---|
| **What** | Standard interface for gas sponsoring on Starknet |
| **Authors** | AVNU |
| **Status** | Draft |
| **How we use it** | Integrated with AVNU's paymaster backend for gasless session transactions |

SNIP-29 defines how paymasters discover, sponsor, and settle gas fees. AVNU's reference implementation is the de facto standard. Integrating the session account with AVNU's paymaster revealed that proper account configuration is essential: correct SNIP-12 timestamp types (U128, not Felt) and proper SRC-5 interface registration are required for signature validation to succeed.

A development fork (`github.com/chipi-pay`, `openzep` branch, based on `github.com/avnu-labs/paymaster`) was created while debugging. After identifying that the root causes were on the account side (wrong timestamp types, missing SRC-5 registration), upstream PR [avnu-labs/paymaster#62](https://github.com/avnu-labs/paymaster/pull/62) was closed. AVNU's paymaster works correctly with properly configured accounts. Session signatures (4-element) pass through unmodified since AVNU already uses `Vec<Felt>` internally.

### 2.6 ERC-1271 — Signature Validation

| | |
|---|---|
| **What** | Standard interface for smart contract signature validation |
| **Origin** | Ethereum (EIP-1271) |
| **How we use it** | Read-only `is_valid_signature(hash, signature)` validates both owner (2-element) and session (4-element) signatures |

`is_valid_signature` is a read-only function (`@ContractState`) that validates signatures without executing calls or consuming session counters. This is critical for:

- Paymasters verifying signatures before gas commitment
- dApps verifying ownership or delegation off-chain
- Compatibility with any protocol that checks ERC-1271

**Important tradeoff (Nethermind audit finding #5)**: `is_valid_signature` receives only `(hash, signature)` — no call context. This means it cannot enforce selector whitelists. We enforce whitelists in `execute_from_outside_v2` where calls are available. This is an accepted architectural tradeoff for paymaster compatibility.

---

## 3. The Paymaster: What We Learned

### Integration Lessons

Integrating a custom OpenZeppelin-based session account with AVNU's paymaster revealed how implementation details — not paymaster bugs — cause integration failures. Two lessons emerged:

**Lesson 1: SNIP-12 Timestamp Type Mismatch**

The session account initially used `Felt` for the "Execute After" and "Execute Before" fields in SNIP-12 V2 TypedData. OpenZeppelin's `SRC9Component` uses `u128` for these fields. Different field types produce different struct type hashes, which produce different message hashes, which cause signature validation failure on any standard OZ/Argent/Braavos account.

The fix was switching the account's hash format to `U128` timestamps (matching the OZ standard). The session account's dual-hash check tries the OZ hash (U128) first, so it matches immediately.

**Lesson 2: SRC-5 Interface Registration**

AVNU's paymaster uses SRC-5 `supports_interface()` to detect SNIP-9 support. The session account initially did not register its SNIP-9 interface IDs via SRC-5 (this was identified and fixed in Nethermind's audit 3, finding #4). All major accounts (Ready, Braavos, OZ) properly register SNIP-9 V2 via SRC-5. A development fork added ABI-based fallback as a workaround while debugging, before the root cause was identified.

Notably, session signature passthrough was NOT a problem — AVNU already uses `Vec<Felt>` internally, so 4-element session signatures pass through unmodified.

### What the Development Fork Changed

A development fork (`openzep` branch) was created while debugging integration issues. The critical changes turned out to be on the account side (2 lines for timestamp types, proper SRC-5 registration). The fork also explored additional improvements:

| Change | Scope | Outcome |
|---|---|---|
| Timestamps: `Felt` → `U128` | Account + fork | **Root cause fix** — account's hash format needed to match OZ standard |
| SRC-5 interface registration | Account (v32) | **Root cause fix** — account needed proper SNIP-9 V2 registration |
| ABI-based fallback for version detection | Fork only | Workaround added while debugging; not needed when accounts register properly |
| Debug `println!` removal | Fork only | ~35 lines of logging removed for production |
| Custom forwarder with `execute_sponsored()` | Forwarder contract | Separate gas-bearing from sponsored flows |

### Compatibility Confirmed

AVNU's paymaster works correctly with properly configured accounts:
- **Chipi session accounts** (post-fix): Owner sig (2-element) + session sig (4-element)
- **Argent / Ready accounts**: SRC-5 detects V2, owner sig works
- **Braavos accounts**: SRC-5 detects V2, owner sig works
- **Any standard OZ account**: SRC-5 detects `execute_from_outside_v2`

### The Full Transaction Flow

```
1. User creates session key (owner signature, once)
   Account.add_or_update_session_key(pubkey, expiry, max_calls, selectors)

2. User signs operation with session key
   hash = poseidon(account, chain_id, nonce, valid_until, calls...)
   signature = ecdsa_sign(hash, session_private_key)

3. Backend builds OutsideExecution
   outside_execution = {
     caller: 0x0,          // ANY_CALLER
     nonce: random,
     execute_after: now - 1,
     execute_before: now + 3600,
     calls: user_calls
   }

4. Paymaster sponsors gas and submits
   SNIP-9 tx → Account.execute_from_outside_v2(outside_execution, [pubkey, r, s, valid_until])

5. Account validates and executes
   → Check caller (ANY_CALLER allowed)
   → Check time bounds
   → Consume nonce
   → Enforce session whitelist
   → Validate signature (try OZ U128 hash first, then felt hash fallback)
   → Consume session call
   → Execute user's calls
```

### The Forwarder Contract

The forwarder (`src/forwarder.cairo`) acts as a whitelisted intermediary between the paymaster backend and user accounts:

```cairo
trait IForwarder<TContractState> {
    // Gas-bearing: collects gas fees in ERC-20, returns remainder
    fn execute(ref self, account, entrypoint, calldata, gas_token, gas_amount) -> bool;

    // Sponsored: no gas collection, logs sponsor metadata
    fn execute_sponsored(ref self, account, entrypoint, calldata, sponsor_metadata) -> bool;
}
```

It uses AVNU's `WhitelistComponent` to restrict which relayer addresses can submit transactions, preventing unauthorized gas spending.

---

## 4. Why On-Chain Session Keys Matter

### The Trust Spectrum

The following table compares approaches on specific dimensions. No approach is strictly superior — each makes different tradeoffs:

| Property | On-Chain (Chipi Pay) | Backend Guardian (Argent) | Library-Based (Braavos) |
|----------|---------------------|--------------------------|------------------------|
| **Enforcement** | Contract rejects unauthorized calls | Backend guardian co-signs | Built on SNIP-9 externally |
| **Survives backend outage** | Yes | No | Partially |
| **Censorship resistant** | Yes | No | Depends on relayer |
| **Rules auditable** | All rules on-chain | Off-chain validation logic | Library source auditable |
| **Composable** | Other contracts can read session state | Via API | Limited |
| **Recovery** | Owner can always revoke/upgrade | Requires guardian availability | Requires key availability |
| **Gas overhead** | Higher (on-chain storage + checks) | Lower (off-chain validation) | Medium |

### Design Choices

Session key validation can live in different places, and each choice reflects a different set of priorities:

**On-chain validation** (e.g., Chipi Pay) stores session rules in contract storage. This makes session state readable by other contracts, verifiable by anyone, and independent of any backend. The tradeoff is higher gas cost and more complex contract logic.

**Off-chain guardian** (e.g., Argent) validates session parameters in a backend service that co-signs transactions. This is gas-efficient and battle-tested at scale. The tradeoff is that session enforcement depends on guardian availability, and other protocols cannot independently verify session state on-chain.

**Library-based** (e.g., Braavos) constructs session proofs externally and validates them via SNIP-9. This keeps the wallet contract simpler while enabling session functionality. The tradeoff is that composability depends on the library interface rather than on-chain storage.

Each approach serves real use cases well. On-chain validation suits DeFi and cross-protocol composability where trustlessness matters. Guardian models suit consumer wallets where UX and gas efficiency are priorities. Library approaches offer flexibility without contract changes.

A standard should accommodate all of them.

---

## 5. The Ecosystem — Teams and People

### OpenZeppelin

**Role**: Foundation layer — Cairo Contracts v2.0.0

OpenZeppelin's Cairo Contracts provide the building blocks: `AccountComponent`, `SRC5Component`, `SRC9Component`, and `UpgradeableComponent`. Our contract is built directly on these components.

Key contribution: The component model in Cairo Contracts v2.0.0 allows us to embed OpenZeppelin's battle-tested account logic while overriding specific functions (like `__validate__`) with custom session key logic. Without this architecture, every session key implementation would need to re-implement account basics from scratch.

**Team**: Martin Triay and the OpenZeppelin Cairo team.

### Argent Labs / Ready

**Role**: Pioneered session keys on Starknet (guardian model)

Argent's approach uses a backend guardian that co-signs session transactions. The guardian validates session parameters off-chain and provides a second signature. This is the most deployed session key implementation on Starknet.

Argent is also a co-author of SNIP-9, which means the outside execution standard was designed with their guardian model in mind.

**Relevant work**: Argent X wallet, Argent guardian model, SNIP-9 co-authorship.

### Braavos

**Role**: Open-source session keys library

Braavos published an open-source session keys library that builds on SNIP-9. Their approach uses externally-constructed session proofs that the wallet validates.

**Relevant work**: Braavos wallet, session keys library, SNIP-9 co-authorship (delaaxe).

### Cartridge

**Role**: Gaming infrastructure (Controller + passkeys)

Cartridge's Controller uses passkeys (WebAuthn) for authentication and has a session-like mechanism for gaming transactions. Their Flippy Flop demo achieved 127 TPS on Starknet, demonstrating that high-throughput session-based gaming is viable.

**Relevant work**: Cartridge Controller, Flippy Flop (127 TPS), gaming session infrastructure.

### AVNU

**Role**: Paymaster infrastructure (SNIP-29)

AVNU operates the primary paymaster infrastructure on Starknet and authored SNIP-29 (Paymaster Standard). They are also a co-author of SNIP-9. The reference implementation was tested and validated against their open-source paymaster at `github.com/avnu-labs/paymaster`.

**Relevant work**: AVNU DEX, paymaster API, SNIP-29, SNIP-9 co-authorship.

### Nethermind

**Role**: Security auditing

Nethermind audited the session account contract. Their AuditAgent performed four scans:
- **January 2026**: 10 findings (3 High fixed, 1 High disputed, 1 High accepted, 2 Medium resolved, 1 Low fixed, 2 Best Practice fixed)
- **February 2026 (scan 2)**: 3 findings (1 High fixed, 1 Medium accepted, 1 Low fixed)
- **February 2026 (scan 3)**: 5 findings (2 High fixed — 1 unique + 1 duplicate, 2 Low fixed, 1 Info fixed)
- **February 2026 (scan 4)**: 0 findings — clean bill of health

### Bibliotheca DAO

**Role**: First session key implementation on Starknet

Bibliotheca DAO built the original "Arcade Accounts" — the first session key implementation in the Starknet ecosystem. This originated from a collaboration between Chris Lexmond (Influence game) and Loaf (Loot Realms / Bibliotheca). Their work demonstrated the concept and inspired subsequent implementations.

### EthSign

**Role**: Forum proposal for function call delegation

In October 2024, EthSign proposed "Access Control for Function Call Delegation" on the Starknet community forum. While not a formal SNIP, it explored similar territory: restricting delegated access to specific function selectors with time and call limits.

---

## 6. The Gap: No Session Key Standard Exists

### The Current State

Every team has built their own session key implementation:

| Team | Approach | Signature Format | Hash Format | Paymaster Compatible |
|------|----------|-----------------|-------------|---------------------|
| **Argent** | Backend guardian | 3+ elements (with guardian sig) | Argent-specific | Yes (native) |
| **Braavos** | External library | Proof-based | Braavos-specific | Partial |
| **Cartridge** | Controller + passkeys | WebAuthn | Controller-specific | Yes (custom) |
| **Chipi Pay** | On-chain validation | 4 elements [pubkey, r, s, expiry] | Dual: OZ U128 + felt fallback | Yes (via AVNU) |
| **Bibliotheca** | Arcade Accounts | Custom | Custom | No |

These implementations are **mutually incompatible**. A dApp built for Argent sessions won't work with Braavos sessions. A paymaster built for one format can't validate another.

### Concrete Example: Production Integration Lessons

Integrating a custom session account with AVNU's paymaster demonstrated how small implementation mismatches cause cascading failures:
1. The account used `Felt` timestamps in SNIP-12 TypedData — mismatching OZ's `U128` struct type hash
2. The account did not register SNIP-9 V2 via SRC-5, causing interface detection to fail
3. The account's caller field was misconfigured for outside execution

A development fork was created while debugging, but all root causes were on the account side. After fixing the account (U128 timestamps, proper SRC-5 registration, correct caller field), AVNU's paymaster works correctly. Upstream PR [avnu-labs/paymaster#62](https://github.com/avnu-labs/paymaster/pull/62) was closed after confirming this. The experience underscores why a standard matters: clear specification of hash formats, interface registration, and signature conventions would prevent these integration issues entirely.

### What a Standard Unlocks

**Cross-wallet interoperability**: A session key created in Argent could be validated by Braavos. A Cartridge session could work with AVNU's paymaster. Any compliant wallet could use any compliant paymaster.

**Unified dApp SDKs**: Instead of building separate integrations for each wallet's session format, dApp developers could target a single standard interface.

**Shared audit surface**: Instead of every team auditing their own session implementation, the community could focus audit resources on one reference implementation and its deviations.

**Paymaster compatibility**: The most immediate practical benefit. Any paymaster implementing the standard could sponsor transactions for any session-enabled account, without forking.

---

## 7. Real-World Impact

Session keys are not just a UX convenience — they are a network usage multiplier. Every confirmation popup a user skips is a transaction that happens instead of being abandoned. Every gasless session is a user who stays instead of churning. The primitives defined here — time-limited delegation, call-limited authorization, selector-restricted access, and gasless submission — directly increase the number of transactions flowing through the network.

### Passkeys + Session Keys: The Full UX Stack

Starknet's account ecosystem is converging on native passkeys (WebAuthn/secp256r1) for owner authentication. Braavos' Hardware Signer uses the device's Secure Enclave for P256 signing. Cartridge's Controller uses WebAuthn passkeys for seedless onboarding. In the [SNIP-6 forum discussion](https://community.starknet.io/t/snip-starknet-standard-account/95665), Xiang (April 2024) confirmed implementing native passkeys and endorsed the `Array<felt252>` signature format to support them.

This matters because passkeys and session keys are complementary layers:

| Layer | Problem | Solution |
|---|---|---|
| **Authentication** (passkeys) | "How do I prove I own this account?" | Biometrics (Face ID, fingerprint) via secp256r1 |
| **Authorization** (session keys) | "What can a delegate do on my behalf?" | Time-limited, call-limited, selector-restricted delegation |
| **Sponsorship** (paymaster) | "Who pays for gas?" | SNIP-9 outside execution + SNIP-29 paymaster |

Passkeys solve onboarding — no seed phrases, just biometrics. Session keys solve interaction — no popups, just scoped delegation. Together they make self-custodial wallets indistinguishable from Web2 apps. Cartridge's Flippy Flop demonstrated this full stack in production: passkey for login, session key for gameplay, paymaster for gas — 127 TPS with zero user friction.

Critically, session keys are independent of the owner's authentication method. An account that uses passkeys for owner auth can implement `ISessionKeyManager` without modification — the owner creates sessions via passkey signature, and the session key itself uses lightweight Stark-curve ECDSA for programmatic signing. This separation means session key standardization benefits the entire ecosystem regardless of which authentication methods individual wallets adopt.

### Gaming

Session keys are critical for blockchain gaming, where users make frequent, low-value transactions that cannot each require a wallet popup.

- **Flippy Flop** (Cartridge): Achieved 127 TPS on Starknet during stress test, demonstrating session-based gaming at scale
- **Loot Survivor** (Bibliotheca DAO): One of the first games to use session keys on Starknet
- **Eternum** (Bibliotheca DAO): On-chain strategy game leveraging delegated execution
- **Influence** (Chris Lexmond): Space industry game that drove early session key development

The Starknet Foundation's **Propulsion Program** is actively funding gaming projects (up to $1M per project, 20+ projects), most of which will need session key functionality.

### DeFi

Session keys enable automated DeFi strategies without giving full account access:

- **Limit orders**: Session key authorized to call `execute_order` on a specific DEX
- **Dollar-cost averaging (DCA)**: Session key with time-based recurring authorization
- **Yield optimization**: Session key restricted to `deposit`, `withdraw`, `harvest` selectors
- **Portfolio rebalancing**: Session key with call limits matching rebalance frequency

### Payments

Visa's December 2022 proof-of-concept on Starknet demonstrated automated payments using account abstraction. Session keys extend this: a subscription service could hold a session key authorized to call `transfer` once per month, with a fixed maximum amount per call encoded in the calldata whitelist.

### The Common Thread

Every use case requires the same primitives:
1. Time-limited delegation
2. Call-limited authorization
3. Selector-restricted access
4. Gasless submission via paymaster

A standard that codifies these primitives would serve all of them.

### AI Agents

Autonomous AI agents are the fastest-growing use case for delegated on-chain access. AI crypto tokens grew from ~$9B to ~$27B market cap in 2025, and Gartner projects AI agents will touch $30T in transactions by 2030. As Brian Armstrong noted: "AI agents cannot get bank accounts, but they can get crypto wallets."

Session key primitives map directly to agent authorization needs:

| Session Key Primitive | Agent Need | Example |
|---|---|---|
| `valid_until` | Time-bounded access | Trading bot active only during market hours |
| `max_calls` | Rate limiting | Prevent runaway execution loops |
| `allowed_entrypoints` | Function scoping | Agent can only call `swap`, not `transfer` |
| `revoke_session_key` | Kill switch | Emergency shutdown of misbehaving agent |
| Non-custodial delegation | Key separation | Agent never holds the owner key |

**Starknet-specific projects** already building in this direction:
- **Giza** — Autonomous DeFi agents using session keys + account abstraction for verifiable ML inference on-chain
- **Snak / Starknet Agent Kit** (KasarLabs) — Plugin architecture for AI agents with session key security for on-chain operations
- **Eliza Framework** — Starknet plugin enabling conversational AI agents to execute on-chain transactions

**Broader industry context**: a16z's "Agency by Design" framework identifies scoped delegation as essential for safe AI agent deployment. Safe's AI agent economy already drives >50% of Gnosis Chain transactions. Coinbase's AgentKit and ERC-8004 (Trustless Agents) are establishing similar patterns on Ethereum.

Starknet has a structural advantage here: native account abstraction means agents don't need EOA workarounds. Session keys are the authorization layer that makes this safe. A standard session key interface enables any compliant agent framework to work with any compliant wallet — the same interoperability benefit that motivates this SNIP for human users applies equally to autonomous agents.

Starknet's official positioning reflects this direction: the [verifiable AI agents portal](https://www.starknet.io/verifiable-ai-agents/) and the Agents Gizathon hackathon signal ecosystem commitment. The 2025 Ecosystem Report shows growth from 72 to 193 projects (168%), with AI agent infrastructure as a key vertical.

---

## 8. Our Journey

### Starting Point

We started from OpenZeppelin's `AccountComponent` — the standard Starknet account implementation. The goal was simple: let users interact with our dApp without paying gas or signing every transaction.

### Phase 1: Session Key Validation

Extended `__validate__` with dual-path signature validation:
- 2-element signatures → owner path (delegate to OZ)
- 4-element signatures → session path (custom validation)

Added on-chain storage for session data:
```cairo
session_keys: Map<felt252, SessionData>        // pubkey → {valid_until, max_calls, calls_used, entrypoints_len}
session_entrypoints: Map<(felt252, u32), felt252>  // (pubkey, index) → selector
```

### Phase 2: SNIP-9 v2 Integration

Implemented custom `execute_from_outside_v2` override to support session signatures in the outside execution flow. This required:
- SNIP-12 felt-timestamp type hash computation (matching starknet.js)
- Session whitelist enforcement before signature validation
- Dual hash support (u128 format tried first + felt format fallback)

### Phase 3: Paymaster Integration

Integrated with AVNU's paymaster, creating a development fork (`openzep` branch) while debugging:
- Identified root cause: account used `Felt` timestamps instead of `U128` in SNIP-12 TypedData (2-line fix on account side)
- Identified root cause: account did not register SNIP-9 V2 via SRC-5 (fixed in audit 3)
- Fork added ABI-based fallback as workaround before root causes were found
- Built forwarder contract with whitelist and sponsored execution
- Upstream PR [#62](https://github.com/avnu-labs/paymaster/pull/62) closed after confirming AVNU's paymaster works correctly with properly configured accounts

### Phase 4: First Nethermind Audit (January 2026)

10 findings across the session key and outside execution logic:
- **3 High findings fixed**: Session whitelist enforcement (#2, #4), admin selector blocklist (#3, #8)
- **1 High disputed**: Unrestricted `__execute__` (#1) — added defense-in-depth caller check
- **1 High accepted**: Session keys as ERC-1271 signers (#5) — architectural tradeoff for paymaster compatibility
- **1 Medium invalid**: State modification in `is_valid_signature` (#6) — false positive (`@ContractState` is read-only)
- **1 Medium by design**: Non-atomic multicall (#7) — intentional best-effort execution
- **1 Low fixed**: Session can revoke sessions (#8) — blocked via admin selector blocklist
- **2 Best Practice fixed**: Safe type conversion (#9), stale entrypoint cleanup (#10)

### Phase 5: Second Nethermind Audit (February 2026)

3 additional findings:
- **1 High fixed**: Nested `__execute__` bypass (#1) — blocked `__execute__` selector for sessions
- **1 Medium accepted**: Session hash doesn't bind full tx envelope (#2) — accepted for paymaster compatibility, documented
- **1 Low fixed**: Call consumed before validation in SNIP-9 path (#3) — reordered to consume after validation

### Phase 6: Third Nethermind Audit (February 2026)

5 additional findings (2 High — same finding filed as duplicate, 2 Low, 1 Info):
- **1 High fixed**: `set_public_key`/`setPublicKey` not in blocklist (#1) — OZ owner rotation selectors added to blocklist
- **1 High duplicate**: Same as #1 (filed against test file)
- **1 Low fixed**: Nested `execute_from_outside_v2` double-consumption (#3) — selector added to blocklist
- **1 Low fixed**: Missing SRC-5 interface registration (#4) — `ISessionKeyManager` ID registered in constructor
- **1 Info fixed**: Malleable `valid_until` in SNIP-9 path (#5) — signature value bound to stored session

**Systemic fix**: Added self-call block — sessions with empty whitelist cannot target the account contract at all. This eliminates the entire class of privilege escalation via self-calls that audits 1→2→3 kept discovering (each audit found new OZ selectors not in the denylist).

### Phase 7: Fourth Nethermind Audit (February 2026)

0 findings. Clean report on v32 (commit `9be9629b`). The self-call block and expanded blocklist eliminated the systemic vulnerability class. Findings trajectory: **10 → 3 → 5 → 0**.

### Current State

- **Production on mainnet**: Class hash `0x35a2251aca25daba18a5d8950deffa8372a7d84774554e75283cb85552eebc9` (v32)
- **46 tests passing**: 21 session validation + 22 audit regression + 3 SNIP-9 compatibility
- **Four Nethermind audits**: All critical findings fixed, accepted tradeoffs documented, audit 4 returned 0 findings
- **Dependencies**: OpenZeppelin Cairo Contracts v2.0.0, AVNU Contracts Lib v0.1.0, Starknet >= 2.8.0

### Phase 8: Standards Submission

The SNIP process follows a defined lifecycle: **Draft → Review → Last Call (14 days) → Final**. The starting point is a forum thread at [community.starknet.io](https://community.starknet.io/c/development-proposals/snip/7), followed by a PR to [starknet-io/SNIPs](https://github.com/starknet-io/SNIPs).

This is a long-term effort. SRC standards like SNIP-6 (Standard Account), SNIP-9 (Outside Execution), and SNIP-12 (Typed Data) have been in Review for 2+ years. Core protocol changes with StarkWare backing can move in 3–6 months, but interface standards require broad ecosystem consensus. SNIP editors check format and completeness, not merit — community consensus determines adoption.

We welcome feedback from wallet teams, paymaster operators, dApp developers, and AI agent builders. A session key standard will only succeed if it accommodates the diversity of approaches that already exist in the ecosystem.

---

## 9. Acknowledgments

### OpenZeppelin

The foundation of everything. `AccountComponent`, `SRC5Component`, `SRC9Component`, `UpgradeableComponent` — these are the building blocks that make session key implementations possible without reinventing account abstraction from scratch. The component architecture in Cairo Contracts v2.0.0 is what allows us to extend standard account behavior with custom session logic while inheriting battle-tested security for everything else.

### Starknet Foundation

Thank you for creating the ecosystem where native account abstraction thrives. Through grants, the Propulsion Program, and the vision that blockchain UX should be invisible, you made it possible for builders like us to push boundaries. The Propulsion Program alone is funding 20+ gaming projects (up to $1M each), most of which will need session key functionality — standardization directly serves this cohort. The Foundation's grant infrastructure enabled this work to be built, audited, and proposed as a standard. The fact that session keys are even possible — natively, without L1 workarounds — is a testament to Starknet's architecture and the Foundation's commitment to advancing it.

### Nethermind

Four rigorous audits that found real vulnerabilities and made our contract significantly more secure. The nested `__execute__` bypass (audit 2, finding #1) and `set_public_key` account takeover (audit 3, finding #1) were particularly subtle privilege escalations that we would not have caught without their review. Audit 4 returned a clean report with 0 findings, confirming that the self-call block and expanded blocklist eliminated the systemic vulnerability class.

### AVNU

For building the paymaster infrastructure that makes gasless transactions practical, and for open-sourcing the codebase. The integration issues we encountered turned out to be on our side — incorrect caller fields, wrong timestamp types, and missing SRC-5 registration. AVNU's paymaster works correctly with properly configured accounts. Florian Bellotti's review of our upstream PR helped us identify the root causes. This experience is precisely why a standard matters: clear specification prevents integration mismatches.

### The SNIP-9 Authors

Julien Niset (Argent), delaaxe (Braavos), and AVNU — for designing the outside execution standard that makes paymaster-sponsored sessions possible. SNIP-9 is arguably the most critical enabler of gasless UX on Starknet.

### Bibliotheca DAO

For building the first session key implementation (Arcade Accounts) and proving the concept before anyone else. Chris Lexmond and Loaf showed the ecosystem what was possible.

---

## Appendix A: Contract Interface Summary

```cairo
#[derive(Drop, Copy, Serde, starknet::Store)]
pub struct SessionData {
    pub valid_until: u64,
    pub max_calls: u32,
    pub calls_used: u32,
    pub allowed_entrypoints_len: u32,
}

#[starknet::interface]
pub trait ISessionKeyManager<TContractState> {
    fn add_or_update_session_key(
        ref self: TContractState,
        session_key: felt252,
        valid_until: u64,
        max_calls: u32,
        allowed_entrypoints: Array<felt252>
    );
    fn revoke_session_key(ref self: TContractState, session_key: felt252);
    fn get_session_data(self: @TContractState, session_key: felt252) -> SessionData;
}
```

## Appendix B: Admin Selector Blocklist

The following selectors are blocked for ALL session keys, regardless of whitelist configuration:

| Selector | Function | Reason | Added |
|----------|----------|--------|-------|
| `selector!("upgrade")` | Contract upgrade | Prevents session key from replacing contract code | Audit 1 |
| `selector!("add_or_update_session_key")` | Session creation | Prevents session key from creating new sessions | Audit 1 |
| `selector!("revoke_session_key")` | Session revocation | Prevents session key from revoking other sessions | Audit 1 |
| `selector!("__execute__")` | Nested execution | Prevents privilege escalation via nested call routing | Audit 2 |
| `selector!("set_public_key")` | Owner key rotation | Prevents account takeover via OZ PublicKeyImpl | Audit 3 |
| `selector!("setPublicKey")` | Owner key rotation (camel) | Prevents account takeover via OZ PublicKeyCamelImpl | Audit 3 |
| `selector!("execute_from_outside_v2")` | Nested SNIP-9 | Prevents double nonce/call consumption | Audit 3 |

**Self-call block (v32)**: In addition to the blocklist, sessions with `allowed_entrypoints_len == 0` (empty whitelist) cannot target the account contract at all (`call.to != get_contract_address()`). This eliminates the entire class of privilege escalation via self-calls.

## Appendix C: Test Coverage Summary

| Category | Count | Coverage |
|----------|-------|----------|
| Session Validation | 21 | Add, revoke, expiry, limits, selectors, signatures, events, edge cases |
| Audit 1+2 Fix Regressions | 14 | One or more tests per Nethermind finding from audits 1 and 2 |
| Audit 3 Fix Regressions | 8 | Blocklist expansion, self-call block, SRC-5 registration, external call allowance |
| SNIP-9 Compatibility | 3 | Version checks, interface detection, session + SNIP-9 integration |
| **Total** | **46** | |
