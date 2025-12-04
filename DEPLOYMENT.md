# Deployment History

This document tracks all contract class declarations on Starknet mainnet.

---

## Latest Class Declaration (v28 - Production Cleanup)

### Deployment Information
- **Class Hash**: `0x2de1565226d5215a38b68c4d9a4913989b54edff64c68c45e453c417b44cd83`
- **Transaction Hash**: `0x28ef63135484ce3d99c83298e0f054f9cc9194207fbea46b2eab9a5951af06d`
- **Status**: ✅ Declared on L2
- **Date**: December 4, 2025
- **Starkscan Links**:
  - Class: https://starkscan.co/class/0x02de1565226d5215a38b68c4d9a4913989b54edff64c68c45e453c417b44cd83
  - Transaction: https://starkscan.co/tx/0x028ef63135484ce3d99c83298e0f054f9cc9194207fbea46b2eab9a5951af06d

### Key Changes in Version 28 (December 4, 2025)

#### 🧹 Production Cleanup - Debug Code Removed

**Changes Made**:
1. **Removed Debug Events** from `account.cairo`:
   - Removed `DebugEvent`, `SignatureValidation`, `SessionValidationResult`, `ExecutionStarted`, `CallExecuted` event structs
   - Removed all debug `emit` calls from `__validate__`, `__execute__`, `is_valid_signature`, `_execute_calls`
   - Kept essential events: `SessionKeyAdded`, `SessionKeyRevoked`

2. **Removed Debug Events** from `outside_execution.cairo`:
   - Removed `OutsideExecutionValidation` event struct
   - Removed debug emits from `execute_from_outside_v2`
   - Kept essential event: `OutsideExecutionExecuted`

3. **Removed Dead Code**:
   - Removed unused `_validate_session_for_calls` function (superseded by `_is_session_allowed_for_calls` + `_consume_session_call`)

4. **Cleaned Up Comments**:
   - Removed outdated "FIX" and "DEBUG" comments
   - Simplified inline documentation

**Code Size Reduction**:
- `account.cairo`: ~803 lines → ~652 lines
- `outside_execution.cairo`: ~354 lines → ~311 lines

**No Functional Changes**:
- ✅ All existing functionality preserved
- ✅ All 38 tests passing
- ✅ SNIP-9 v2 compatibility maintained
- ✅ Session key support unchanged
- ✅ Paymaster compatibility unchanged

---

## Previous Deployment (v26 - Fixed SRC6 Interface Implementation)

### Deployment Information
- **Class Hash**: `0xad74b94d9891672cd49e11b2abe56ece9539fd02eedf2d4980537663277984`
- **Transaction Hash**: `0x432470f1a56249ccedbe4aeb4bb54db7cb8f975697f50fff772fc84f33cb037`
- **Status**: ⚠️ Superseded by v28
- **Date**: October 28, 2025
- **Starkscan Links**:
  - Class: https://starkscan.co/class/0x00ad74b94d9891672cd49e11b2abe56ece9539fd02eedf2d4980537663277984
  - Transaction: https://starkscan.co/tx/0x0432470f1a56249ccedbe4aeb4bb54db7cb8f975697f50fff772fc84f33cb037

### Key Changes in Version 26 (October 28, 2025)

#### 🔧 Fixed: SRC6 Interface Implementation for SNIP-9 Compatibility

**Problem**: 
Using `#[abi(per_item)]` + `#[generate_trait]` pattern didn't properly expose SRC6 functions for SNIP-9 outside execution. Additionally, `is_valid_signature` was incorrectly placed inside the SRC6Impl block.

**Issues Found**:
1. ❌ `is_valid_signature` was inside SRC6Impl (shouldn't be part of SRC6)
2. ❌ `#[external(v0)]` on each function with `#[abi(per_item)]` instead of `#[abi(embed_v0)]`
3. ❌ Missing debug events in `__execute__` and `_execute_calls`

**Solution**:
- ✅ Defined explicit `ISRC6<TContractState>` interface
- ✅ Changed to `#[abi(embed_v0)]` pattern for proper ABI exposure
- ✅ Removed `#[external(v0)]` attributes (handled by `#[abi(embed_v0)]`)
- ✅ Removed `is_valid_signature` from SRC6Impl (kept as separate external function)
- ✅ Added debug events to track execution flow

**Code Changes**:
- `src/account.cairo` lines 131-143: Added explicit ISRC6 interface definition
- `src/account.cairo` line 146: Changed to `#[abi(embed_v0)]`
- `src/account.cairo` lines 224-227: Added debug events to `__execute__`
- `src/account.cairo` lines 592-620: Added debug events to `_execute_calls`
- Removed duplicate `is_valid_signature` from SRC6Impl block

**Why This Matters**:
The `#[abi(embed_v0)]` pattern properly exposes all interface functions in the ABI, which is critical for SNIP-9's `execute_from_outside` to correctly call `__execute__` after signature validation.

---

### Previous Fixes (Included in v26)

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
  --calldata 0x2de1565226d5215a38b68c4d9a4913989b54edff64c68c45e453c417b44cd83 \
  --network mainnet
```

**Note**: Only the contract owner can call the `upgrade` function.

**Important**: v28 is a cleanup release with no functional changes - debug events removed for cleaner on-chain footprint. Upgrade recommended for production use.

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

Expected result: 38/38 tests passing

---

## Previous Deployments

### v25 - Complete Paymaster + SNIP-9 Session Fix (Superseded)
- **Class Hash**: `0x792915e08867ec1bd0f248ee82b9fdd5e9463d5949f9b82990d644e775103c3`
- **Date**: October 28, 2025
- **Status**: ⚠️ Superseded by v26
- **Issue**: Fixed validation logic but had SRC6 interface implementation issue
- **Starkscan**: https://starkscan.co/class/0x0792915e08867ec1bd0f248ee82b9fdd5e9463d5949f9b82990d644e775103c3

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

