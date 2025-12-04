# OutsideExecution Calldata Format Reference

## Overview

This document describes the SNIP-9 v2 Outside Execution implementation, including the correct SNIP-12 Revision 1 typed data hashing.

## Function Signature

```cairo
fn execute_from_outside_v2(
    ref self: TContractState,
    outside_execution: OutsideExecution,
    signature: Array<felt252>,  // SNIP-9 v2 standard
) -> Array<Span<felt252>>;
```

**Note**: In SNIP-9 v2, `calls` is INSIDE the `OutsideExecution` struct, not a separate parameter.

## Type Definitions

```cairo
struct OutsideExecution {
    caller: ContractAddress,      // felt252
    nonce: felt252,
    execute_after: u64,           // felt252
    execute_before: u64,          // felt252
    calls: Span<Call>,            // ✅ Calls are INSIDE the struct
}

struct Call {
    to: ContractAddress,          // felt252
    selector: felt252,
    calldata: Span<felt252>       // dynamic array
}
```

## SNIP-12 Revision 1 Type Hashes

**CRITICAL**: These are the CORRECT type hashes for SNIP-12 Revision 1 (with quoted type strings).

```cairo
// SNIP-12 Revision 1 Type Hashes (QUOTED format)
// Type strings: "StarknetDomain"("name":"shortstring",...)
pub const STARKNET_DOMAIN_TYPE_HASH: felt252 = 
    0x1ff2f602e42168014d405a94f75e8a93d640751d71d16311266e140d8b0a210;
pub const CALL_TYPE_HASH: felt252 = 
    0x3635c7f2a7ba93844c0d064e18e487f35ab90f7c39d00f186a781fc3f0c2ca9;
pub const OUTSIDE_EXECUTION_TYPE_HASH: felt252 = 
    0x5a4b49e17039355cd95d1f0981d75901191d1319b1f4b05a9a791d218d7e0c;
```

### Type String Format (Revision 1 uses QUOTES)

```
"StarknetDomain"("name":"shortstring","version":"shortstring","chainId":"shortstring","revision":"shortstring")
"Call"("To":"ContractAddress","Selector":"selector","Calldata":"felt*")
"OutsideExecution"("Caller":"ContractAddress","Nonce":"felt","Execute After":"felt","Execute Before":"felt","Calls":"Call*")"Call"("To":"ContractAddress","Selector":"selector","Calldata":"felt*")
```

## SNIP-12 Hash Computation

### Domain Hash

```cairo
fn _hash_domain(chain_id: felt252) -> felt252 {
    poseidon_hash_span([
        STARKNET_DOMAIN_TYPE_HASH,
        'Account.execute_from_outside',  // name (shortstring)
        2,                                // version (NUMERIC, not '2')
        chain_id,                         // chainId
        1,                                // revision (NUMERIC, not '1')
    ])
}
```

**IMPORTANT**: Version and revision must be NUMERIC (`2`, `1`), not shortstrings (`'2'`, `'1'`):
- `'2'` encodes to `0x32` (ASCII) ❌
- `2` encodes to `0x2` (numeric) ✅

### Call Hash (with PRE-HASHED calldata)

```cairo
fn _hash_call(call: Call) -> felt252 {
    // PRE-HASH the calldata array (required for felt* type)
    let calldata_hash = poseidon_hash_span(call.calldata);
    
    poseidon_hash_span([
        CALL_TYPE_HASH,
        call.to.into(),
        call.selector,
        calldata_hash,  // Single hash, NOT element-by-element
    ])
}
```

### OutsideExecution Struct Hash (with PRE-HASHED calls array)

