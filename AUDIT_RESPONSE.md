# Nethermind Security Audit Response

## Audit Information
- **Auditor**: Nethermind AuditAgent (powered by Nethermind Security)
- **Date**: January 23, 2026
- **Commit audited**: 628a5122...0c4f71aa (v28)
- **Contracts in scope**: src/account.cairo, src/lib.cairo, src/outside_execution.cairo
- **Full report**: [audit/nethermind-audit-2026-01.pdf](audit/nethermind-audit-2026-01.pdf)

> **Note**: The audit was performed on the v28 codebase which had a separate `OutsideExecutionComponent` in `src/outside_execution.cairo`. All valid findings were fixed in the current production architecture, where outside execution logic is implemented inline in `src/account.cairo` using OpenZeppelin's `SRC9Component` with a custom `execute_from_outside_v2` override.
>
> **Update (February 2026)**: A second audit ([AUDIT_RESPONSE_2.md](AUDIT_RESPONSE_2.md)) found that `_consume_session_call` was called before signature validation in `execute_from_outside_v2`. This has been fixed in v31. The code snippets below reflect the audit 1 response as originally written.

## Summary

| # | Finding | Severity | Our Assessment | Status |
|---|---------|----------|----------------|--------|
| 1 | Unrestricted execute | High | **DISPUTED** | Defense-in-depth added |
| 2 | Session whitelist not enforced in is_valid_signature | High | Valid | FIXED |
| 3 | Call-limit bypass via reset | High | Valid | FIXED |
| 4 | Session whitelist not enforced in execute_from_outside | High | Valid | FIXED |
| 5 | Session keys as ERC-1271 signers | High | **ACCEPTED** | Documented tradeoff |
| 6 | State modification in is_valid_signature | Medium | **INVALID** | False positive |
| 7 | Non-atomic multicall | Medium | **BY DESIGN** | Documented |
| 8 | Session can revoke sessions | Low | Valid | FIXED |
| 9 | DoS via unsafe conversion | Best Practice | Valid | FIXED |
| 10 | Stale entrypoints | Best Practice | Valid | FIXED |

---

## Detailed Responses

### Finding #1: Unrestricted execute (HIGH) - DISPUTED

**Claim**: Anyone can call `__execute__` directly, bypassing `__validate__`.

**Our Response**: This finding misunderstands Starknet's account abstraction architecture.

On Starknet:
1. Transactions are account-centric, not destination-centric
2. Sequencer calls `__validate__` then `__execute__` on the SENDER's account only
3. An attacker cannot submit a TX targeting victim's `__execute__` directly

When sequencer calls `__execute__`, `get_caller_address()` returns `0`. When another contract calls it, `get_caller_address()` returns the caller's address.

**Defense-in-depth added** (v26):
```cairo
fn __execute__(ref self: ContractState, calls: Array<Call>) -> Array<Span<felt252>> {
    let caller = get_caller_address();
    assert(
        caller.is_zero() || caller == get_contract_address(),
        'Account: unauthorized caller'
    );
    self._execute_calls(calls)
}
```

---

### Finding #2 & #4: Session whitelist not enforced in SNIP-9 (HIGH) - FIXED

**Claim**: Session key whitelist is not enforced in `execute_from_outside_v2`.

**Our Response**: Valid finding. Fixed by implementing custom `execute_from_outside_v2`.

**Fix implemented** (v26):
```cairo
fn execute_from_outside_v2(...) {
    // For session signatures, enforce whitelist BEFORE signature validation
    if signature.len() == 4 {
        let session_pubkey = *signature.at(0);
        assert(
            self._is_session_allowed_for_calls(session_pubkey, outside_execution.calls),
            'Session: unauthorized selector'
        );
        self._consume_session_call(session_pubkey);
    }
    // ... validate signature and execute
}
```

