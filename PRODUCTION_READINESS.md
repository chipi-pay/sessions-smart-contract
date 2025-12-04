# SNIP-9 v2 Production Readiness Checklist

**Status**: ⚠️ NOT PRODUCTION READY - Critical items must be completed

This document tracks all requirements for production deployment of the custom SNIP-9 v2 implementation.

---

## 🔴 CRITICAL (Must Complete Before ANY Deployment)

### 1. Type Hash Computation ✅ COMPLETE

**Status**: ✅ DONE  
**Priority**: CRITICAL  
**Effort**: 2-4 hours (COMPLETED)

**Issue**: ~~Current type hashes were placeholders~~ **FIXED WITH PRODUCTION VALUES**

**Completed Actions**:
- [x] Run `python3 scripts/compute_snip12_type_hashes.py` to get correct values
- [x] ~~Install dependencies~~ NO DEPENDENCIES NEEDED (stdlib only)
- [x] Computed production values using starknet_keccak
- [x] Updated constants in `src/outside_execution.cairo` lines 42, 46, 50
- [x] Rebuilt: `scarb build` ✅ SUCCESS
- [x] Verified compilation succeeds

**Production Values Now In Contract**:
```cairo
STARKNET_DOMAIN_TYPE_HASH = 0x06e3b1a0f44677d1e2792819f5bd0f619216c5c15b53ab9e32222b38557a83b6
OUTSIDE_EXECUTION_TYPE_HASH = 0x00740e68dea8ee199471f33c2917185e212b88eb92043927de470de44b91cdce
CALL_TYPE_HASH = 0x0778f3b261b5528e28c6e4766907a87d8b419322ad49cd4b96903f01d0908532
```

**Files to Update**:
- `src/outside_execution.cairo` (lines 38-47)

**Verification**:
```bash
cd scripts
python3 compute_snip12_type_hashes.py
# Copy output to src/outside_execution.cairo
cd ..
scarb build  # Must succeed
```

**Reference**:
- SNIP-12 Spec: https://github.com/starknet-io/SNIPs/blob/main/SNIPS/snip-12.md
- Argent Implementation: https://github.com/argentlabs/argent-contracts-starknet

---

### 2. Integration into account.cairo ⚠️ BLOCKING

**Status**: ❌ NOT DONE  
**Priority**: CRITICAL  
**Effort**: 4-6 hours  

**Issue**: The implementation is in a separate example file. It needs to be integrated into your actual `src/account.cairo`.

**Required Actions**:
- [ ] Review integration example: `src/account_with_outside_execution.cairo`
- [ ] Add component import to `src/account.cairo`
- [ ] Add component declaration
- [ ] Update Storage struct
- [ ] Update Event enum
- [ ] Implement `ISignatureValidator` trait
- [ ] Implement `ICallExecutor` trait
- [ ] Expose `execute_from_outside_v2` entrypoint
- [ ] Update constructor (if needed)
- [ ] Build and verify: `scarb build`

**Integration Checklist**:
```cairo
// 1. Add import
use sessions_smart_contract::outside_execution::{
    OutsideExecutionComponent, IOutsideExecution
};

// 2. Add component
component!(path: OutsideExecutionComponent, storage: outside_execution, event: OutsideExecutionEvent);

// 3. Update Storage
#[storage]
struct Storage {
    #[substorage(v0)]
    outside_execution: OutsideExecutionComponent::Storage,
    // ... existing fields
}

// 4. Update Events
#[event]
enum Event {
    #[flat]
    OutsideExecutionEvent: OutsideExecutionComponent::Event,
    // ... existing events
}

// 5. Implement traits
impl SignatureValidatorImpl of OutsideExecutionComponent::ISignatureValidator<ContractState> {
    fn validate_signature(ref self: ContractState, hash: felt252, signature: Array<felt252>) -> bool {
        self.is_valid_signature(hash, signature) == starknet::VALIDATED
    }
}

impl CallExecutorImpl of OutsideExecutionComponent::ICallExecutor<ContractState> {
    fn execute_calls(ref self: ContractState, calls: Array<Call>) -> Array<Span<felt252>> {
        self._execute_calls(calls)
    }
}

// 6. Expose entrypoint
#[abi(embed_v0)]
impl OutsideExecutionImpl = OutsideExecutionComponent::OutsideExecutionImpl<ContractState>;
```

**Verification**:
```bash
scarb build  # Must succeed with no errors
```

---

### 3. Core Functionality Testing ⚠️ BLOCKING

**Status**: ❌ NOT DONE  
**Priority**: CRITICAL  
**Effort**: 1-2 days  

**Issue**: Test suite exists but needs proper setup and execution.

**Required Actions**:
- [ ] Set up test environment for account deployment
- [ ] Implement test helpers for signature generation
- [ ] Run all 15 tests in `tests/test_outside_execution.cairo`
- [ ] Add tests for session + outside execution combination
- [ ] All tests must pass: `snforge test`

