# Production vs Debug Contract Comparison

## Overview

This project includes two account contract implementations:
- **`account.cairo`** - Production-safe, SNIP-9 compatible
- **`debug_account.cairo`** - Debug version with additional testing functions

## ✅ Production Contract: `account.cairo`

### Version
`v23_snip9_compatible`

### Features
- ✅ SNIP-9 v2 (Outside Execution) support
- ✅ Session key management
- ✅ Custom `__validate__` logic
- ✅ ERC-1271 signature validation
- ✅ Upgradeable
- ✅ All functions are production-safe

### External Functions (All Safe for Production)

| Function | Description | Security Level |
|----------|-------------|----------------|
| `__validate__` | Transaction validation | ✅ Safe - Required |
| `__execute__` | Transaction execution | ✅ Safe - Required |
| `__validate_deploy__` | Deploy validation | ✅ Safe - Required |
| `__validate_declare__` | Declare validation | ✅ Safe - Required |
| `execute_from_outside` | SNIP-9 outside execution | ✅ Safe - Standard |
| `add_or_update_session_key` | Session management | ✅ Safe - Protected by assert_only_self |
| `revoke_session_key` | Session revocation | ✅ Safe - Protected by assert_only_self |
| `get_session_data` | Read session info | ✅ Safe - Read-only |
| `get_contract_info` | Get version | ✅ Safe - Returns constant |
| `get_snip9_version` | Get SNIP-9 version | ✅ Safe - Returns constant |
| `compute_session_message_hash` | Compute hash | ✅ Safe - Uses real tx_info |
| `is_valid_signature` | ERC-1271 validation | ✅ Safe - Standard |
| `get_session_allowed_entrypoints_len` | Get entrypoint count | ✅ Safe - Read-only |
| `get_session_allowed_entrypoint_at` | Get entrypoint by index | ✅ Safe - Read-only |

### Security Properties

✅ **No Debug Functions**: No functions that accept forced parameters
✅ **No Bypasses**: All validations use real transaction info
✅ **Protected Management**: Session management requires owner signature
✅ **Standard Compliance**: Implements SNIP-9 v2, ERC-1271
✅ **Production Ready**: Safe to deploy to mainnet

---

## 🔧 Debug Contract: `debug_account.cairo`

### Version
`v23_debug_snip9`

### Features
- ✅ SNIP-9 v2 (Outside Execution) support
- ✅ Session key management
- ✅ Custom `__validate__` logic
- ✅ ERC-1271 signature validation
- ✅ Upgradeable
- ⚠️ **Additional debug functions for testing**

### Additional Debug Functions (NOT for Production)

| Function | Description | Why Dangerous |
|----------|-------------|---------------|
| `compute_session_message_hash_offchain` | Hash with forced nonce/chain | ⚠️ Bypasses real tx_info |
| `debug_validate_session_signature` | Dry-run signature validation | ⚠️ Accepts forced parameters |
| `_debug_entrypoint_storage` | Read entrypoint storage | ℹ️ Internal implementation details |
| `_debug_get_session_data` | Get session data | ℹ️ Internal implementation details |
| `_debug_session_exists` | Check session existence | ℹ️ Internal implementation details |
| `_debug_get_all_session_data` | Get all session data | ℹ️ Internal implementation details |
| `_debug_verify_entrypoint_storage` | Verify entrypoint storage | ℹ️ Internal implementation details |
| `_debug_check_entrypoint_storage_status` | Check storage status | ℹ️ Internal implementation details |
| `_debug_validate_session_for_calls` | Validate with debug info | ℹ️ Returns internal state |

### Security Risks

⚠️ **Forced Parameters**: Functions accept `forced_nonce` and `forced_chain_id`
- Allows creating signatures with arbitrary nonce/chain_id
- Could be exploited to test signature generation
- Should NEVER be deployed to production

⚠️ **Internal State Exposure**: Debug functions expose internal storage layout
- Could help attackers understand storage structure
- Useful for testing but not for production

---

## 🔒 Security Comparison

### Production Contract (`account.cairo`)

```cairo
// ✅ SAFE: Uses real transaction info
fn compute_session_message_hash(
    self: @ContractState,
    calls: Array<starknet::account::Call>,
    valid_until: u64
) -> felt252 {
    self._session_message_hash(calls.span(), valid_until)
    // Uses: get_tx_info().nonce and get_tx_info().chain_id
}
```

