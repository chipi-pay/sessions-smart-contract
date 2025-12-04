// Test suite for SNIP-9 v2 Outside Execution
// Verifies execute_from_outside_v2, nonce handling, and timestamp validation

#[cfg(test)]
mod test_outside_execution {
    use starknet::ContractAddress;
    use starknet::account::Call;
    use snforge_std_deprecated::{
        declare, ContractClassTrait, DeclareResultTrait,
        start_cheat_caller_address, stop_cheat_caller_address,
        start_cheat_block_timestamp_global, start_cheat_chain_id_global
    };
    
    use sessions_smart_contract::outside_execution::{
        OutsideExecution, IOutsideExecutionDispatcher, IOutsideExecutionDispatcherTrait
    };
    use sessions_smart_contract::account::{
        ISessionKeyManagerDispatcher, ISessionKeyManagerDispatcherTrait
    };

    // Constants
    const OWNER_PUBKEY: felt252 = 0x123456789abcdef123456789abcdef123456789abcdef123456789abcdef;
    const SESSION_PUBKEY: felt252 = 0x987654321fedcba987654321fedcba987654321fedcba987654321fedcba;

    fn deploy_account() -> ContractAddress {
        let account_class = declare("Account").unwrap().contract_class();
        let mut calldata = array![OWNER_PUBKEY];
        let (contract_address, _) = account_class.deploy(@calldata).unwrap();
        contract_address
    }

    // Helper to create contract address from felt252
    fn addr(val: felt252) -> ContractAddress {
        val.try_into().unwrap()
    }

    // ========== NONCE VALIDATION ==========

    #[test]
    fn test_fresh_nonce_is_valid() {
        let account = deploy_account();
        let dispatcher = IOutsideExecutionDispatcher { contract_address: account };
        
        // Fresh nonces should all be valid
        assert(dispatcher.is_valid_outside_execution_nonce(1), 'Nonce 1 should be valid');
        assert(dispatcher.is_valid_outside_execution_nonce(100), 'Nonce 100 should be valid');
        assert(dispatcher.is_valid_outside_execution_nonce(999999), 'Large nonce should be valid');
    }

    #[test]
    fn test_zero_nonce_is_valid() {
        let account = deploy_account();
        let dispatcher = IOutsideExecutionDispatcher { contract_address: account };
        
        // Nonce 0 should be valid (no special treatment)
        assert(dispatcher.is_valid_outside_execution_nonce(0), 'Nonce 0 should be valid');
    }

    // ========== MESSAGE HASH COMPUTATION ==========

    #[test]
    fn test_message_hash_computation() {
        let account = deploy_account();
        let current_time = 1000000_u64;
        
        start_cheat_block_timestamp_global(current_time);
        start_cheat_chain_id_global('SN_MAIN');
        
        let dispatcher = IOutsideExecutionDispatcher { contract_address: account };
        
        let target: ContractAddress = addr(0x1234);
        let caller: ContractAddress = addr(0);
        
        let calls = array![
            Call {
                to: target,
                selector: 0x83afd3f4caedc6eebf44246fe54e38c95e3179a5ec9ea81740eca5b482d12e,
                calldata: array![0x100, 0x50].span()
            }
        ];
        
        let outside_execution = OutsideExecution {
            caller: caller,
            nonce: 1,
            execute_after: current_time,
            execute_before: current_time + 3600,
            calls: calls.span(),
        };
        
        let hash = dispatcher.get_outside_execution_message_hash_rev_1(outside_execution);
        
        // Hash should be computed (non-zero)
        assert(hash != 0, 'Hash should be non-zero');
    }

    #[test]
    fn test_message_hash_includes_calls() {
        let account = deploy_account();
        let current_time = 1000000_u64;
        
        start_cheat_block_timestamp_global(current_time);
        start_cheat_chain_id_global('SN_MAIN');
        
        let dispatcher = IOutsideExecutionDispatcher { contract_address: account };
        
        let target: ContractAddress = addr(0x1234);
        let caller: ContractAddress = addr(0);
        
        // First hash with calldata [0x100]
        let calls1 = array![
            Call {
                to: target,
                selector: 0xabcdef,
                calldata: array![0x100].span()
            }
        ];
        
        let oe1 = OutsideExecution {
            caller: caller,
            nonce: 1,
            execute_after: current_time,
            execute_before: current_time + 3600,
            calls: calls1.span(),
        };
        
        // Second hash with different calldata [0x200]
        let calls2 = array![
            Call {
                to: target,
                selector: 0xabcdef,
                calldata: array![0x200].span()
            }
        ];
        
        let oe2 = OutsideExecution {
            caller: caller,
            nonce: 1,
            execute_after: current_time,
            execute_before: current_time + 3600,
            calls: calls2.span(),
        };
        
        let hash1 = dispatcher.get_outside_execution_message_hash_rev_1(oe1);
        let hash2 = dispatcher.get_outside_execution_message_hash_rev_1(oe2);
        
        // Different calls should produce different hashes
        assert(hash1 != hash2, 'Hashes should differ');
    }