**Test Coverage Required**:
- [ ] Owner signature (2-element) execution
- [ ] Session signature (4-element) execution  
- [ ] Nonce replay prevention
- [ ] Timestamp validation (execute_after, execute_before)
- [ ] Caller restriction (specific address)
- [ ] Unrestricted execution (ANY_CALLER = 0x0)
- [ ] Multiple calls in single execution
- [ ] Invalid signature rejection
- [ ] Session entrypoint restrictions
- [ ] Session call limit enforcement
- [ ] Message hash computation accuracy

**Verification**:
```bash
snforge test  # All tests must pass
```

---

### 4. Frontend Hash Computation ⚠️ BLOCKING

**Status**: ❌ NOT DONE  
**Priority**: CRITICAL  
**Effort**: 1-2 days  

**Issue**: Frontend must compute identical SNIP-12 hashes as the contract.

**Required Actions**:
- [ ] Implement SNIP-12 hash computation in TypeScript/JavaScript
- [ ] Use correct type hashes from step 1
- [ ] Implement domain hash computation
- [ ] Implement call hash computation
- [ ] Implement struct hash computation
- [ ] Implement final message hash
- [ ] Verify hashes match contract exactly

**TypeScript Implementation Needed**:
```typescript
// 1. Type hashes (from Python script output)
const STARKNET_DOMAIN_TYPE_HASH = '0x...';
const OUTSIDE_EXECUTION_TYPE_HASH = '0x...';
const CALL_TYPE_HASH = '0x...';

// 2. Hash functions
function hashDomain(chainId: string): string;
function hashCall(call: Call): string;
function hashOutsideExecution(oe: OutsideExecution, calls: Call[]): string;
function computeSnip12Hash(account: string, chainId: string, oe: OutsideExecution, calls: Call[]): string;
```

**Verification**:
- [ ] Deploy test contract to Sepolia
- [ ] Compute hash in frontend
- [ ] Call `get_outside_execution_message_hash_rev_1()` from contract
- [ ] Hashes must match exactly
- [ ] Test with multiple different call combinations

---

### 5. Testnet Integration Testing ⚠️ BLOCKING

**Status**: ❌ NOT DONE  
**Priority**: CRITICAL  
**Effort**: 2-3 days  

**Issue**: Must verify end-to-end flow on testnet before mainnet.

**Required Actions**:
- [ ] Deploy account to Sepolia testnet
- [ ] Add session key via owner
- [ ] Test owner signature outside execution (2-element)
- [ ] Test session signature outside execution (4-element)
- [ ] Test nonce management
- [ ] Test with restricted caller
- [ ] Test with unrestricted caller (ANY_CALLER)
- [ ] Test multiple calls
- [ ] Test session restrictions (entrypoints, max_calls)
- [ ] Monitor events and transaction status
- [ ] Verify gas costs are reasonable

**Testnet Verification Steps**:
```bash
# 1. Declare contract
sncast declare --contract-name Account --network sepolia

# 2. Deploy instance
sncast deploy --class-hash <CLASS_HASH> --constructor-calldata <OWNER_PUBKEY> --network sepolia

# 3. Add session key
sncast invoke --contract-address <ACCOUNT> --function add_or_update_session_key --calldata <SESSION_DATA> --network sepolia

# 4. Test outside execution (from different account)
sncast invoke --contract-address <ACCOUNT> --function execute_from_outside_v2 --calldata <OUTSIDE_EXECUTION_DATA> --network sepolia
```

---

## 🟡 IMPORTANT (Highly Recommended)

### 6. Security Audit

**Status**: ❌ NOT DONE  
**Priority**: HIGH  
**Effort**: 2-4 weeks (external)  

**Required Actions**:
- [ ] Internal code review by senior developers
- [ ] Engage professional audit firm (OpenZeppelin, Trail of Bits, etc.)
- [ ] Address all findings
- [ ] Re-audit if major changes made
- [ ] Document audit results

**Recommended Auditors**:
- OpenZeppelin
- Trail of Bits
- Nethermind
- Consensys Diligence

---

### 7. Nonce Management Strategy

**Status**: ❌ NOT DONE  
**Priority**: HIGH  
**Effort**: 4-8 hours  

**Required Actions**:
- [ ] Define nonce generation scheme (timestamp? counter? hybrid?)
- [ ] Implement frontend nonce tracking
- [ ] Handle nonce conflicts gracefully
- [ ] Add nonce validation in frontend
- [ ] Document nonce strategy for users

**Recommended Approach**:
```typescript
// Hybrid: timestamp + counter
const baseNonce = Math.floor(Date.now() / 1000);
const nonce = baseNonce * 1000 + counter;

// Track used nonces off-chain
const usedNonces = new Set<number>();
```

---

### 8. Error Handling & User Experience

**Status**: ❌ NOT DONE  
**Priority**: MEDIUM  
**Effort**: 1-2 days  

