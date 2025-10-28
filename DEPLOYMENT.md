# Deployment History

This document tracks all contract class declarations on Starknet mainnet.

---

## Latest Class Declaration (v24 - SNIP-9 Session Key Fix)

### Deployment Information
- **Class Hash**: `0x3aa948f0a598caa2b913421e4e5ff31c6d0c590a91623d6364d71cf92d15bff`
- **Transaction Hash**: `0x637cf8169f52b9888582545741c0fdeacaf2c8d44cbeb0c4887331ad69baa0d`
- **Status**: ✅ Declared on L2
- **Date**: October 28, 2025
- **Starkscan Links**:
  - Class: https://starkscan.co/class/0x03aa948f0a598caa2b913421e4e5ff31c6d0c590a91623d6364d71cf92d15bff
  - Transaction: https://starkscan.co/tx/0x0637cf8169f52b9888582545741c0fdeacaf2c8d44cbeb0c4887331ad69baa0d

### Key Changes in Version 24 (October 28, 2025)

#### 🔧 Fixed: SNIP-9 Outside Execution with Session Keys

**Problem**: 
When using SNIP-9's `execute_from_outside` function with session key signatures (4-element signatures), the validation failed because the `is_valid_signature` function only accepted 2-element owner signatures. This caused:
- ❌ Paymaster transactions with session keys to fail
- ❌ SNIP-9 outside execution with sessions to not execute inner calls
- ❌ Incomplete SNIP-9 v2 compatibility

**Root Cause**:
OpenZeppelin's SRC9Component validates signatures through ERC-1271's `is_valid_signature` function, NOT through the custom `__validate__` function. The `is_valid_signature` implementation only validated owner signatures (2 elements), completely rejecting session signatures (4 elements).

**Solution**:
Updated both `is_valid_signature` implementations (internal SRC6 trait and external ERC-1271 function) to handle:
- ✅ 2-element owner signatures: `[r, s]`
- ✅ 4-element session signatures: `[session_pubkey, r, s, valid_until]`

**Code Changes**:
- `src/account.cairo` lines 242-305: Internal `is_valid_signature` in SRC6Impl trait
- `src/account.cairo` lines 431-474: External `is_valid_signature` function (ERC-1271 compatible)

**Now Supports**:
- ✅ Full SNIP-9 v2 compatibility with session keys
- ✅ `execute_from_outside` with session authentication
- ✅ Paymaster integration with session keys
- ✅ All SNIP-9 integrations requiring session authorization

**Validation**:
- ✅ All 18 tests passing
- ✅ Compilation successful
- ✅ No linter errors

---

## Upgrading Existing Contracts

If you have deployed contracts using a previous class hash, you can upgrade them to this new version:

```bash
sncast --account deployer_oz \
  --accounts-file ~/.starknet_accounts/starknet_open_zeppelin_accounts.json \
  invoke \
  --contract-address <YOUR_DEPLOYED_CONTRACT_ADDRESS> \
  --function upgrade \
  --calldata 0x3aa948f0a598caa2b913421e4e5ff31c6d0c590a91623d6364d71cf92d15bff \
  --network mainnet
```

**Note**: Only the contract owner can call the `upgrade` function.

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

*(No previous mainnet deployments tracked)*

---

## Network Information

- **Network**: Starknet Mainnet
- **Chain ID**: `0x534e5f4d41494e` (SN_MAIN)
- **Deployer Account**: `0x064b1cf9c492b9ea333db7d4a2836feeee31cd1e2720f43b22732873122d433e`

---

## Documentation

- **Source Code**: `src/account.cairo`
- **Fix Explanation**: `SNIP9_SESSION_FIX.md`
- **Deploy Instructions**: `DEPLOY_INSTRUCTIONS.md`
- **Project README**: `README.md`

---

## Support & Links

- **Starknet Documentation**: https://docs.starknet.io/
- **OpenZeppelin Cairo**: https://docs.openzeppelin.com/contracts-cairo/
- **SNIP-9 Specification**: https://github.com/starknet-io/SNIPs/blob/main/SNIPS/snip-9.md
- **Starkscan Explorer**: https://starkscan.co/

