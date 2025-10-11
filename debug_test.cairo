use starknet::ContractAddress;
use snforge_std_deprecated::{
    declare, ContractClassTrait, DeclareResultTrait,
    start_cheat_caller_address, stop_cheat_caller_address,
    start_cheat_block_timestamp_global
};

// Import the contract interface
use sessions_smart_contract::account::{
    ISessionKeyManagerDispatcher, ISessionKeyManagerDispatcherTrait
};

// Test constants
const OWNER_PUBKEY: felt252 = 0x123456789abcdef123456789abcdef123456789abcdef123456789abcdef;
const SESSION_PUBKEY: felt252 = 0x987654321fedcba987654321fedcba987654321fedcba987654321fedcba;

// Selector for a transfer function
const TRANSFER_SELECTOR: felt252 = 0x83afd3f4caedc6eebf44246fe54e38c95e3179a5ec9ea81740eca5b482d12e;
// Selector for a wave function  
const WAVE_SELECTOR: felt252 = 0x36af806f8c6a244b75823a6f3f912e5fad5c6b8a7c5e6d9b2a1f8e7c;

fn deploy_account() -> (ContractAddress, ISessionKeyManagerDispatcher) {
    let contract_class = declare("Account").unwrap().contract_class();
    let constructor_calldata = array![OWNER_PUBKEY];
    let (contract_address, _) = contract_class.deploy(@constructor_calldata).unwrap();
    
    let dispatcher = ISessionKeyManagerDispatcher { contract_address };
    (contract_address, dispatcher)
}

#[test]
fn test_debug_entrypoint_storage() {
    let (account_address, session_manager) = deploy_account();
    
    // Add session key as owner
    start_cheat_caller_address(account_address, account_address);
    
    let current_time = 1000000_u64;
    start_cheat_block_timestamp_global(current_time);
    
    let valid_until = current_time + 86400; // 24 hours from now
    let max_calls = 10_u32;
    let allowed_entrypoints = array![TRANSFER_SELECTOR, WAVE_SELECTOR]; // 2 entrypoints
    
    session_manager.add_or_update_session_key(
        SESSION_PUBKEY,
        valid_until,
        max_calls,
        allowed_entrypoints
    );
    
    stop_cheat_caller_address(account_address);
    
    // Check session data
    let session_data = session_manager.get_session_data(SESSION_PUBKEY);
    assert(session_data.valid_until == valid_until, 'Session not added');
    assert(session_data.max_calls == max_calls, 'Wrong max_calls');
    assert(session_data.calls_used == 0, 'Should start at 0');
    
    // This should be 2, not 1!
    assert(session_data.allowed_entrypoints_len == 2, 'Wrong entrypoints_len');
}
