# AuditAgent Scan Response (Report 3)

## Audit Information
- **Auditor**: Nethermind AuditAgent (Scanned Code Report)
- **Date**: February 10, 2026
- **Commit audited**: 6424aa0b...af802805 (v31)
- **Contracts in scope**: src/account.cairo, src/lib.cairo, tests/test_audit_fixes.cairo, tests/test_session_validation.cairo, tests/test_snip9_compatibility.cairo
- **Full report**: [audit/audit_agent_report_3_4bedc58d-5c45-4607-b61a-d3f040f8a783.pdf](audit/audit_agent_report_3_4bedc58d-5c45-4607-b61a-d3f040f8a783.pdf)

## Summary

| # | Finding | Severity | Our Assessment | Status |
|---|---------|----------|----------------|--------|
| 1 | `set_public_key`/`setPublicKey` not in admin blocklist — account takeover | High | **AGREE** | FIXED |
| 2 | Duplicate of #1 (filed against test file) | High | **DUPLICATE** | FIXED |
| 3 | Double-consumption via nested `execute_from_outside_v2` | Low | **AGREE** | FIXED |
| 4 | Missing SRC-5 interface registration for custom interfaces | Low | **AGREE** | FIXED |
| 5 | Malleable `valid_until` in `execute_from_outside_v2` session signatures | Info | **AGREE** | FIXED |

## Detailed Responses

### Finding #1: `set_public_key`/`setPublicKey` not in admin blocklist (HIGH) — AGREE

**Claim**: A session key with an empty whitelist can call `set_public_key` or `setPublicKey` (OZ `PublicKeyImpl`/`PublicKeyCamelImpl`) on the account contract, rotating the owner key and achieving full account takeover.

**Our Response**: We agree this is a valid privilege escalation path. OpenZeppelin's `AccountComponent` embeds `PublicKeyImpl` and `PublicKeyCamelImpl` which expose `set_public_key`/`setPublicKey`. These functions require `assert_only_self()`, which is satisfied when the account calls itself via `__execute__`. A session with an empty whitelist could previously target these selectors.

**Impact**: Complete account takeover — a session key could rotate the owner's public key and gain permanent owner-level control.