```cairo
fn _hash_outside_execution(outside_execution: OutsideExecution, calls: Span<Call>) -> felt252 {
    // First, compute hash for each call
    let mut call_hashes = array![];
    for call in calls {
        call_hashes.append(_hash_call(call));
    }
    
    // PRE-HASH the calls array (required for Call* type)
    let calls_array_hash = poseidon_hash_span(call_hashes.span());
    
    poseidon_hash_span([
        OUTSIDE_EXECUTION_TYPE_HASH,
        outside_execution.caller.into(),
        outside_execution.nonce,
        outside_execution.execute_after.into(),
        outside_execution.execute_before.into(),
        calls_array_hash,  // Single hash, NOT element-by-element
    ])
}
```

### Final Message Hash

```cairo
fn _get_outside_execution_hash(outside_execution: OutsideExecution, calls: Span<Call>) -> felt252 {
    let domain_hash = _hash_domain(chain_id);
    let struct_hash = _hash_outside_execution(outside_execution, calls);
    
    poseidon_hash_span([
        'StarkNet Message',     // SNIP-12 prefix
        domain_hash,
        get_contract_address().into(),
        struct_hash,
    ])
}
```

## Array Hashing Rule

**The `*` suffix in SNIP-12 types means: PRE-HASH the array, then use single hash.**

| Type | Meaning |
|------|---------|
| `felt*` | Hash the array first: `poseidon(calldata)` |
| `Call*` | Hash the array of call hashes: `poseidon([hash1, hash2, ...])` |

### ❌ WRONG (element-by-element)

```cairo
// Don't do this!
hash_data.append(CALL_TYPE_HASH);
hash_data.append(call.to);
hash_data.append(call.selector);
hash_data.append(calldata[0]);  // ❌
hash_data.append(calldata[1]);  // ❌
hash_data.append(calldata[2]);  // ❌
poseidon_hash_span(hash_data.span())
```

### ✅ CORRECT (pre-hash array)

```cairo
let calldata_hash = poseidon_hash_span(call.calldata);  // ✅ Pre-hash
hash_data.append(CALL_TYPE_HASH);
hash_data.append(call.to);
hash_data.append(call.selector);
hash_data.append(calldata_hash);  // ✅ Single hash
poseidon_hash_span(hash_data.span())
```

## Cairo Serde Serialization Rules

1. **Structs**: Serialized field-by-field inline (NO length prefix)
2. **Arrays**: Prefixed with length, then elements
3. **Basic types** (felt252, u64, ContractAddress): Single felt252 value

## Complete Calldata Structure

```
[
  // ===== OutsideExecution struct (5 fields, inline) =====
  caller,           // 0: ContractAddress (felt252)
  nonce,            // 1: felt252
  execute_after,    // 2: u64 (as felt252)
  execute_before,   // 3: u64 (as felt252)
  
  // ===== calls: Span<Call> (inside OutsideExecution) =====
  calls_length,     // 4: number of calls (e.g., '1')
  
  // ----- Call #0 -----
  call_0.to,              // 5: ContractAddress
  call_0.selector,        // 6: felt252
  call_0.calldata_length, // 7: length of calldata array
  call_0.calldata[0],     // 8: first calldata element
  call_0.calldata[1],     // 9: second calldata element
  // ... more calldata elements ...
  
  // ===== signature: Array<felt252> =====
  signature_length,       // N: number of signature elements
  signature[0],           // N+1: first signature element (r or session_pubkey)
  signature[1],           // N+2: second signature element (s or r)
  // ... more signature elements ...
]
```

## Signature Formats

| Signer | Length | Elements |
|--------|--------|----------|
| Owner | 2 | `[r, s]` |
| Session | 4 | `[session_pubkey, r, s, valid_until]` |

## TypeScript Example (starknet.js)