### Debug Contract (`debug_account.cairo`)

```cairo
// ⚠️ DANGEROUS: Accepts forced parameters
fn compute_session_message_hash_offchain(
    self: @ContractState,
    calls: Array<starknet::account::Call>,
    valid_until: u64,
    forced_nonce: felt252,      // ⚠️ Can be anything!
    forced_chain_id: felt252     // ⚠️ Can be anything!
) -> felt252 {
    // Uses forced parameters instead of real tx_info
}
```

---

## 📋 Usage Guidelines

### ✅ Use `account.cairo` When:
- Deploying to mainnet
- Deploying to testnet for production testing
- Need SNIP-9/Paymaster support
- Want production-grade security

### 🔧 Use `debug_account.cairo` When:
- Local development
- Testing signature generation
- Debugging hash mismatches
- Need to inspect internal state
- **NEVER deploy to mainnet**

---

## 🚀 Deployment Recommendations

### For Production (Mainnet/Testnet)

```bash
# Use account.cairo (production)
scarb build
starkli declare target/dev/sessions_smart_contract_Account.contract_class.json

# Deploy
starkli deploy <CLASS_HASH> <PUBLIC_KEY>
```

### For Local Testing Only

```bash
# If you need debug features for local testing
# NEVER deploy these to mainnet!

# The debug contract is available but should only be used
# in controlled development environments
```

---

## 🔐 Security Audit Notes

### Production Contract (`account.cairo`)

**Auditor Checklist:**
- ✅ No functions accept forced parameters
- ✅ All validation uses real tx_info
- ✅ Session management protected by assert_only_self
- ✅ No internal state exposure
- ✅ Standard SNIP-9 v2 implementation
- ✅ ERC-1271 compliant
- ✅ Proper access control

**Verdict:** Safe for production deployment ✅

### Debug Contract (`debug_account.cairo`)

**Auditor Checklist:**
- ⚠️ Contains functions with forced parameters
- ⚠️ Exposes internal implementation details
- ⚠️ Debug functions could aid attackers
- ⚠️ Should not be deployed to production

**Verdict:** Development/Testing ONLY ⚠️

---

## 📊 Function Count Comparison

| Category | Production | Debug |
|----------|-----------|-------|
| Required Account Functions | 4 | 4 |
| Session Management | 3 | 3 |
| SNIP-9 Functions | 1 | 1 |
| Read-Only Helpers | 5 | 5 |
| Debug Functions | 0 | 9 |
| **Total Public Functions** | **13** | **22** |

---

## ✅ Both Contracts Include

- SNIP-9 v2 (Outside Execution) support
- Session key management (add, revoke, query)
- Custom validation logic for sessions
- Owner signature validation
- Upgradeable architecture
- Event emissions
- ERC-1271 signature validation

## ⚠️ Only Debug Contract Includes

- Forced parameter functions
- Internal state inspection
- Debug validation helpers
- Storage verification tools

---

## 🎯 Summary

| Aspect | Production | Debug |
|--------|-----------|-------|
| **SNIP-9 Support** | ✅ v2 | ✅ v2 |
| **Session Keys** | ✅ | ✅ |
| **Security** | ✅ Production-safe | ⚠️ Testing only |
| **Debug Functions** | ❌ None | ⚠️ 9 functions |
| **Mainnet Ready** | ✅ Yes | ❌ No |
| **Testnet Safe** | ✅ Yes | ⚠️ Use with caution |
| **Local Dev** | ✅ Yes | ✅ Yes |

---

## 🔍 How to Verify Contract Safety

Check the contract version:

```bash
# Production contract should return:
starkli call <address> get_contract_info
# Output: v23_snip9_compatible

# Debug contract would return:
# Output: v23_debug_snip9
```

If you see "debug" in the version, **DO NOT USE IN PRODUCTION**.

---

## 📚 Additional Resources

- **Production Deployment**: See `DEPLOY_INSTRUCTIONS.md`
- **SNIP-9 Usage**: See `SNIP9_PAYMASTER_GUIDE.md`
- **Testing**: See `TESTING_GUIDE.md`

---

**Last Updated:** Compatible with SNIP-9 v2  
**Both Contracts:** v23 (Production-safe & Debug versions)