**Verified on mainnet**: [TX 0x7ba00f...](https://voyager.online/tx/0x7ba00f0d799e01f6dd6cf963f9e59d6ca0949a918e39d7a473ef910000f5a6e)

---

### Finding #3 & #8: Session can call admin functions (HIGH/LOW) - FIXED

**Claim**: Sessions with empty whitelist can call `upgrade()`, `add_or_update_session_key()`, `revoke_session_key()`.

**Our Response**: Valid finding. Fixed by adding admin selector blocklist.

**Fix implemented** (v26):
```cairo
fn _is_session_allowed_for_calls(...) -> bool {
    // SECURITY: Block admin selectors - sessions can NEVER call these
    let UPGRADE_SELECTOR = selector!("upgrade");
    let ADD_SESSION_SELECTOR = selector!("add_or_update_session_key");
    let REVOKE_SESSION_SELECTOR = selector!("revoke_session_key");

    // Block admin functions regardless of whitelist
    for call in calls {
        if call.selector == UPGRADE_SELECTOR
            || call.selector == ADD_SESSION_SELECTOR
            || call.selector == REVOKE_SESSION_SELECTOR {
            return false;
        }
    }
    // ... continue with whitelist check
}
```

---

### Finding #5: Session keys as ERC-1271 signers (HIGH) - ACCEPTED TRADEOFF

**Claim**: `is_valid_signature` accepts session signatures for arbitrary hashes.

**Our Response**: This is an intentional architectural tradeoff for Paymaster compatibility.

**Rationale**:
1. Paymasters (SNIP-9) require `is_valid_signature` to validate session signatures
2. `is_valid_signature` receives only `(hash, signature)` - no call context available
3. We enforce whitelist in `execute_from_outside_v2` where calls ARE available
4. Admin selectors are blocked regardless (see #3/#8 fix)

**Mitigation**:
- SNIP-9 path enforces full whitelist
- Pure ERC-1271 callers cannot execute calls (only verify signatures)
- Admin functions blocked for all session keys

---

### Finding #6: State modification in is_valid_signature (MEDIUM) - INVALID

**Claim**: `is_valid_signature` calls `_consume_session_call`, modifying state.

**Our Response**: FALSE POSITIVE. The function signature uses `@ContractState` (read-only snapshot):

```cairo
fn is_valid_signature(
    self: @ContractState,  // <-- READ-ONLY reference
    hash: felt252,
    signature: Array<felt252>
) -> felt252
```

Cairo's type system prevents state modification with `@ContractState`. The function does NOT call `_consume_session_call()`.

---

### Finding #7: Non-atomic multicall (MEDIUM) - BY DESIGN

**Claim**: Failed subcalls don't revert the entire transaction.

**Our Response**: This is intentional behavior, now documented.

**Rationale**:
- Allows partial success in batch operations
- Caller can check results array for empty spans to detect failures
- Some use cases benefit from "best effort" execution

**Documentation added** to README explaining this behavior.

---

### Finding #9: DoS via unsafe conversion (BEST PRACTICE) - FIXED

**Claim**: `try_into().unwrap()` can panic on invalid values.

**Our Response**: Valid. Fixed with safe pattern matching.

**Fix implemented** (v26):
```cairo
// Before (vulnerable):
let valid_until: u64 = (*signature.at(3)).try_into().unwrap();

// After (safe):
let valid_until: u64 = match (*signature.at(3)).try_into() {
    Option::Some(v) => v,
    Option::None => { return 0; }
};
```

---

### Finding #10: Stale entrypoints (BEST PRACTICE) - FIXED

**Claim**: Old entrypoints not cleared when session updated to shorter whitelist.

**Our Response**: Valid. Fixed by clearing old entrypoints on update.

**Fix implemented** (v26): Clear existing entrypoints before writing new ones in `add_or_update_session_key()`.

---

## Verification

All fixes verified on Starknet mainnet:

| Test | Transaction |
|------|-------------|
| SNIP-9 Session (whitelist enforced) | [0x7ba00f...](https://voyager.online/tx/0x7ba00f0d799e01f6dd6cf963f9e59d6ca0949a918e39d7a473ef910000f5a6e) |
| Paymaster Owner Signature | [0x8520db...](https://voyager.online/tx/0x8520db3c33777f3efbbf1e0c8255bd1c5acf4c6a4c88afd01fefbadbd0e8b) |
| Paymaster Session Signature | [0x4f0e4d...](https://voyager.online/tx/0x4f0e4dd3bc3c172ed6151f270b1ea7385eefa334017d9502d470aaa2b639361) |

**Production Contract**: `0x03062f8ec52749beae94daee793871e60a4f71fdee577e9d9fb0c61260024806` (v31 pending — see [DEPLOYMENT.md](DEPLOYMENT.md))
