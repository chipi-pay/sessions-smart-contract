# Deploying SNIP-9 Compatible Contracts

## ✅ Pre-Deployment Verification

Both contracts have been verified as **SNIP-9 v2 compatible**:

### Production Contract (`account.cairo`)
- ✅ SRC9Component integrated
- ✅ `execute_from_outside` implemented
- ✅ `get_snip9_version()` returns 2
- ✅ Compatible with Paymaster services
- ✅ Version: `v23_snip9_compatible`

### Debug Contract (`debug_account.cairo`)
- ✅ SRC9Component integrated
- ✅ `execute_from_outside` implemented
- ✅ `get_snip9_version()` returns 2
- ✅ Compatible with Paymaster services
- ✅ Version: `v23_debug_snip9`
- ⚠️ Contains debug functions (testing only)

## 🚀 Deployment Steps

### Prerequisites

```bash
# Ensure you have starkli installed
starkli --version

# Ensure you have a funded account
starkli account fetch <YOUR_ACCOUNT_ADDRESS> --rpc https://starknet-mainnet.public.blastapi.io/rpc/v0_7

# Check balance
starkli balance <YOUR_ACCOUNT_ADDRESS> --rpc https://starknet-mainnet.public.blastapi.io/rpc/v0_7
```

### Step 1: Build Contracts

```bash
cd /Users/diosplan/Documents/sessions-smart-contract
scarb build
```

### Step 2: Declare Production Contract

```bash
# Declare the production contract (account.cairo)
starkli declare \
  target/dev/sessions_smart_contract_Account.contract_class.json \
  --account ~/.starkli-wallets/deployer/account.json \
  --keystore ~/.starkli-wallets/deployer/keystore.json \
  --rpc https://starknet-mainnet.public.blastapi.io/rpc/v0_7 \
  --watch

# Save the class hash that is returned
# Example output: Class hash: 0x...
```

### Step 3: Deploy Production Contract Instance

```bash
# Deploy an instance with your owner public key
starkli deploy \
  <PRODUCTION_CLASS_HASH> \
  <YOUR_OWNER_PUBLIC_KEY> \
  --account ~/.starkli-wallets/deployer/account.json \
  --keystore ~/.starkli-wallets/deployer/keystore.json \
  --rpc https://starknet-mainnet.public.blastapi.io/rpc/v0_7 \
  --watch

# Save the contract address that is returned
# Example output: Contract deployed at: 0x...
```

### Step 4: Declare Debug Contract (Optional - Testnet Only!)

⚠️ **WARNING**: NEVER deploy the debug contract to mainnet!

```bash
# For testnet/devnet only
starkli declare \
  target/dev/sessions_smart_contract_Account.contract_class.json \
  --account ~/.starkli-wallets/deployer/account.json \
  --keystore ~/.starkli-wallets/deployer/keystore.json \
  --rpc https://starknet-sepolia.public.blastapi.io/rpc/v0_7 \
  --watch

# Save the class hash
```

### Step 5: Verify SNIP-9 Compatibility

After deployment, verify the contracts:

```bash
# Check contract version
starkli call <CONTRACT_ADDRESS> get_contract_info \
  --rpc https://starknet-mainnet.public.blastapi.io/rpc/v0_7

# Should return: v23_snip9_compatible (production)
# Or: v23_debug_snip9 (debug)

# Check SNIP-9 version
starkli call <CONTRACT_ADDRESS> get_snip9_version \
  --rpc https://starknet-mainnet.public.blastapi.io/rpc/v0_7

# Should return: 2
```

### Step 6: Test Outside Execution

Test with Starknet.js:

```typescript
import { Account } from 'starknet';

// Check SNIP-9 support
const account = new Account(provider, accountAddress, privateKey);
const version = await account.getSnip9Version();
console.log('SNIP-9 Version:', version); // Should be 2

// Test execute_from_outside
const outsideTransaction = await account.getOutsideTransaction(
  {
    caller: executorAccount.address,
    execute_after: Math.floor(Date.now() / 1000) - 60,
    execute_before: Math.floor(Date.now() / 1000) + 3600
  },
  transferCall
);

await executorAccount.executeFromOutside(outsideTransaction);
```

