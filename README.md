# Cairo Account Contract with Session Keys

This project implements a Starknet account contract based on OpenZeppelin's Account component (Cairo 2.x) with session key functionality.

## Features

- **OpenZeppelin Account Base**: Uses OpenZeppelin Cairo Contracts v2.0.0 (Cairo 2.x compatible)
- **Session Key Management**: Add, update, and revoke temporary session keys
- **Flexible Permissions**: Configure session keys with:
  - Time limits (valid_until timestamp)
  - Call limits (max_calls)
  - Entrypoint restrictions (specific methods or all methods)
- **SRC-9 Support**: Includes outside execution capabilities
- **Upgradeable**: Built-in upgrade functionality

## Contract Components

The contract uses the following OpenZeppelin components:
- `AccountComponent` - Core account functionality
- `SRC9Component` - Outside execution support
- `SRC5Component` - Interface detection
- `UpgradeableComponent` - Contract upgradeability

## Session Key Structure

```cairo
struct SessionData {
    valid_until: u64,           // Unix timestamp when session expires
    max_calls: u32,             // Maximum number of calls allowed
    calls_used: u32,            // Number of calls used so far
    allowed_entrypoints_len: u32, // Number of allowed entrypoints (0 = all)
}
```

## Key Functions

### Session Key Management

#### `add_or_update_session_key`
```cairo
fn add_or_update_session_key(
    ref self: ContractState,
    session_key: felt252,
    valid_until: u64,
    max_calls: u32,
    allowed_entrypoints: Array<felt252>
)
```
- **Access**: Only callable by the account itself (owner)
- **Purpose**: Create or update a session key with specific permissions
- **Parameters**:
  - `session_key`: The session key identifier
  - `valid_until`: Unix timestamp when the session expires
  - `max_calls`: Maximum number of transactions this session can execute
  - `allowed_entrypoints`: Array of allowed function selectors (empty = allow all)

#### `revoke_session_key`
```cairo
fn revoke_session_key(ref self: ContractState, session_key: felt252)
```
- **Access**: Only callable by the account itself (owner)
- **Purpose**: Immediately revoke a session key
- **Parameters**:
  - `session_key`: The session key to revoke

#### `get_session_data`
```cairo
fn get_session_data(self: @ContractState, session_key: felt252) -> SessionData
```
- **Access**: Public view function
- **Purpose**: Query the current state of a session key
- **Returns**: SessionData struct with all session information

### Internal Validation

The `_validate_session` function checks:
1. Session hasn't expired (timestamp check)
2. Session hasn't exceeded max calls
3. If entrypoints are specified, the called function is allowed
4. Increments the calls_used counter

## Setup and Installation

### Prerequisites
- [Scarb](https://docs.swmansion.com/scarb/) (Cairo/Starknet package manager)
- Starknet development environment

### Installation
```bash
# Clone the repository
git clone <repository-url>
cd sessions-smart-contract

# Build the contract
scarb build
```

The compiled contract will be in `target/dev/`.

## Deployment Guide

### 1. Deploy the Contract

```bash
# Using Starkli or your preferred deployment tool
starkli declare target/dev/sessions_smart_contract_Account.contract_class.json

# Deploy with your owner public key
starkli deploy <class_hash> <owner_public_key>
```

### 2. Add a Session Key (as Owner)

```bash
# Example: Create a session key valid for 24 hours, max 10 calls, all methods allowed
starkli invoke <account_address> add_or_update_session_key \
  <session_key_felt> \
  <valid_until_timestamp> \
  10 \
  []  # Empty array = allow all entrypoints
```

### 3. Add Session Key with Specific Entrypoints

```bash
# Example: Session key limited to specific functions
starkli invoke <account_address> add_or_update_session_key \
  <session_key_felt> \
  <valid_until_timestamp> \
  5 \
  [<entrypoint_selector_1>, <entrypoint_selector_2>]
```

### 4. Use Session Key

When the session key validation is integrated with `__validate__`, transactions signed with the session key will be validated according to the session rules.

### 5. Check Session Data

```bash
starkli call <account_address> get_session_data <session_key_felt>
```

### 6. Revoke Session Key

```bash
starkli invoke <account_address> revoke_session_key <session_key_felt>
```

## Testing

### Run Tests
```bash
scarb test
```

### Manual Testing Checklist

1. **Deploy** the contract with owner public key
2. **Add Session Key** with unrestricted access (empty entrypoints array)
3. **Execute Transaction** signed with session key - should succeed
4. **Check Session Data** - verify calls_used incremented
5. **Exceed Max Calls** - should fail validation
6. **Add Session Key** with specific entrypoints
7. **Call Allowed Method** - should succeed
8. **Call Restricted Method** - should fail
9. **Revoke Session Key** - should succeed
10. **Use Revoked Key** - should fail validation

## Security Considerations

1. **Owner Control**: Only the account owner can add or revoke session keys
2. **Time-based Expiration**: All session keys must have an expiration timestamp
3. **Call Limits**: Session keys have a maximum number of calls to prevent abuse
4. **Entrypoint Restrictions**: Fine-grained control over which functions can be called
5. **Non-transferable**: Session keys are bound to the specific account contract

## Integration Notes

### __validate__ Integration (Next Step)

To fully integrate session key validation, the `__validate__` function needs to be implemented to:
1. First try to validate with the owner's signature (standard flow)
2. If owner validation fails, check if there's a valid session key signature
3. Validate the session key using `_validate_session`
4. Return appropriate validation result

This requires custom signature handling that works alongside OpenZeppelin's account validation.

## Project Structure

```
sessions-smart-contract/
├── src/
│   ├── lib.cairo           # Module declarations
│   └── account.cairo       # Main account contract with session keys
├── tests/
│   └── test_account.cairo  # Test cases
├── Scarb.toml             # Package configuration
└── README.md              # This file
```

## License

MIT

## Resources

- [OpenZeppelin Cairo Contracts](https://github.com/OpenZeppelin/cairo-contracts)
- [Starknet Documentation](https://docs.starknet.io/)
- [Cairo Book](https://book.cairo-lang.org/)

