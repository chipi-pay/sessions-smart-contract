# Deployment History

This document tracks all contract class declarations on Starknet mainnet.

---

## Latest Class Declaration (v25 - Complete Paymaster + SNIP-9 Session Fix)

### Deployment Information
- **Class Hash**: `0x792915e08867ec1bd0f248ee82b9fdd5e9463d5949f9b82990d644e775103c3`
- **Transaction Hash**: `0x4c78993cc03deac57f31aec658e3ed238a1023bfe637ce275d0cedbb45d7aa6`
- **Status**: ✅ Declared on L2
- **Date**: October 28, 2025
- **Starkscan Links**:
  - Class: https://starkscan.co/class/0x0792915e08867ec1bd0f248ee82b9fdd5e9463d5949f9b82990d644e775103c3
  - Transaction: https://starkscan.co/tx/0x04c78993cc03deac57f31aec658e3ed238a1023bfe637ce275d0cedbb45d7aa6

### Key Changes in Version 25 (October 28, 2025)

#### 🔧 Fixed: TWO Critical Bugs Preventing Session Keys with Paymaster & SNIP-9

**Problem #1: `__validate__` Routing v1 Transactions Incorrectly**:
The `__validate__` function checked `version == 1` BEFORE checking signature length, routing ALL version 1 (paymaster) transactions to `AccountComponent.validate_transaction()`, which doesn't understand 4-element session signatures. This caused:
- ❌ Paymaster transactions with session keys: Validation passed but inner calls NOT executed
- ❌ Transaction succeeded but did nothing (no USDC transfer, no wave event)
- ❌ Empty 2nd internal call

**Root Cause #1**:
```cairo
// OLD BROKEN CODE
if version == 1 {
    return self.account.validate_transaction(); // ❌ All v1 routed here!
}
// Session check came after...
```

**Solution #1**:
Check signature length BEFORE checking version. Session signatures (4 elements) are now handled the same way for BOTH v1 (paymaster) and v3 (standard) transactions.

**Code Changes #1**:
- `src/account.cairo` lines 136-210: Moved session signature check (len == 4) BEFORE owner signature check
- Removed version-based routing that bypassed session validation

---

**Problem #2: `is_valid_signature` Only Accepting Owner Signatures**:
When using SNIP-9's `execute_from_outside` function with session key signatures (4-element signatures), the validation failed because the `is_valid_signature` function only accepted 2-element owner signatures. This caused:
- ❌ SNIP-9 outside execution with sessions to be rejected
- ❌ Incomplete SNIP-9 v2 compatibility

**Root Cause #2**:
OpenZeppelin's SRC9Component validates signatures through ERC-1271's `is_valid_signature` function, NOT through the custom `__validate__` function. The `is_valid_signature` implementation only validated owner signatures (2 elements), completely rejecting session signatures (4 elements).

**Solution #2**:
Updated both `is_valid_signature` implementations (internal SRC6 trait and external ERC-1271 function) to handle:
- ✅ 2-element owner signatures: `[r, s]`
- ✅ 4-element session signatures: `[session_pubkey, r, s, valid_until]`

**Code Changes #2**:
- `src/account.cairo` lines 242-305: Internal `is_valid_signature` in SRC6Impl trait
- `src/account.cairo` lines 431-474: External `is_valid_signature` function (ERC-1271 compatible)

**Now Supports**:
- ✅ **Paymaster + Session Keys**: Sponsored transactions with delegated access (Bug #1 fixed)
- ✅ **SNIP-9 Outside Execution + Sessions**: Third-party execution with session auth (Bug #2 fixed)
- ✅ Full SNIP-9 v2 compatibility with both owner and session signatures
- ✅ Session signatures work identically for v1 (paymaster) and v3 (standard) transactions
- ✅ All existing functionality preserved

**Validation**:
- ✅ All 18 tests passing
- ✅ Compilation successful
- ✅ No linter errors

**Detailed Analysis**: See `COMPLETE_BUG_FIX.md` for full explanation of both bugs and fixes

---

## Upgrading Existing Contracts

If you have deployed contracts using a previous class hash, you can upgrade them to this new version:

```bash
sncast --account deployer_oz \
  --accounts-file ~/.starknet_accounts/starknet_open_zeppelin_accounts.json \
  invoke \
  --contract-address <YOUR_DEPLOYED_CONTRACT_ADDRESS> \
  --function upgrade \
  --calldata 0x792915e08867ec1bd0f248ee82b9fdd5e9463d5949f9b82990d644e775103c3 \
  --network mainnet
```

**Note**: Only the contract owner can call the `upgrade` function.

**Important**: This version fixes critical bugs with paymaster and SNIP-9 session support. Upgrade recommended if you use session keys!

---

## Contract Features

This account contract includes:

### Core Features
- ✅ **Session Keys**: Temporary delegated access with configurable restrictions
- ✅ **SNIP-9 v2**: Full Outside Execution compatibility (now with session support!)
- ✅ **Upgradeable**: Can upgrade contract logic without changing address
- ✅ **SRC-5**: Interface detection support
- ✅ **SRC-6**: Standard account interface
- ✅ **ERC-1271**: Signature validation (now handles both owner and session signatures)

### Session Key Management
- Time-based expiration (`valid_until`)
- Call count limits (`max_calls`)
- Entrypoint restrictions (optional whitelist)
- Individual key revocation
- Owner-only management

### Signature Support
- **Owner Signatures** (2 elements): `[r, s]` - Full account control
- **Session Signatures** (4 elements): `[session_pubkey, r, s, valid_until]` - Delegated access

### Validation Paths
1. **`__validate__`**: For regular invoke transactions (v1 with paymaster, v3 standard)
2. **`is_valid_signature`**: For SNIP-9 outside execution and ERC-1271 validation

Both paths now support owner and session signatures! 🎉

---

## Testing

Run the test suite:

```bash
snforge test
```

Expected result: 18/18 tests passing

---

## Previous Deployments

### v24 - Partial SNIP-9 Session Key Fix (Superseded)
- **Class Hash**: `0x3aa948f0a598caa2b913421e4e5ff31c6d0c590a91623d6364d71cf92d15bff`
- **Date**: October 28, 2025
- **Status**: ⚠️ Superseded by v25
- **Issue**: Fixed `is_valid_signature` but not `__validate__` routing bug
- **Starkscan**: https://starkscan.co/class/0x03aa948f0a598caa2b913421e4e5ff31c6d0c590a91623d6364d71cf92d15bff

---

## Network Information

- **Network**: Starknet Mainnet
- **Chain ID**: `0x534e5f4d41494e` (SN_MAIN)
- **Deployer Account**: `0x064b1cf9c492b9ea333db7d4a2836feeee31cd1e2720f43b22732873122d433e`

---

## Documentation

- **Source Code**: `src/account.cairo`
- **Complete Fix Explanation**: `COMPLETE_BUG_FIX.md` (both bugs explained)
- **SNIP-9 Fix Only**: `SNIP9_SESSION_FIX.md` (bug #2 only)
- **Deploy Instructions**: `DEPLOY_INSTRUCTIONS.md`
- **Project README**: `README.md`

---

## Support & Links

- **Starknet Documentation**: https://docs.starknet.io/
- **OpenZeppelin Cairo**: https://docs.openzeppelin.com/contracts-cairo/
- **SNIP-9 Specification**: https://github.com/starknet-io/SNIPs/blob/main/SNIPS/snip-9.md
- **Starkscan Explorer**: https://starkscan.co/

