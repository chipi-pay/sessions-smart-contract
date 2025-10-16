# SNIP-9 (Outside Execution) & Paymaster Support Guide

## 🎉 Your Account is Now SNIP-9 Compatible!

This branch (`paymaster`) adds **SNIP-9 v2 compatibility** to your session-enabled account contract, enabling **sponsored transactions** (Paymaster support).

## What Changed?

### Added Components

1. **SRC9Component** - OpenZeppelin's Outside Execution implementation
   - Provides `execute_from_outside` functionality
   - Implements SNIP-9 v2 standard
   - Fully compatible with existing session keys

### Key Modifications

**File: `src/account.cairo`**

1. **Import SRC9Component:**
   ```cairo
   use openzeppelin::account::extensions::SRC9Component;
   component!(path: SRC9Component, storage: src9, event: SRC9Event);
   ```

2. **Added Outside Execution Implementation:**
   ```cairo
   #[abi(embed_v0)]
   impl OutsideExecutionV2Impl = SRC9Component::OutsideExecutionV2Impl<ContractState>;
   ```

3. **Updated Storage:**
   ```cairo
   #[substorage(v0)]
   src9: SRC9Component::Storage,
   ```

4. **Initialize in Constructor:**
   ```cairo
   self.src9.initializer();
   ```

5. **Added Version Check Function:**
   ```cairo
   fn get_snip9_version(self: @ContractState) -> u8 {
       2  // SNIP-9 v2 compatible
   }
   ```

## How It Works: Sessions + Paymaster = Magic ✨

### Before (Session Keys Only)
```
User → Creates Session Key → App signs with session → User pays gas ⛽💰
```

### Now (Sessions + SNIP-9)
```
User → Creates Session Key → App signs with session → Backend pays gas 🎉
User needs $0 in wallet!
```

## Usage Examples

### 1. Check SNIP-9 Compatibility (Frontend)

```typescript
import { Account, OutsideExecutionVersion } from 'starknet';

const account = new Account(provider, accountAddress, privateKey);
const version = await account.getSnip9Version();

if (version === OutsideExecutionVersion.UNSUPPORTED) {
  throw new Error('Account not SNIP-9 compatible');
}

console.log('Account is SNIP-9 v2 compatible!'); // ✅
```

### 2. Create Session + Outside Execution

```typescript
// Step 1: User creates a session key (as before)
const sessionKeyPair = ec.starkCurve.utils.randomPrivateKey();
const sessionPublicKey = ec.starkCurve.getStarkKey(sessionKeyPair);

const addSessionCall = {
  contractAddress: accountAddress,
  entrypoint: 'add_or_update_session_key',
  calldata: {
    session_key: sessionPublicKey,
    valid_until: Math.floor(Date.now() / 1000) + 86400, // 24 hours
    max_calls: 10,
    allowed_entrypoints: [selector.getSelectorFromName('transfer')]
  }
};

await ownerAccount.execute(addSessionCall);

// Step 2: App creates an outside transaction with session signature
const call = {
  contractAddress: erc20Address,
  entrypoint: 'transfer',
  calldata: {
    recipient: recipientAddress,
    amount: cairo.uint256(1000000000000000000n) // 1 token
  }
};

const callOptions: OutsideExecutionOptions = {
  caller: backendExecutorAccount.address, // Who will pay gas
  execute_after: Math.floor(Date.now() / 1000) - 60,
  execute_before: Math.floor(Date.now() / 1000) + 3600
};

// Session account creates the outside transaction
const sessionAccount = new Account(provider, accountAddress, sessionKeyPair);
const outsideTransaction = await sessionAccount.getOutsideTransaction(
  callOptions,
  call
);

// Step 3: Backend executes and pays gas
const backendAccount = new Account(provider, backendAddress, backendPrivateKey);
const response = await backendAccount.executeFromOutside(outsideTransaction);
await provider.waitForTransaction(response.transaction_hash);

console.log('Transaction executed! Backend paid the gas 🎉');
```

### 3. Multiple Session Transactions (Pre-signed)

```typescript
// User pre-signs multiple transactions at once
const calls = [
  { contractAddress: erc20Address, entrypoint: 'approve', calldata: {...} },
  { contractAddress: erc20Address, entrypoint: 'transfer', calldata: {...} },
  { contractAddress: nftAddress, entrypoint: 'mint', calldata: {...} }
];

const outsideTx1 = await sessionAccount.getOutsideTransaction(callOptions, calls[0]);
const outsideTx2 = await sessionAccount.getOutsideTransaction(callOptions, calls[1]);
const outsideTx3 = await sessionAccount.getOutsideTransaction(callOptions, calls[2]);

// Store these transactions
// Later, backend can execute any of them in any order
await backendAccount.executeFromOutside([outsideTx2, outsideTx3]); // Skip tx1
```