### Step 7: Test Paymaster Integration

```typescript
import { PaymasterRpc } from 'starknet';

// Initialize Paymaster
const paymasterRpc = new PaymasterRpc({ default: true });

// Get supported gas tokens
const gasTokens = await paymasterRpc.getSupportedGasTokens();
console.log('Supported tokens:', gasTokens);

// Execute transaction with Paymaster
await account.executePaymasterTransaction(calls, {
  feeMode: { 
    mode: 'default', 
    gasToken: gasTokens[0].address 
  }
});
```

## 📝 Update README.md

After deployment, update the README.md with new class hashes:

```markdown
**Starknet Mainnet (Production Version v23 - SNIP-9 Compatible):**
- **Class Hash**: `0x<YOUR_NEW_PRODUCTION_CLASS_HASH>`
- **Contract Address**: `0x<YOUR_NEW_PRODUCTION_CONTRACT_ADDRESS>`
- **Network**: Starknet Mainnet
- **Compiler**: Cairo 2.11.4
- **SNIP-9**: v2 Compatible ✅
- **Paymaster**: Supported ✅
- **Deployed**: <CURRENT_DATE>

**Starknet Testnet (Debug Version v23 - FOR DEBUGGING ONLY):**
- **Class Hash**: `0x<YOUR_NEW_DEBUG_CLASS_HASH>`
- **Contract Address**: `0x<YOUR_NEW_DEBUG_CONTRACT_ADDRESS>`
- **Network**: Starknet Sepolia
- **Compiler**: Cairo 2.11.4
- **SNIP-9**: v2 Compatible ✅
- **Deployed**: <CURRENT_DATE>
```

## 🔍 Verification on Starkscan

After deployment, verify on Starkscan:

```
Production:
https://starkscan.co/class/<YOUR_CLASS_HASH>
https://starkscan.co/contract/<YOUR_CONTRACT_ADDRESS>

Debug (Testnet):
https://sepolia.starkscan.co/class/<YOUR_CLASS_HASH>
https://sepolia.starkscan.co/contract/<YOUR_CONTRACT_ADDRESS>
```

## ✅ Deployment Checklist

- [ ] Contracts built successfully
- [ ] Production contract declared on mainnet
- [ ] Production contract deployed with owner public key
- [ ] `get_contract_info()` returns `v23_snip9_compatible`
- [ ] `get_snip9_version()` returns `2`
- [ ] Outside execution tested
- [ ] Paymaster integration tested
- [ ] Session keys tested
- [ ] Sessions + Paymaster tested
- [ ] README.md updated with new class hashes
- [ ] Starkscan verification completed
- [ ] Debug contract only on testnet (if deployed)

## 🎯 Expected Gas Costs

Approximate gas costs on mainnet:

- **Declaration**: ~0.001-0.002 ETH
- **Deployment**: ~0.002-0.005 ETH
- **Total**: ~0.003-0.007 ETH

## 🔐 Security Notes

### Production Contract
- ✅ Safe for mainnet
- ✅ No debug functions
- ✅ Uses real tx_info
- ✅ Production-grade security

### Debug Contract
- ⚠️ **NEVER** deploy to mainnet
- ⚠️ Contains forced parameter functions
- ⚠️ Security vulnerabilities present
- ✅ Safe for local testing only

## 📞 Support

If you encounter issues:
1. Check the error message
2. Verify account has sufficient balance
3. Ensure correct network (mainnet vs testnet)
4. Review SNIP9_PAYMASTER_GUIDE.md
5. Check PRODUCTION_VS_DEBUG.md

## 🎉 Success Criteria

Your deployment is successful when:
- ✅ Contract returns SNIP-9 version 2
- ✅ `execute_from_outside` is callable
- ✅ Paymaster transactions work
- ✅ Session keys function correctly
- ✅ Sessions + Paymaster combination works
- ✅ All tests pass
- ✅ Starkscan shows the contract

---

**Note**: This guide assumes you're using starkli. Adjust commands if using a different deployment tool.