**Required Actions**:
- [ ] Implement user-friendly error messages
- [ ] Handle common failure scenarios gracefully
- [ ] Add retry logic for transient failures
- [ ] Provide clear feedback on transaction status
- [ ] Add loading states for async operations

**Common Errors to Handle**:
- Nonce already used
- Invalid timestamp (too early/late)
- Invalid caller
- Invalid signature
- Session expired
- Max calls exceeded

---

### 9. Gas Optimization

**Status**: ❌ NOT DONE  
**Priority**: MEDIUM  
**Effort**: 1-2 days  

**Required Actions**:
- [ ] Profile gas usage of outside execution
- [ ] Compare with normal transaction flow
- [ ] Optimize if needed (storage access patterns, etc.)
- [ ] Document gas costs for users
- [ ] Test with various call combinations

**Target Metrics**:
- Single call outside execution: < 500k gas
- Multi-call outside execution: < 1M gas
- Acceptable overhead vs normal execution: < 20%

---

### 10. Documentation Updates

**Status**: ❌ NOT DONE  
**Priority**: MEDIUM  
**Effort**: 4-6 hours  

**Required Actions**:
- [ ] Update README.md with SNIP-9 v2 support
- [ ] Add usage examples for execute_from_outside_v2
- [ ] Document nonce management
- [ ] Document type hashes
- [ ] Add frontend integration guide
- [ ] Document upgrade procedure
- [ ] Add troubleshooting section

---

## 🟢 NICE TO HAVE (Optional)

### 11. Monitoring & Analytics

**Status**: ❌ NOT DONE  
**Priority**: LOW  
**Effort**: 1-2 days  

**Required Actions**:
- [ ] Set up event monitoring
- [ ] Track outside execution usage
- [ ] Monitor nonce patterns
- [ ] Alert on anomalies
- [ ] Dashboard for metrics

---

### 12. Upgrade Testing

**Status**: ❌ NOT DONE  
**Priority**: LOW  
**Effort**: 4-8 hours  

**Required Actions**:
- [ ] Test upgrade mechanism on testnet
- [ ] Verify storage preservation after upgrade
- [ ] Test that existing sessions still work
- [ ] Document upgrade process
- [ ] Create upgrade scripts

---

## Production Deployment Checklist

Before declaring new class hash on mainnet:

- [ ] All 🔴 CRITICAL items complete
- [ ] All 🟡 IMPORTANT items complete (or documented why skipped)
- [ ] All tests passing
- [ ] Security audit complete (if applicable)
- [ ] Testnet deployment successful
- [ ] Frontend integration tested
- [ ] Documentation complete
- [ ] Upgrade plan documented
- [ ] Rollback plan documented
- [ ] Monitoring in place

## Estimated Timeline

Based on the above checklist:

| Phase | Duration | Items |
|-------|----------|-------|
| Critical Fixes | 4-7 days | Items 1-5 |
| Important Items | 3-5 days | Items 6-10 |
| Testing & Polish | 2-3 days | Final verification |
| **Total** | **9-15 days** | Full production ready |

Add 2-4 weeks if professional security audit is required.

---

## Quick Start (Minimum Viable)

If you need to get started ASAP, complete these in order:

1. **Day 1**: Fix type hashes (Item 1) + Integration (Item 2)
2. **Day 2-3**: Core testing (Item 3)
3. **Day 4-5**: Frontend integration (Item 4)
4. **Day 6-7**: Testnet testing (Item 5)
5. **Day 8+**: Security review and remaining items

---

## Current Blockers

1. ⚠️ **Type hashes are placeholders** - Will not work with standard implementations
2. ⚠️ **Not integrated into account.cairo** - Still in example file
3. ⚠️ **No test execution** - Tests exist but haven't been run
4. ⚠️ **No frontend implementation** - Hash computation not implemented
5. ⚠️ **No testnet deployment** - End-to-end flow not verified

---

## Next Immediate Steps

**Do this first** (2-3 hours):
1. Run `python3 scripts/compute_snip12_type_hashes.py`
2. Update type hashes in `src/outside_execution.cairo`
3. Verify build: `scarb build`

**Then do this** (4-6 hours):
4. Integrate component into `src/account.cairo`
5. Verify build: `scarb build`
6. Run basic smoke tests

**Then test** (1-2 days):
7. Set up test environment
8. Run full test suite
9. Deploy to testnet
10. Test end-to-end flow

---

## Support & Resources

- **SNIP-9 Spec**: https://github.com/starknet-io/SNIPs/blob/main/SNIPS/snip-9.md
- **SNIP-12 Spec**: https://github.com/starknet-io/SNIPs/blob/main/SNIPS/snip-12.md
- **Argent Implementation**: https://github.com/argentlabs/argent-contracts-starknet
- **Starknet.js Guide**: https://starknetjs.com/docs/guides/outsideExecution

---

**Last Updated**: Type hashes updated with production values
**Status**: ⚠️ NOT PRODUCTION READY (1/5 critical items done)
**Completion**: 1/12 critical and important items complete (✅ Type Hashes DONE)