**Fix implemented (v32)**:
1. **Blocklist expansion**: Added `selector!("set_public_key")` and `selector!("setPublicKey")` to the admin selector blocklist in `_is_session_allowed_for_calls`.
2. **Self-call block**: Added a second protection layer — sessions with empty whitelist (`allowed_entrypoints_len == 0`) now CANNOT target the account contract at all. This eliminates the entire class of self-call privilege escalation. See [Systemic Fix](#systemic-fix-self-call-block) below.

---

### Finding #2: Duplicate of #1 (HIGH) — DUPLICATE

Filed against the test file. Same vulnerability as finding #1. Fixed by the same blocklist expansion and self-call block.

---

### Finding #3: Double-consumption via nested `execute_from_outside_v2` (LOW) — AGREE

**Claim**: A session key could call `execute_from_outside_v2` as a top-level call, resulting in double nonce consumption or double call-counter increments within a single transaction.

**Our Response**: We agree this is a valid re-entrancy vector. Although `execute_from_outside_v2` has its own nonce protection, allowing session keys to invoke it creates unexpected execution paths.

**Impact**: Potential double consumption of session calls or nonce confusion.

**Fix implemented (v32)**:
1. **Blocklist**: Added `selector!("execute_from_outside_v2")` to the admin selector blocklist.
2. **Self-call block**: The self-call block also prevents this since `execute_from_outside_v2` targets the account contract itself.

---

### Finding #4: Missing SRC-5 interface registration (LOW) — AGREE

**Claim**: The account contract does not register the `ISessionKeyManager` interface via SRC-5, preventing paymasters and dApps from discovering session key support programmatically.

**Our Response**: We agree. The contract uses `SRC5Component` and registers ISRC6 (via `account.initializer`) and ISRC9_V2 (via `src9.initializer`) but did not register `ISessionKeyManager`.

**Impact**: Paymasters and dApps cannot use `supports_interface()` to detect session key support, forcing them to use ABI-based fallback detection.

**Fix implemented (v32)**:
- Added `SRC5InternalImpl` import for `register_interface` access.
- Computed the `ISessionKeyManager` interface ID as the XOR of:
  - `starknetKeccak("add_or_update_session_key")`
  - `starknetKeccak("revoke_session_key")`
  - `starknetKeccak("get_session_data")`
- Result: `0x037ab4f01106526662a612eaa2926df2aa314c4144b964f183805880bbcfa55d`
- Registered in the constructor via `self.src5.register_interface(SESSION_KEY_MANAGER_ID)`.

---

### Finding #5: Malleable `valid_until` in `execute_from_outside_v2` (INFO) — AGREE

**Claim**: In the `execute_from_outside_v2` session path, the `valid_until` value from the signature is not validated against the stored session's `valid_until`. A relayer could extend the `valid_until` beyond what the session owner intended.

**Our Response**: We agree this is a valid integrity gap. While `__validate__` checks `valid_until` against the block timestamp, the SNIP-9 path did not bind the signature's `valid_until` to the stored session value.

**Impact**: A relayer could submit a session signature with an extended `valid_until`, potentially keeping a session alive beyond the stored expiration window (though it would still fail at block timestamp check once the session truly expires).

**Fix implemented (v32)**:
- In `execute_from_outside_v2`, after extracting `session_pubkey`, the signature's `valid_until` is now extracted, safely converted to `u64`, and asserted to be `<= session.valid_until`.
- This prevents a relayer from extending `valid_until` beyond the session's stored limit.

---

## Systemic Fix: Self-Call Block

### The Pattern: Denylist Whack-a-Mole

Across three audits, every High/critical finding has been the same class of vulnerability: a session key with an empty whitelist can call a privileged function on the account contract itself.

| Audit | What was missed | Root cause |
|-------|----------------|------------|
| Audit 1 | `upgrade`, `add_or_update_session_key`, `revoke_session_key` | No blocklist existed |
| Audit 2 | `__execute__` | `__execute__` not in blocklist |
| Audit 3 | `set_public_key`, `setPublicKey`, `execute_from_outside_v2` | OZ public key rotation not in blocklist |

Each audit found selectors we missed. The denylist approach is **fundamentally fragile** — every new OZ embedded implementation or future contract upgrade could expose new privileged selectors.

### The Solution: Self-Call Block

In v32, we added a second layer of protection:

> **When `allowed_entrypoints_len == 0` (open whitelist), sessions CANNOT target the account contract (`call.to == get_contract_address()`) at all.**

This eliminates the entire class of self-call privilege escalation:
- **Known selectors**: Still caught by the blocklist (defense-in-depth for explicit whitelists)
- **Unknown future selectors**: Caught by the self-call block (no need to update the blocklist)
- **External calls**: Unaffected — sessions with empty whitelist can still call any external contract

The blocklist remains as defense-in-depth for sessions with **explicit whitelists** (where the self-call block does not apply). But for the most common case (empty whitelist = "allow all user functions"), the self-call block provides complete protection.

### Why This Matters

Audit 4 should not find another missing selector — because the self-call block makes the blocklist irrelevant for the empty-whitelist case. This converts an open-ended problem (maintain a complete list of all privileged selectors) into a closed problem (block all self-calls for open sessions).

---

## Production Readiness

All 5 findings are fixed in v32. The self-call block provides systemic protection beyond individual selector fixes.

**Regression tests added** (8 new, 46 total):
- `test_audit3_session_blocked_from_set_public_key` — set_public_key blocked
- `test_audit3_session_blocked_from_setPublicKey` — camelCase variant blocked
- `test_audit3_session_blocked_from_execute_from_outside_v2` — nested SNIP-9 blocked
- `test_audit3_session_blocked_self_call_generic` — ANY self-call blocked (proves self-call block)
- `test_audit3_session_allows_external_call_with_empty_whitelist` — external calls still work
- `test_audit3_session_explicit_whitelist_allows_external` — explicit whitelist unchanged
- `test_audit3_src5_supports_session_interface` — SRC-5 registration works
- `test_audit3_src5_supports_unknown_returns_false` — unknown interface returns false