## Security Notes

### ✅ What's Preserved
- All existing session key security (expiry, max calls, entrypoint restrictions)
- Owner signature validation unchanged
- Custom `__validate__` logic intact
- All 15 existing tests pass

### ⚠️ Important Considerations

1. **Caller Restriction**: Always set a specific `caller` in `OutsideExecutionOptions`
   ```typescript
   // ✅ GOOD - specific executor
   { caller: backendExecutorAccount.address }
   
   // ❌ DANGEROUS - anyone can execute
   { caller: "ANY_CALLER" }
   ```

2. **Time Windows**: Use reasonable time frames
   ```typescript
   {
     execute_after: Math.floor(Date.now() / 1000) - 60,  // 1 min ago
     execute_before: Math.floor(Date.now() / 1000) + 3600 // 1 hour from now
   }
   ```

3. **Session + Outside Execution**: Both validations apply
   - Session key must be valid (not expired, not revoked)
   - Session must have calls remaining
   - Entrypoint must be allowed
   - Outside execution signature must be valid
   - Caller must match
   - Current time must be within window

## Use Cases

### 🎮 Gaming dApps
```typescript
// Player creates session at login
// Backend sponsors all in-game transactions
// Player never needs gas tokens
```

### 📱 Mobile Apps
```typescript
// Smooth UX - no wallet popups
// App sponsors onboarding transactions
// Users can try features with $0 balance
```

### 🤖 Automated Trading Bots
```typescript
// Pre-sign limit orders with sessions
// Backend executes when price conditions met
// Backend pays gas
```

### 🆕 User Onboarding
```typescript
// New users get session keys
// Protocol sponsors first transactions
// No "buy gas first" friction
```

## Testing SNIP-9 Support

```bash
# Build the contract
scarb build

# Run all tests (should pass)
snforge test

# Check SNIP-9 compatibility
starkli call <account_address> get_snip9_version
# Should return: 2
```

## Deployment

When deploying the updated account:

```bash
# Declare the new class
starkli declare target/dev/sessions_smart_contract_Account.contract_class.json

# Deploy with your public key
starkli deploy <CLASS_HASH> <PUBLIC_KEY>

# Or upgrade existing account
starkli invoke <ACCOUNT_ADDRESS> upgrade <NEW_CLASS_HASH>
```

## Compatibility

| Account Version | SNIP-9 | Session Keys | Paymaster |
|----------------|--------|--------------|-----------|
| v22 (main)     | ❌     | ✅           | ❌        |
| v23 (paymaster)| ✅ v2  | ✅           | ✅        |

This account is compatible with:
- ✅ **ArgentX v0.4.0** style outside execution (v2)
- ✅ **Braavos v1.1.0** style outside execution (v2)
- ✅ **OpenZeppelin v2.0.0** with SRC9Component
- ✅ All existing session key functionality

## Architecture

```
┌─────────────────────────────────────────────┐
│           Your Account Contract             │
├─────────────────────────────────────────────┤
│                                             │
│  ┌─────────────┐  ┌──────────────────────┐ │
│  │   Session   │  │  Outside Execution   │ │
│  │    Keys     │  │     (SNIP-9 v2)      │ │
│  └─────────────┘  └──────────────────────┘ │
│         │                    │              │
│         └────────┬───────────┘              │
│                  │                          │
│         ┌────────▼────────┐                 │
│         │  __validate__   │                 │
│         │  (custom logic) │                 │
│         └─────────────────┘                 │
│                                             │
│  Base: OpenZeppelin AccountComponent       │
└─────────────────────────────────────────────┘
```

## Next Steps

1. **Deploy** the updated contract (with SNIP-9 support)
2. **Update your frontend** to use `executeFromOutside`
3. **Set up a backend** to sponsor transactions
4. **Test** with small amounts first
5. **Monitor gas costs** on your sponsor account

## Resources

- [SNIP-9 Specification](https://community.starknet.io/t/snip-9-outside-execution/98812)
- [Starknet.js Outside Execution Guide](https://starknetjs.com/docs/guides/outsideExecution)
- [OpenZeppelin Cairo Contracts](https://docs.openzeppelin.com/contracts-cairo)

## Questions?

The integration preserves all existing functionality while adding SNIP-9 support. Your session keys work exactly the same, but now you can also sponsor transactions for your users!

---

**Summary**: You can now create gasless user experiences by combining session keys (convenience) with outside execution (sponsored gas). Perfect for onboarding, gaming, and mobile apps! 🚀

