# Deployment History

This document tracks all contract class declarations on Starknet mainnet.

---

## Latest: v29 — Audit-Compliant (February 2026)

- **Class Hash**: `0x53f4f8791ed5bed0fddaa553d180c664e32cfaf8316bb232ae77bb08f459f2a`
- **Status**: Production
- **Audit**: Nethermind AuditAgent, January 2026 — [Full Report](audit/nethermind-audit-2026-01.pdf)
- **Starkscan**: [View Contract Class](https://starkscan.co/class/0x053f4f8791ed5bed0fddaa553d180c664e32cfaf8316bb232ae77bb08f459f2a)

### What changed from v28

- Restored v26.3 architecture (all logic in `account.cairo`, OZ `SRC9Component` with custom override)
- Applied all Nethermind audit fixes (#1-#4, #8-#10)
- Removed separate `OutsideExecutionComponent` (v28-only, superseded by inline implementation)
- Removed debug contract, redundant documentation, and utility scripts
- 18 tests passing

### Audit fixes applied

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

---

## Upgrading Existing Contracts

If you have deployed contracts using a previous class hash, upgrade to v29:

```bash
sncast --account deployer_oz \
  --accounts-file ~/.starknet_accounts/starknet_open_zeppelin_accounts.json \
  invoke \
  --contract-address <YOUR_DEPLOYED_CONTRACT_ADDRESS> \
  --function upgrade \
  --calldata 0x53f4f8791ed5bed0fddaa553d180c664e32cfaf8316bb232ae77bb08f459f2a \
  --network mainnet
```

**Note**: Only the contract owner can call `upgrade`.

---

## Previous Deployments

### v28 — Production Cleanup (December 4, 2025)
- **Class Hash**: `0x2de1565226d5215a38b68c4d9a4913989b54edff64c68c45e453c417b44cd83`
- **Status**: Superseded by v29
- **Notes**: Separate `OutsideExecutionComponent` architecture. Debug events removed. Missing audit fixes.
- **Starkscan**: [View](https://starkscan.co/class/0x02de1565226d5215a38b68c4d9a4913989b54edff64c68c45e453c417b44cd83)

### v26 — SRC6 Interface Fix (October 28, 2025)
- **Class Hash**: `0xad74b94d9891672cd49e11b2abe56ece9539fd02eedf2d4980537663277984`
- **Status**: Superseded by v28
- **Notes**: Fixed SRC6 interface for SNIP-9 compatibility. Base for audit-compliant code.
- **Starkscan**: [View](https://starkscan.co/class/0x00ad74b94d9891672cd49e11b2abe56ece9539fd02eedf2d4980537663277984)

### v25 — Paymaster + SNIP-9 Session Fix (October 28, 2025)
- **Class Hash**: `0x792915e08867ec1bd0f248ee82b9fdd5e9463d5949f9b82990d644e775103c3`
- **Status**: Superseded by v26
- **Starkscan**: [View](https://starkscan.co/class/0x0792915e08867ec1bd0f248ee82b9fdd5e9463d5949f9b82990d644e775103c3)

### v24 — Partial SNIP-9 Fix (October 28, 2025)
- **Class Hash**: `0x3aa948f0a598caa2b913421e4e5ff31c6d0c590a91623d6364d71cf92d15bff`
- **Status**: Superseded by v25
- **Starkscan**: [View](https://starkscan.co/class/0x03aa948f0a598caa2b913421e4e5ff31c6d0c590a91623d6364d71cf92d15bff)

---

## Network Information

- **Network**: Starknet Mainnet
- **Chain ID**: `0x534e5f4d41494e` (SN_MAIN)
- **Deployer Account**: `0x064b1cf9c492b9ea333db7d4a2836feeee31cd1e2720f43b22732873122d433e`
