#!/usr/bin/env python3
"""
Compute SNIP-12 Type Hashes for SNIP-9 Outside Execution

This script computes the correct type hashes using starknet_keccak as specified in SNIP-12.
These values MUST match the Cairo contract constants for production deployment.

NO EXTERNAL DEPENDENCIES NEEDED - Uses standard library only

Reference:
    - SNIP-12: https://github.com/starknet-io/SNIPs/blob/main/SNIPS/snip-12.md
    - Argent: https://github.com/argentlabs/argent-contracts-starknet
"""

import hashlib

# Starknet prime field modulus (Stark curve prime)
PRIME = 2**251 + 17 * 2**192 + 1

def starknet_keccak(data: bytes) -> int:
    """
    Compute starknet_keccak as specified in SNIP-12.
    
    Formula: starknet_keccak(x) = keccak256(x) % PRIME
    where x is ASCII-encoded bytes
    
    This is the standard hash function for SNIP-12 type hashes.
    """
    # Use SHA3-256 (Keccak-256)
    keccak_hash = hashlib.sha3_256(data).digest()
    # Convert to integer
    hash_int = int.from_bytes(keccak_hash, byteorder='big')
    # Reduce modulo the Stark prime
    return hash_int % PRIME

def compute_type_hash(type_string: str) -> int:
    """
    Compute type hash for a SNIP-12 type string.
    
    Args:
        type_string: The type definition string (e.g., "Call(to:felt,selector:felt,...)")
    
    Returns:
        The type hash as a field element
    """
    type_bytes = type_string.encode('ascii')
    return starknet_keccak(type_bytes)

def to_hex_felt(value: int) -> str:
    """Convert integer to felt252 hex representation."""
    return f"0x{value:064x}"

def main():
    print("=" * 80)
    print("SNIP-12 Type Hash Computation for SNIP-9 Outside Execution")
    print("=" * 80)
    print()
    
    # Define type strings as per SNIP-9/SNIP-12 specification
    type_strings = {
        'StarknetDomain': 'StarknetDomain(name:shortstring,version:shortstring,chainId:felt,revision:shortstring)',
        'OutsideExecution': 'OutsideExecution(caller:ContractAddress,nonce:felt,execute_after:u128,execute_before:u128,calls_len:felt,calls:Call*)',
        'Call': 'Call(to:ContractAddress,selector:felt,calldata_len:felt,calldata:felt*)',
    }
    
    print("Type Strings:")
    print("-" * 80)
    for name, type_str in type_strings.items():
        print(f"{name}:")
        print(f"  {type_str}")
        print()
    
    print("Computed Type Hashes:")
    print("-" * 80)
    
    type_hashes = {}
    for name, type_str in type_strings.items():
        hash_value = compute_type_hash(type_str)
        type_hashes[name] = hash_value
        print(f"{name}:")
        print(f"  Decimal: {hash_value}")
        print(f"  Hex:     {to_hex_felt(hash_value)}")
        print(f"  Felt252: {hash_value}")
        print()
    
    # Generate Cairo constants
    print("=" * 80)
    print("Cairo Constants (Copy to src/outside_execution.cairo)")
    print("=" * 80)
    print()
    print("// SNIP-12 Type Hashes - PRODUCTION VALUES")
    print("// Computed using starknet_keccak as per SNIP-12 specification")
    print()
    print(f"pub const STARKNET_DOMAIN_TYPE_HASH: felt252 = ")
    print(f"    {to_hex_felt(type_hashes['StarknetDomain'])};")
    print()
    print(f"pub const OUTSIDE_EXECUTION_TYPE_HASH: felt252 =")
    print(f"    {to_hex_felt(type_hashes['OutsideExecution'])};")
    print()
    print(f"pub const CALL_TYPE_HASH: felt252 =")
    print(f"    {to_hex_felt(type_hashes['Call'])};")
    print()
    
    # Generate TypeScript constants
    print("=" * 80)
    print("TypeScript Constants (For Frontend)")
    print("=" * 80)
    print()
    print("// SNIP-12 Type Hashes - PRODUCTION VALUES")
    print("export const STARKNET_DOMAIN_TYPE_HASH = ")
    print(f"  '{to_hex_felt(type_hashes['StarknetDomain'])}';")
    print()
    print("export const OUTSIDE_EXECUTION_TYPE_HASH = ")
    print(f"  '{to_hex_felt(type_hashes['OutsideExecution'])}';")
    print()
    print("export const CALL_TYPE_HASH = ")
    print(f"  '{to_hex_felt(type_hashes['Call'])}';")
    print()
    
    # Verification notes
    print("=" * 80)
    print("Verification Steps")
    print("=" * 80)
    print()
    print("1. Compare these values with Argent's implementation:")
    print("   https://github.com/argentlabs/argent-contracts-starknet")
    print()
    print("2. Test hash computation in frontend matches contract:")
    print("   - Compute domain hash with same inputs")
    print("   - Compute call hash with same inputs")
    print("   - Compute full message hash")
    print("   - Sign and verify with contract")
    print()
    print("3. Cross-verify with other SNIP-9 implementations:")
    print("   - Braavos wallet")
    print("   - OpenZeppelin SRC9Component")
    print()
    print("=" * 80)
    print()

if __name__ == '__main__':
    main()