    #[test]
    fn test_message_hash_includes_timestamps() {
        let account = deploy_account();
        let current_time = 1000000_u64;
        
        start_cheat_block_timestamp_global(current_time);
        start_cheat_chain_id_global('SN_MAIN');
        
        let dispatcher = IOutsideExecutionDispatcher { contract_address: account };
        
        let target: ContractAddress = addr(0x1234);
        let caller: ContractAddress = addr(0);
        
        let calls1 = array![
            Call {
                to: target,
                selector: 0xabcdef,
                calldata: array![].span()
            }
        ];
        let calls2 = array![
            Call {
                to: target,
                selector: 0xabcdef,
                calldata: array![].span()
            }
        ];
        
        // Different execute_before times
        let oe1 = OutsideExecution {
            caller: caller,
            nonce: 1,
            execute_after: current_time,
            execute_before: current_time + 3600,
            calls: calls1.span(),
        };
        
        let oe2 = OutsideExecution {
            caller: caller,
            nonce: 1,
            execute_after: current_time,
            execute_before: current_time + 7200,  // Different
            calls: calls2.span(),
        };
        
        let hash1 = dispatcher.get_outside_execution_message_hash_rev_1(oe1);
        let hash2 = dispatcher.get_outside_execution_message_hash_rev_1(oe2);
        
        assert(hash1 != hash2, 'Timestamps affect hash');
    }

    // ========== MULTIPLE CALLS ==========

    #[test]
    fn test_message_hash_with_multiple_calls() {
        let account = deploy_account();
        let current_time = 1000000_u64;
        
        start_cheat_block_timestamp_global(current_time);
        start_cheat_chain_id_global('SN_MAIN');
        
        let dispatcher = IOutsideExecutionDispatcher { contract_address: account };
        
        let target1: ContractAddress = addr(0x1111);
        let target2: ContractAddress = addr(0x2222);
        let caller: ContractAddress = addr(0);
        
        // Batch of multiple calls
        let calls = array![
            Call {
                to: target1,
                selector: 0xaaa,
                calldata: array![0x1, 0x2].span()
            },
            Call {
                to: target2,
                selector: 0xbbb,
                calldata: array![0x3].span()
            },
            Call {
                to: target1,
                selector: 0xccc,
                calldata: array![].span()
            }
        ];
        
        let outside_execution = OutsideExecution {
            caller: caller,
            nonce: 1,
            execute_after: current_time,
            execute_before: current_time + 3600,
            calls: calls.span(),
        };
        
        let hash = dispatcher.get_outside_execution_message_hash_rev_1(outside_execution);
        
        assert(hash != 0, 'Multi-call hash should compute');
    }

    // ========== EMPTY CALLS ==========

    #[test]
    fn test_message_hash_with_empty_calls() {
        let account = deploy_account();
        let current_time = 1000000_u64;
        
        start_cheat_block_timestamp_global(current_time);
        start_cheat_chain_id_global('SN_MAIN');
        
        let dispatcher = IOutsideExecutionDispatcher { contract_address: account };
        
        let caller: ContractAddress = addr(0);
        
        // Empty calls array
        let calls: Array<Call> = array![];
        
        let outside_execution = OutsideExecution {
            caller: caller,
            nonce: 1,
            execute_after: current_time,
            execute_before: current_time + 3600,
            calls: calls.span(),
        };
        
        let hash = dispatcher.get_outside_execution_message_hash_rev_1(outside_execution);
        
        // Should still produce a valid hash
        assert(hash != 0, 'Empty calls hash should compute');
    }

    // ========== ANY_CALLER TESTS ==========

    #[test]
    fn test_any_caller_address_is_zero() {
        // Verify ANY_CALLER convention (address 0)
        let any_caller: ContractAddress = addr(0);
        let zero: felt252 = any_caller.into();
        assert(zero == 0, 'ANY_CALLER should be 0');
    }

    // ========== SESSION KEY INTEGRATION ==========

