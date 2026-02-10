# AuditAgent Scan Response (Report 2)

## Audit Information
- **Auditor**: Nethermind AuditAgent (Scanned Code Report)
- **Date**: February 06, 2026
- **Commit audited**: 8251abfd...b90e129a
- **Contracts in scope**: src/account.cairo, src/lib.cairo, tests/test_audit_fixes.cairo, tests/test_session_validation.cairo, tests/test_snip9_compatibility.cairo
- **Full report**: [audit/audit_agent_report_2_acedcc33-1159-4f2d-939a-cb04b84ff85c.pdf](audit/audit_agent_report_2_acedcc33-1159-4f2d-939a-cb04b84ff85c.pdf)

## Summary

| # | Finding | Severity | Our Assessment | Status |
|---|---------|----------|----------------|--------|
| 1 | Session keys can bypass whitelist/admin blocklist via nested `__execute__` | High | **AGREE** | FIXED |
| 2 | Session signature does not bind full tx envelope | Medium | **AGREE (Risk Accepted)** | OPEN |
| 3 | `execute_from_outside_v2` consumes call before validation | Low | **AGREE** | FIXED |

## Detailed Responses

### Finding #1: Session keys can bypass whitelist/admin blocklist via nested `__execute__` (HIGH) — AGREE

**Claim**: A session can call the account’s `__execute__` as a top-level call, then pass arbitrary nested calls. Because the nested `__execute__` sees the account as the caller, it can run admin selectors and bypass whitelist constraints.

**Our Response**: We agree this is a valid privilege-escalation path if a session key can call `__execute__` directly. The report’s exploit path is credible because the current selector checks only the top-level call(s). This violates the intended isolation guarantees for session keys.

**Impact**: A session key can gain owner-equivalent privileges (upgrade, add/revoke session keys, or call non-whitelisted selectors) by nesting calls.

**Fix implemented**:
- `__execute__` is now blocked for session calls at the selector level, preventing nested execution bypass.

---

### Finding #2: Session signature does not bind full tx envelope (MEDIUM) — AGREE (Risk Acceptance Possible)

**Claim**: Session signatures cover `(calls, nonce, chain_id, valid_until)` but not full tx envelope fields (fee/resource bounds/tip/paymaster-related fields). A relayer could reuse a signature with modified fee parameters.

**Our Response**: We agree this is a valid integrity gap. While it does not change the calls or calldata, it can alter fee-related parameters without the session signer’s explicit consent.

**Risk Consideration**: We are intentionally keeping the current session hash (no envelope binding) to preserve Chipi Paymaster compatibility. This is an accepted risk for now; we will re-evaluate once session-key standards or paymaster alignment is clarified.

**Planned Fix Options**:
- Include envelope fields (fee/resource bounds/tip/paymaster fields) in the session message hash when available.
- Add constraints or policy checks for relayer parameters.

---

### Finding #3: `execute_from_outside_v2` consumes call before validation (LOW) — AGREE

**Claim**: `_consume_session_call` is invoked before signature validation in `execute_from_outside_v2`, causing an off-by-one failure for `max_calls = 1` and reducing available calls by one for other sessions.

**Our Response**: We agree this is a correctness bug. The sequence differs from `__validate__` and can break single-use session keys with paymasters.

**Fix implemented**:
- `_consume_session_call` now runs after successful signature validation in `execute_from_outside_v2`, matching `__validate__`.

---

## Production Readiness

Findings #1 and #3 are fixed in v31. Finding #2 (session hash scope) is an **accepted risk** for paymaster compatibility — session signatures bind calls, calldata, nonce, chain_id, and expiration but not fee parameters. In the paymaster flow, users do not pay gas, so fee manipulation by a relayer has no economic impact on the signer. See [README.md — Session Hash Scope](README.md#session-hash-scope) for the full rationale.

**Next steps**:
- Re-evaluate envelope binding once session-key standards or paymaster alignment is clarified.
- Keep the regression tests for nested execution blocking and `execute_from_outside_v2` behavior.
- Re-run a targeted review or rescan after any future hash-format change.
- ~~Submit to a third auditor for independent verification before final production release.~~ Done — audits 3 and 4 completed, audit 4 returned 0 findings. See [AUDIT_RESPONSE_3.md](AUDIT_RESPONSE_3.md) and [AUDIT_RESPONSE_4.md](AUDIT_RESPONSE_4.md).

