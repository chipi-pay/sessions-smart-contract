# Deployment History

This document tracks all contract class declarations on Starknet mainnet.

---

## Latest: v32 — Audit 3 Fixes

- **Class Hash**: `0x35a2251aca25daba18a5d8950deffa8372a7d84774554e75283cb85552eebc9`
- **Contract Address**: `0x03062f8ec52749beae94daee793871e60a4f71fdee577e9d9fb0c61260024806`
- **Status**: Live (declared + upgraded)
- **Starkscan**: [View Contract Class](https://starkscan.co/class/0x035a2251aca25daba18a5d8950deffa8372a7d84774554e75283cb85552eebc9)
- **Voyager**: [View Contract Class](https://voyager.online/class/0x035a2251aca25daba18a5d8950deffa8372a7d84774554e75283cb85552eebc9)
- **Audits**:
  - Audit 1: Nethermind AuditAgent, January 2026
  - Audit 2: Nethermind AuditAgent, February 2026
  - Audit 3: Nethermind AuditAgent, February 2026 — [Full Report](audit/audit_agent_report_3_4bedc58d-5c45-4607-b61a-d3f040f8a783.pdf)
  - Audit 4: Nethermind AuditAgent, February 2026 — 0 findings — [Full Report](audit/audit_agent_report_4_3d9877bd-6f4e-46c3-945d-32e3872e6264.pdf)

### What changed from v31

- **Audit 3 fix: `set_public_key`/`setPublicKey` blocklist** — OZ PublicKeyImpl owner rotation functions added to admin blocklist
- **Audit 3 fix: `execute_from_outside_v2` blocklist** — Nested SNIP-9 re-entry blocked for session keys
- **Audit 3 fix: Self-call block** — Sessions with empty whitelist cannot target the account contract at all, eliminating the entire class of self-call privilege escalation
- **Audit 3 fix: SRC-5 `ISessionKeyManager` registration** — Interface ID registered in constructor for paymaster/dApp discovery
- **Audit 3 fix: `valid_until` binding** — SNIP-9 path binds signature `valid_until` to stored session value
- **NatSpec documentation** — Comprehensive doc comments on all public and security-critical functions
- **Version string** — `get_contract_info` returns `'v32'`
- **Admin blocklist** — Expanded from 4 to 7 selectors + self-call block

### Audit 3 fixes applied (February 2026)

| # | Finding | Severity | Status |
|---|---------|----------|--------|
| 1 | `set_public_key`/`setPublicKey` not in admin blocklist | High | Fixed (blocklist + self-call block) |
| 2 | Duplicate of #1 (filed against test file) | High | Duplicate (same fix) |
| 3 | Nested `execute_from_outside_v2` double-consumption | Low | Fixed (blocklist + self-call block) |
| 4 | Missing SRC-5 interface registration | Low | Fixed (register in constructor) |
| 5 | Malleable `valid_until` in SNIP-9 session path | Info | Fixed (bind to stored session) |

See [AUDIT_RESPONSE_3.md](AUDIT_RESPONSE_3.md) for detailed responses.

---

### v31 — Audit 2 Fixes (February 2026)
- **Class Hash**: `0x254f6dd0427319ec614c29e4e3929500d1ba95d0da87ff81d67051ce572667`
- **Status**: Superseded by v32 (does not include audit 3 fixes)
- **Notes**: Audit 1+2 fixes applied. Does NOT include: self-call block, set_public_key blocklist, SRC-5 registration, valid_until binding.
- **Voyager**: [View](https://voyager.online/class/0x00254f6dd0427319ec614c29e4e3929500d1ba95d0da87ff81d67051ce572667)

---

## Upgrading Existing Contracts

To upgrade existing contracts to v32:

```bash
sncast --account deployer_oz \
  --accounts-file ~/.starknet_accounts/starknet_open_zeppelin_accounts.json \
  invoke \
  --contract-address <YOUR_DEPLOYED_CONTRACT_ADDRESS> \
  --function upgrade \
  --calldata 0x35a2251aca25daba18a5d8950deffa8372a7d84774554e75283cb85552eebc9 \
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