```typescript
import { typedData, Account } from "starknet";

// Define typed data for SNIP-9 v2
const outsideExecutionTypedData = {
  types: {
    StarknetDomain: [
      { name: 'name', type: 'shortstring' },
      { name: 'version', type: 'shortstring' },
      { name: 'chainId', type: 'shortstring' },
      { name: 'revision', type: 'shortstring' },
    ],
    OutsideExecution: [
      { name: 'Caller', type: 'ContractAddress' },
      { name: 'Nonce', type: 'felt' },
      { name: 'Execute After', type: 'felt' },
      { name: 'Execute Before', type: 'felt' },
      { name: 'Calls', type: 'Call*' },
    ],
    Call: [
      { name: 'To', type: 'ContractAddress' },
      { name: 'Selector', type: 'selector' },
      { name: 'Calldata', type: 'felt*' },
    ],
  },
  primaryType: 'OutsideExecution',
  domain: {
    name: 'Account.execute_from_outside',
    version: '2',
    chainId: 'SN_MAIN',  // or 'SN_SEPOLIA'
    revision: '1',
  },
  message: {
    Caller: '0x0',  // ANY_CALLER
    Nonce: '0x' + Date.now().toString(16),
    'Execute After': '0x0',
    'Execute Before': '0x' + (Math.floor(Date.now() / 1000) + 3600).toString(16),
    Calls: [{
      To: WAVE_CONTRACT,
      Selector: getSelectorFromName('wave'),
      Calldata: ['0x6f', '0x69', '0x75'],
    }],
  },
};

// Get message hash (starknet.js computes SNIP-12 hash correctly)
const messageHash = typedData.getMessageHash(outsideExecutionTypedData, accountAddress);

// Sign with owner private key
const signature = ec.starkCurve.sign(messageHash, privateKey);
```

## Exposed Contract Functions

The account contract exposes these SNIP-9 functions:

```cairo
// Execute outside transaction
fn execute_from_outside_v2(
    ref self: ContractState,
    outside_execution: OutsideExecution,
    signature: Array<felt252>,
) -> Array<Span<felt252>>;

// Check if nonce is valid (not yet used)
fn is_valid_outside_execution_nonce(
    self: @ContractState,
    nonce: felt252
) -> bool;

// Compute message hash (for verification)
fn get_outside_execution_message_hash_rev_1(
    self: @ContractState,
    outside_execution: OutsideExecution,
) -> felt252;

// Alias for compatibility
fn get_outside_execution_message_hash(
    self: @ContractState,
    outside_execution: OutsideExecution,
) -> felt252;
```

## Key Points Summary

1. **SNIP-12 Revision 1** - Use quoted type strings and corresponding type hashes
2. **Version/Revision encoding** - Use numeric (`2`, `1`), not shortstrings (`'2'`, `'1'`)
3. **Array hashing** - PRE-HASH arrays with `*` suffix, then use single hash value
4. **Calls inside OutsideExecution** - In SNIP-9 v2, calls are part of the struct
5. **Poseidon for everything** - Revision 1 uses Poseidon hash throughout
6. **Signature** - Owner uses 2 elements `[r, s]`, session uses 4 elements

## Common Mistakes

❌ **Using Revision 0 type hashes**
```cairo
// WRONG - these are Revision 0 (unquoted format)
STARKNET_DOMAIN_TYPE_HASH = 0x2885275e800b54f851ca9215daf6c98b5b0c607b642052fc1249a2ce43c6a02;
```

✅ **Use Revision 1 type hashes**
```cairo
// CORRECT - Revision 1 (quoted format)
STARKNET_DOMAIN_TYPE_HASH = 0x1ff2f602e42168014d405a94f75e8a93d640751d71d16311266e140d8b0a210;
```

❌ **Using shortstring for version**
```cairo
hash_data.append('2');  // WRONG - gives 0x32
```

✅ **Use numeric value**
```cairo
hash_data.append(2);    // CORRECT - gives 0x2
```

❌ **Element-by-element array hashing**
```cairo
for element in calldata {
    hash_data.append(element);  // WRONG
}
```

✅ **Pre-hash the array**
```cairo
let calldata_hash = poseidon_hash_span(calldata);
hash_data.append(calldata_hash);  // CORRECT
```
