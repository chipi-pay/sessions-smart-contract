# Account Contract Testing Guide

## 📋 Overview

This guide explains how to test your custom Account contract validation logic using `snforge` (Starknet Foundry) **without deploying to a network**.

---

## 🛠️ Prerequisites

1. **Install Starknet Foundry (snforge)**:
   ```bash
   curl -L https://raw.githubusercontent.com/foundry-rs/starknet-foundry/master/scripts/install.sh | sh
   snfoundryup
   ```

2. **Verify installation**:
   ```bash
   snforge --version
   ```

---

## 📂 Test Files

### 1. `test_account_validation.cairo`
Comprehensive tests for session key management:
- ✅ Constructor and public key initialization
- ✅ Adding session keys
- ✅ Session expiration checks
- ✅ Max calls enforcement
- ✅ Allowed entrypoints validation
- ✅ Session revocation
- ✅ Authorization checks (`assert_only_self`)

### 2. `test_validation_flow.cairo`
Focused tests for `__validate__` function logic:
- ✅ Owner signature validation (2-element `[r, s]`)
- ✅ Session signature validation (4-element `[session_pubkey, r, s, valid_until]`)
- ✅ Expired session rejection
- ✅ Invalid signature length handling

---

## 🚀 How to Run Tests

### Option 1: Run All Tests
```bash
snforge test
```

### Option 2: Run Specific Test Module
```bash
snforge test test_account_validation
snforge test test_validation_flow
```

### Option 3: Run Single Test
```bash
snforge test test_add_session_key
snforge test test_validate_owner_signature_2_elements
```

### Option 4: Verbose Output
```bash
snforge test -v
```

### Option 5: Show Gas Usage
```bash
snforge test --detailed-resources
```

---

## 📊 Expected Test Results

### ✅ Should Pass:
- `test_constructor` - Public key initialization
- `test_add_session_key` - Session key storage
- `test_session_expiration` - Expired sessions fail validation
- `test_session_max_calls` - Max calls limit enforcement
- `test_session_allowed_entrypoints` - Entrypoint filtering
- `test_revoke_session` - Session revocation
- `test_validate_expired_session` - Validation rejects expired sessions
- `test_validate_wrong_signature_length` - Invalid signatures rejected

### ⚠️ Expected Behavior:
- `test_add_session_requires_self_call` - Should **panic** with "Account: unauthorized"
- `test_validate_owner_signature_2_elements` - May return 0 (mock signature won't be valid)
- `test_validate_session_signature_4_elements` - May return 0 (mock signature won't be valid)

---

## 🔍 Understanding Test Results

### Validation Return Values
```cairo
starknet::VALIDATED = 'VALID'  // 0x56414c4944 - Success
0                               // Failure
```

### Common Test Patterns

#### 1. Testing Session Logic (No Signature Needed)
```cairo
#[test]
fn test_session_expiration() {
    // Setup contract state
    // Add session key
    // Set block timestamp after expiration
    // Verify validation fails
}
```

#### 2. Testing Validation Paths (Signature Checks)
```cairo
#[test]
fn test_validate_owner_signature_2_elements() {
    // Set 2-element signature
    // Call __validate__
    // Verify correct path is taken
}
```

#### 3. Testing Authorization
```cairo
#[test]
#[should_panic(expected: ('Account: unauthorized',))]
fn test_unauthorized_access() {
    // Set caller to non-account address
    // Try to call protected function
    // Should panic
}
```

---

## 🐛 Debugging Failed Tests

### If tests don't compile:
1. Ensure your contract imports are correct
2. Check Cairo version compatibility: `scarb --version`
3. Verify `Scarb.toml` dependencies

### If tests panic unexpectedly:
```bash
snforge test --exact test_name -vvv
```
This shows the full panic trace.

### If session tests fail:
- Check `set_block_timestamp()` values
- Verify `valid_until` is in the future
- Ensure `allowed_entrypoints` match call selectors

---

## 📝 Test Coverage Checklist

Before deploying, ensure these scenarios pass:

- [ ] Constructor sets public key correctly
- [ ] Only account can call `add_or_update_session_key`
- [ ] Sessions with expired `valid_until` are rejected
- [ ] Sessions respect `max_calls` limit
- [ ] Sessions only allow specified entrypoints
- [ ] Revoked sessions are invalid
- [ ] 2-element signatures trigger owner validation path
- [ ] 4-element signatures trigger session validation path
- [ ] Invalid signature lengths return 0

---

## 🔄 After Fixing Contract

Once you update `__validate__` to use `self.account.validate_transaction()`:

### 1. Update Tests (if needed)
The session tests should still pass unchanged. Owner validation tests might need adjustment.

### 2. Run Full Test Suite
```bash
snforge test -v
```

### 3. Check Gas Usage
```bash
snforge test --detailed-resources
```

### 4. Deploy with Confidence
```bash
# Declare updated contract
starkli declare target/dev/your_contract.sierra.json

# Note the new class hash
# Update NEXT_PUBLIC_OZ_ACCOUNT_CLASS_HASH in .env.local
```

---

## 🎯 Key Benefits of Testing with snforge

1. **No Network Required** - Test locally, no testnet tokens needed
2. **Fast Iteration** - Instant feedback on logic changes
3. **Gas Estimation** - See costs before deploying
4. **Full Control** - Mock any contract state or caller
5. **Regression Prevention** - Catch bugs before deployment

---

## 📚 Additional Resources

- [Starknet Foundry Docs](https://foundry-rs.github.io/starknet-foundry/)
- [Cairo Testing Guide](https://book.cairo-lang.org/ch10-00-testing-cairo-programs.html)
- [OpenZeppelin Cairo Contracts](https://docs.openzeppelin.com/contracts-cairo/)

---

## ❓ Troubleshooting

### "snforge command not found"
```bash
# Reinstall Starknet Foundry
curl -L https://raw.githubusercontent.com/foundry-rs/starknet-foundry/master/scripts/install.sh | sh
snfoundryup
source ~/.bashrc  # or ~/.zshrc
```

### "Contract not found"
Ensure your contract file structure matches:
```
src/
  lib.cairo          # Exports Account contract
  account.cairo      # Your contract code
tests/
  test_account_validation.cairo
  test_validation_flow.cairo
```

### "Version mismatch"
Check Cairo versions:
```bash
scarb --version
snforge --version
```

Both should use compatible Cairo versions (2.x).

---

**Ready to test!** Run `snforge test` and verify your contract logic before deploying. 🚀