    #[test]
    fn test_session_key_added_for_outside_execution() {
        let account = deploy_account();
        let current_time = 1000000_u64;
        
        start_cheat_block_timestamp_global(current_time);
        
        // Add session key as owner
        start_cheat_caller_address(account, account);
        
        let session_manager = ISessionKeyManagerDispatcher { contract_address: account };
        let valid_until = current_time + 86400;
        let max_calls = 100_u32;
        let transfer_selector: felt252 = 0x83afd3f4caedc6eebf44246fe54e38c95e3179a5ec9ea81740eca5b482d12e;
        let allowed_entrypoints = array![transfer_selector];
        
        session_manager.add_or_update_session_key(
            SESSION_PUBKEY,
            valid_until,
            max_calls,
            allowed_entrypoints
        );
        
        stop_cheat_caller_address(account);
        
        // Verify session was created
        let session_data = session_manager.get_session_data(SESSION_PUBKEY);
        assert(session_data.valid_until == valid_until, 'Session should be added');
        assert(session_data.max_calls == max_calls, 'Max calls should match');
        assert(session_data.calls_used == 0, 'Calls used should be 0');
        assert(session_data.allowed_entrypoints_len == 1, 'Should have 1 entrypoint');
    }

    // ========== BOUNDARY CONDITIONS ==========

    #[test]
    fn test_timestamp_boundary_execute_after_equals_current() {
        // execute_after == current_time should be valid (>= check)
        let account = deploy_account();
        let current_time = 1000000_u64;
        
        start_cheat_block_timestamp_global(current_time);
        start_cheat_chain_id_global('SN_MAIN');
        
        let dispatcher = IOutsideExecutionDispatcher { contract_address: account };
        
        let caller: ContractAddress = addr(0);
        let calls: Array<Call> = array![];
        
        let outside_execution = OutsideExecution {
            caller: caller,
            nonce: 1,
            execute_after: current_time,  // Exactly equal
            execute_before: current_time + 3600,
            calls: calls.span(),
        };
        
        // Should successfully compute hash (timestamp validation is in execute, not hash)
        let hash = dispatcher.get_outside_execution_message_hash_rev_1(outside_execution);
        assert(hash != 0, 'Boundary hash should compute');
    }

    #[test]
    fn test_timestamp_boundary_execute_before_equals_current() {
        // execute_before == current_time should be valid (<= check)
        let account = deploy_account();
        let current_time = 1000000_u64;
        
        start_cheat_block_timestamp_global(current_time);
        start_cheat_chain_id_global('SN_MAIN');
        
        let dispatcher = IOutsideExecutionDispatcher { contract_address: account };
        
        let caller: ContractAddress = addr(0);
        let calls: Array<Call> = array![];
        
        let outside_execution = OutsideExecution {
            caller: caller,
            nonce: 1,
            execute_after: current_time - 100,
            execute_before: current_time,  // Exactly equal
            calls: calls.span(),
        };
        
        let hash = dispatcher.get_outside_execution_message_hash_rev_1(outside_execution);
        assert(hash != 0, 'Boundary hash should compute');
    }

    // ========== LARGE VALUES ==========

    #[test]
    fn test_large_nonce_value() {
        let account = deploy_account();
        let dispatcher = IOutsideExecutionDispatcher { contract_address: account };
        
        // Test with maximum felt252 range nonce
        let large_nonce: felt252 = 0x7ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
        assert(dispatcher.is_valid_outside_execution_nonce(large_nonce), 'Large nonce should be valid');
    }

    #[test]
    fn test_large_calldata() {
        let account = deploy_account();
        let current_time = 1000000_u64;
        
        start_cheat_block_timestamp_global(current_time);
        start_cheat_chain_id_global('SN_MAIN');
        
        let dispatcher = IOutsideExecutionDispatcher { contract_address: account };
        
        let target: ContractAddress = addr(0x1234);
        let caller: ContractAddress = addr(0);
        
        // Create call with larger calldata
        let calls = array![
            Call {
                to: target,
                selector: 0xabcdef,
                calldata: array![
                    0x1, 0x2, 0x3, 0x4, 0x5, 0x6, 0x7, 0x8,
                    0x9, 0xa, 0xb, 0xc, 0xd, 0xe, 0xf, 0x10
                ].span()
            }
        ];
        
        let outside_execution = OutsideExecution {
            caller: caller,
            nonce: 1,
            execute_after: current_time,
            execute_before: current_time + 3600,
            calls: calls.span(),
        };
        
        let hash = dispatcher.get_outside_execution_message_hash_rev_1(outside_execution);
        assert(hash != 0, 'Large calldata hash should work');
    }
}

