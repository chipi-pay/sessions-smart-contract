# Deployment History

This document tracks all contract class declarations on Starknet mainnet.

---

## Latest: v31 — Audit 2 Fixes (Pending Declaration)

- **Class Hash**: `0x254f6dd0427319ec614c29e4e3929500d1ba95d0da87ff81d67051ce572667`
- **Contract Address**: `0x03062f8ec52749beae94daee793871e60a4f71fdee577e9d9fb0c61260024806`
- **Status**: Declared (pending upgrade)
- **Starkscan**: [View Contract Class](https://starkscan.co/class/0x00254f6dd0427319ec614c29e4e3929500d1ba95d0da87ff81d67051ce572667)
- **Voyager**: [View Contract Class](https://voyager.online/class/0x00254f6dd0427319ec614c29e4e3929500d1ba95d0da87ff81d67051ce572667)
- **Audits**:
  - Audit 1: Nethermind AuditAgent, January 2026 — [Full Report](audit/nethermind-audit-2026-01.pdf)
  - Audit 2: Nethermind AuditAgent, February 2026 — [Full Report](audit/audit_agent_report_2_acedcc33-1159-4f2d-939a-cb04b84ff85c.pdf)

### What changed from v30

- **Audit 2 fix: `__execute__` blocklist** — Session keys can no longer call `__execute__` to achieve nested execution privilege escalation
- **Audit 2 fix: call-consume ordering** — `_consume_session_call` now runs after signature validation in `execute_from_outside_v2`, preventing single-use session keys from being consumed on failed signatures
- **Dead code removal** — Deleted `_validate_session_for_calls` (superseded by `_is_session_allowed_for_calls` + `_consume_session_call`, lacked admin blocklist)
- **`is_valid_signature` consolidation** — External ERC-1271 entry point now delegates to `SRC6Impl::is_valid_signature`, eliminating duplicate logic
- **Version string** — `get_contract_info` returns `'v31'`
- **Comment cleanup** — Updated stale references to felt-timestamp primary path (now a fallback)

### Audit 1 fixes applied (January 2026)

| # | Finding | Severity | Status |
|---|---------|----------|--------|
| 1 | Unrestricted `__execute__` | High | Defense-in-depth caller check added |
| 2 | Session whitelist bypassed in `is_valid_signature` | High | Fixed |
| 3 | Call-limit bypass via `calls_used` reset | High | Fixed (admin blocklist) |
| 4 | Session whitelist bypassed in `execute_from_outside_v2` | High | Fixed |
| 5 | Session keys as ERC-1271 signers | High | Accepted tradeoff (documented) |
| 6 | State modification in `is_valid_signature` | Medium | Invalid (uses `@ContractState`) |
| 7 | Non-atomic multicall | Medium | By design (documented) |
| 8 | Session can revoke sessions | Low | Fixed (admin blocklist) |
| 9 | DoS via unsafe `unwrap()` | Best Practice | Fixed (safe match pattern) |
| 10 | Stale entrypoints on revoke | Best Practice | Fixed (clear before write) |

See [AUDIT_RESPONSE.md](AUDIT_RESPONSE.md) for detailed responses.

### Audit 2 fixes applied (February 2026)

| # | Finding | Severity | Status |
|---|---------|----------|--------|
| 1 | Session keys bypass blocklist via nested `__execute__` | High | Fixed (`__execute__` added to admin blocklist) |
| 2 | Session signature does not bind full tx envelope | Medium | Accepted risk (paymaster compatibility) |
| 3 | `execute_from_outside_v2` consumes call before validation | Low | Fixed (consume after validation) |

See [AUDIT_RESPONSE_2.md](AUDIT_RESPONSE_2.md) for detailed responses.

---

## Upgrading Existing Contracts

To upgrade existing contracts to v31:

```bash
sncast --account deployer_oz \
  --accounts-file ~/.starknet_accounts/starknet_open_zeppelin_accounts.json \
  invoke \
  --contract-address <YOUR_DEPLOYED_CONTRACT_ADDRESS> \
  --function upgrade \
  --calldata 0x254f6dd0427319ec614c29e4e3929500d1ba95d0da87ff81d67051ce572667 \
  --network mainnet
```

**Note**: Only the contract owner can call `upgrade`.

---

## Previous Deployments

### v30 — Audit 1 Compliant (February 2026)
- **Class Hash**: `0x72b77b033a874fa1b8f7ff52e18be8fb5ce01a00c59cd184ae15f5b29bc0e57`
- **Status**: Superseded by v31 (does not include audit 2 fixes)
- **Notes**: Audit 1 fixes applied. Does NOT include: `__execute__` blocklist, call-consume-after-validation fix, or dead code removal.
- **Voyager**: [View](https://voyager.online/class/0x072b77b033a874fa1b8f7ff52e18be8fb5ce01a00c59cd184ae15f5b29bc0e57)

### v29 — Audit-Compliant (February 2026)
- **Class Hash**: `0x53f4f8791ed5bed0fddaa553d180c664e32cfaf8316bb232ae77bb08f459f2a`
- **Status**: Superseded by v30
- **Notes**: All Nethermind audit 1 fixes (#1-#4, #8-#10). Custom SRC9 v2 with session enforcement.
- **Voyager**: [View](https://voyager.online/class/0x053f4f8791ed5bed0fddaa553d180c664e32cfaf8316bb232ae77bb08f459f2a)

### v28 — Production Cleanup (December 4, 2025)
- **Class Hash**: `0x2de1565226d5215a38b68c4d9a4913989b54edff64c68c45e453c417b44cd83`
- **Status**: Superseded by v29
- **Notes**: Separate `OutsideExecutionComponent` architecture. Debug events removed. Missing audit fixes.
- **Voyager**: [View](https://voyager.online/class/0x02de1565226d5215a38b68c4d9a4913989b54edff64c68c45e453c417b44cd83)

### v26 — SRC6 Interface Fix (October 28, 2025)
- **Class Hash**: `0xad74b94d9891672cd49e11b2abe56ece9539fd02eedf2d4980537663277984`
- **Status**: Superseded by v28
- **Notes**: Fixed SRC6 interface for SNIP-9 compatibility. Base for audit-compliant code.
- **Voyager**: [View](https://voyager.online/class/0x00ad74b94d9891672cd49e11b2abe56ece9539fd02eedf2d4980537663277984)

### v25 — Paymaster + SNIP-9 Session Fix (October 28, 2025)
- **Class Hash**: `0x792915e08867ec1bd0f248ee82b9fdd5e9463d5949f9b82990d644e775103c3`
- **Status**: Superseded by v26
- **Voyager**: [View](https://voyager.online/class/0x0792915e08867ec1bd0f248ee82b9fdd5e9463d5949f9b82990d644e775103c3)

### v24 — Partial SNIP-9 Fix (October 28, 2025)
- **Class Hash**: `0x3aa948f0a598caa2b913421e4e5ff31c6d0c590a91623d6364d71cf92d15bff`
- **Status**: Superseded by v25
- **Voyager**: [View](https://voyager.online/class/0x03aa948f0a598caa2b913421e4e5ff31c6d0c590a91623d6364d71cf92d15bff)

---

## Network Information

- **Network**: Starknet Mainnet
- **Chain ID**: `0x534e5f4d41494e` (SN_MAIN)
- **Deployer Account**: `0x064b1cf9c492b9ea333db7d4a2836feeee31cd1e2720f43b22732873122d433e`
