# Deployment Summary - October 10, 2025

## Contract Deployment Details

### Latest Class Declaration (v4 - CORRECTED with __validate_deploy__)
- **Class Hash**: `0x06ea132398934f65c717ccd7e9928e589cd94c1e64b7c2339c1a3ecfabc58ad5`
- **Transaction**: `0x03f94ca53e4705cac4db0b1cdda8a1af8120dd67120545b5a8582a9eb594772a`
- **Status**: ✅ Accepted on L2
- **Starkscan**: https://starkscan.co/class/0x06ea132398934f65c717ccd7e9928e589cd94c1e64b7c2339c1a3ecfabc58ad5

### Previous Attempt (v3 - INCOMPLETE)
- **Class Hash**: `0x05ff12bf03552f013cd8322e79bd4c72ca99b3f963aedb20e6f85b6443413bc3`
- **Transaction**: `0x077158abf7915ec28f0b6a648e1eaf6bd35ac9048e33d0e482f08ed46b38e02a`
- **Status**: ⚠️ SRC6CamelOnlyImpl/DeclarerImpl don't expose __validate_deploy__ properly
- **Starkscan**: https://starkscan.co/class/0x05ff12bf03552f013cd8322e79bd4c72ca99b3f963aedb20e6f85b6443413bc3

### Previous Class Declaration (v2)
- **Class Hash**: `0x023dc5d0d4f581c98d2e30e8a7317432e180e9f8b090e775339e3462c3de2949`
- **Transaction**: `0x044261226f6908fb02f8e3838a8117c8b3ab76ef376be87b334b479246cca46c`
- **Status**: ⚠️ Missing `__validate_deploy__` (cannot deploy new instances)
- **Starkscan**: https://starkscan.co/class/0x023dc5d0d4f581c98d2e30e8a7317432e180e9f8b090e775339e3462c3de2949

### Reference Implementation Deployment
- **Contract Address**: `0x01b0b06255f6960219dc358114779fda563c3b817d2df3fbd214e67c3572fd7f`
- **Transaction**: `0x06a77999d05b8440dd1ca39eeabc77750074cbd624786c69e09b4e94dbe8174f`
- **Owner Public Key**: `0x201930d4f9610621299dd6f00d7e689f62803dcbfe5b89d2ff4c657e2372d74`
- **Starkscan**: https://starkscan.co/contract/0x01b0b06255f6960219dc358114779fda563c3b817d2df3fbd214e67c3572fd7f

## Key Changes in Version 4 (October 10, 2025) - CORRECTED

### 🔧 Fixed: Missing __validate_deploy__ and __validate_declare__ Entrypoints

**Problem**: Previous versions manually implemented SRC6 interface but didn't expose `__validate_deploy__` and `__validate_declare__`, preventing DEPLOY_ACCOUNT and DECLARE transactions.

**Failed Attempt (v3)**: Tried using `SRC6CamelOnlyImpl` and `DeclarerImpl` from AccountComponent, but these don't properly expose the required methods.

**Working Solution (v4)**: Manually implemented both methods directly in the `SRC6Impl` trait:

```cairo
#[external(v0)]
fn __validate_deploy__(
    self: @ContractState,
    class_hash: felt252,
    contract_address_salt: felt252,
    public_key: felt252
) -> felt252 {
    // Validates deployment signature against the public_key constructor arg
    let tx_info = get_tx_info().unbox();
    let signature = tx_info.signature;
    
    if signature.len() != 2 {
        return 0;
    }
    
    let tx_hash = tx_info.transaction_hash;
    let is_valid = check_ecdsa_signature(
        tx_hash,
        public_key,
        *signature.at(0),
        *signature.at(1)
    );
    
    if is_valid {
        starknet::VALIDATED
    } else {
        0
    }
}

#[external(v0)]
fn __validate_declare__(self: @ContractState, class_hash: felt252) -> felt252 {
    // Validates declaration signature against account's public key
    let tx_info = get_tx_info().unbox();
    let signature = tx_info.signature;
    
    if signature.len() != 2 {
        return 0;
    }
    
    let public_key = self.account.get_public_key();
    let tx_hash = tx_info.transaction_hash;
    let is_valid = check_ecdsa_signature(
        tx_hash,
        public_key,
        *signature.at(0),
        *signature.at(1)
    );
    
    if is_valid {
        starknet::VALIDATED
    } else {
        0
    }
}
```

**Now properly supports:**
- ✅ `__validate__` - Custom validation with session key support
- ✅ `__execute__` - Custom execution logic  
- ✅ `__validate_deploy__` - Deploy new account instances (VERIFIED in ABI)
- ✅ `__validate_declare__` - Declare new contract classes (VERIFIED in ABI)
- ✅ All 13 tests passing

## Key Changes in Version 2 (October 8, 2025)

### 🔧 Fixed: Chicken-and-Egg Problem in Session Signatures

**Problem**: Previous version required `transaction_hash` in the session message hash, but clients can't know the transaction hash before sending the transaction.

**Solution**: Session message hash now uses only predictable, off-chain-computable values:

```cairo
hash_data = [
    account_address,      // Known (contract address)
    chain_id,            // Known (network constant)
    nonce,               // Known (fetch from account)
    valid_until,         // Known (session parameter)
    ...call_data         // Known (user's intended calls)
]
```

### Security Properties

✅ **Replay Protection**: Nonce ensures each signature is single-use
✅ **Account Binding**: Address prevents cross-account attacks  
✅ **Chain Binding**: Chain ID prevents cross-network replay
✅ **Complete Integrity**: All call parameters included in hash
✅ **Pre-signing Enabled**: Clients can sign before transaction submission

## Client Integration

Clients can now:
1. Fetch current nonce from account contract
2. Compute message hash with all known values
3. Sign with session private key
4. Submit transaction with signature

No more circular dependency!

## Network
- **Network**: Starknet Mainnet
- **Compiler**: Cairo 2.11.4 (via Scarb)
- **Starknet Foundry**: v0.50.0

## Files Modified
- `src/account.cairo` - Updated `_session_message_hash` function
- `README.md` - Updated deployment info and documentation
- `snfoundry.toml` - Added deployment configuration






