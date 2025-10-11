# Deployment Instructions for LLM

This guide provides step-by-step instructions for deploying updates to the Session Account Contract on Starknet mainnet.

## Prerequisites

Before deploying, ensure:
1. **Scarb** is installed (Cairo compiler)
2. **Starknet Foundry** (`sncast`) is installed
3. Account file exists at: `~/.starknet_accounts/starknet_open_zeppelin_accounts.json`
4. Account has sufficient STRK balance for gas fees (~3-5 STRK for declaration)

## Account Information

- **Account Name**: `deployer_oz`
- **Account Address**: `0x064b1cf9c492b9ea333db7d4a2836feeee31cd1e2720f43b22732873122d433e`
- **Network**: Starknet Mainnet

## Deployment Steps

### Step 1: Compile the Contract

```bash
cd /Users/diosplan/Documents/sessions-smart-contract
scarb build
```

**Expected output**: Compilation should complete successfully with no errors.

### Step 2: Verify Changes

Before deploying, review the changes made to ensure they are correct:
- Check `src/account.cairo` for modifications
- Run tests if available: `snforge test`
- Check for linter errors

### Step 3: Declare Contract Class on Mainnet

Use the `--network mainnet` flag which uses Starknet's public RPC:

```bash
sncast --account deployer_oz \
  --accounts-file ~/.starknet_accounts/starknet_open_zeppelin_accounts.json \
  declare \
  --contract-name Account \
  --network mainnet
```

**Expected output**:
```
Success: Declaration completed

Class Hash:       0x...
Transaction Hash: 0x...

To see declaration details, visit:
class: https://starkscan.co/class/0x...
transaction: https://starkscan.co/tx/0x...
```

**Common Issues**:

1. **Insufficient balance error**: 
   - Fund account with STRK tokens
   - Check balance at: https://starkscan.co/contract/0x064b1cf9c492b9ea333db7d4a2836feeee31cd1e2720f43b22732873122d433e

2. **RPC version mismatch**:
   - Use `--network mainnet` instead of custom RPC URLs
   - This uses Starknet's public provider with proper version compatibility

3. **Class already declared**:
   - This means the exact contract code is already on-chain
   - No action needed unless you need to modify the contract further

### Step 4: Update Documentation

After successful declaration, update `DEPLOYMENT.md` with:

1. **New version section** with:
   - Class Hash (from step 3 output)
   - Transaction Hash
   - Starkscan link
   - Date of deployment
   
2. **Key changes** describing what was modified

Example update:
```markdown
### Latest Class Declaration (vX - description)
- **Class Hash**: `0x...`
- **Transaction Hash**: `0x...`
- **Status**: ✅ Accepted on L2
- **Starkscan**: https://starkscan.co/class/0x...

## Key Changes in Version X (Date)
### 🔧 Fixed/Added: Description
**Problem**: Describe the issue
**Solution**: Describe the fix
```

### Step 5: Commit Changes

```bash
git add src/account.cairo DEPLOYMENT.md
git commit -m "Deploy vX: Brief description of changes"
git push origin main
```

## Important Notes

### Gas Fees
- Declarations typically cost 2-5 STRK
- Keep at least 10 STRK in deployer account for multiple deployments
- Gas prices vary based on network congestion

### Network Options
- **Mainnet**: Use `--network mainnet` (production)
- **Sepolia Testnet**: Use `--network sepolia` (testing)

### Account Security
- The account file contains private keys
- Never commit account files to git
- Keep backups in secure location

### Contract Upgrades
This contract uses the Upgradeable pattern. To upgrade existing deployed contracts:

1. Declare the new class (steps above)
2. Call the `upgrade` function on existing contract instances:
```bash
sncast --account deployer_oz \
  --accounts-file ~/.starknet_accounts/starknet_open_zeppelin_accounts.json \
  invoke \
  --contract-address <DEPLOYED_CONTRACT_ADDRESS> \
  --function upgrade \
  --calldata <NEW_CLASS_HASH> \
  --network mainnet
```

## Verification Checklist

Before declaring to mainnet:
- [ ] Contract compiles without errors
- [ ] All tests pass (if applicable)
- [ ] No linter errors
- [ ] Changes are documented in code comments
- [ ] DEPLOYMENT.md is ready to update
- [ ] Account has sufficient STRK balance
- [ ] You understand what changes are being deployed

After declaring:
- [ ] Transaction confirmed on Starkscan
- [ ] Class hash saved
- [ ] DEPLOYMENT.md updated
- [ ] Changes committed to git

## Troubleshooting

### Compilation Errors
- Ensure Scarb is up to date: `scarb --version`
- Expected version: 2.8.4 or later
- Update if needed: Check Scarb documentation

### sncast Not Found
```bash
# Install Starknet Foundry
curl -L https://raw.githubusercontent.com/foundry-rs/starknet-foundry/master/scripts/install.sh | sh
snfoundryup
```

### Old starkli Version
If using `starkli` instead of `sncast`:
```bash
starkliup  # Updates to latest version
```

## Quick Reference

**One-liner for common deployment**:
```bash
cd /Users/diosplan/Documents/sessions-smart-contract && \
scarb build && \
sncast --account deployer_oz --accounts-file ~/.starknet_accounts/starknet_open_zeppelin_accounts.json declare --contract-name Account --network mainnet
```

## Related Documentation

- Contract source: `src/account.cairo`
- Deployment history: `DEPLOYMENT.md`
- Project config: `Scarb.toml`
- Network config: `snfoundry.toml`
- Starknet Foundry Docs: https://foundry-rs.github.io/starknet-foundry/
- Starkscan Explorer: https://starkscan.co/


