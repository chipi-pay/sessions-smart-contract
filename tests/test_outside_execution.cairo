// Comprehensive test suite for SNIP-9 v2 Outside Execution
// Tests the OutsideExecutionComponent with session key integration

#[cfg(test)]
mod test_outside_execution {
    use core::array::ArrayTrait;
    use core::traits::TryInto;
    use starknet::account::Call;
    use starknet::ContractAddress;
    use starknet::contract_address_const;
    use starknet::get_block_timestamp;
    use starknet::testing::{set_caller_address, set_contract_address, set_block_timestamp};
    
    // Import your account with outside execution
    // Note: You'll need to update this import once you integrate into your account.cairo
    use sessions_smart_contract::outside_execution::{
        OutsideExecution, IOutsideExecutionDispatcher, IOutsideExecutionDispatcherTrait
    };

    // Helper: Deploy a mock target contract for testing
    fn deploy_mock_target() -> ContractAddress {
        // Mock contract that we'll call via outside execution
        contract_address_const::<'target'>()
    }

    // Helper: Deploy account with outside execution
    fn deploy_account() -> ContractAddress {
        // This would deploy your account_with_outside_execution
        // For now, returning a mock address
        contract_address_const::<'account'>()
    }

    // Helper: Get test addresses
    fn owner_address() -> ContractAddress {
        contract_address_const::<'owner'>()
    }

    fn session_key_address() -> ContractAddress {
        contract_address_const::<'session'>()
    }

    fn executor_address() -> ContractAddress {
        contract_address_const::<'executor'>()
    }

    #[test]
    fn test_execute_from_outside_owner_signature() {
        // Setup
        let account = deploy_account();
        let target = deploy_mock_target();
        let current_time = 1000_u64;
        set_block_timestamp(current_time);
        set_contract_address(account);

        // Create outside execution
        let outside_execution = OutsideExecution {
            caller: contract_address_const::<0>(), // ANY_CALLER
            nonce: 1,
            execute_after: current_time,
            execute_before: current_time + 3600,
        };

        // Create calls
        let mut calls = ArrayTrait::new();
        calls.append(Call {
            to: target,
            selector: selector!("transfer"),
            calldata: array![0x123, 0x456].span()
        });

        // Sign with owner (2-element signature)
        let signature = array![0x111, 0x222]; // Mock r, s

        // Execute
        let dispatcher = IOutsideExecutionDispatcher { contract_address: account };
        let results = dispatcher.execute_from_outside_v2(
            outside_execution,
            calls,
            signature
        );

        // Verify nonce was consumed
        assert(!dispatcher.is_valid_outside_execution_nonce(1), 'Nonce should be used');
    }

    #[test]
    fn test_execute_from_outside_session_signature() {
        // Setup
        let account = deploy_account();
        let target = deploy_mock_target();
        let current_time = 1000_u64;
        let valid_until = current_time + 86400; // 24h
        set_block_timestamp(current_time);
        set_contract_address(account);

        // Add session key first (would need to call add_or_update_session_key)
        // ... (mock this)

        // Create outside execution
        let outside_execution = OutsideExecution {
            caller: contract_address_const::<0>(),
            nonce: 2,
            execute_after: current_time,
            execute_before: valid_until,
        };

        // Create calls
        let mut calls = ArrayTrait::new();
        calls.append(Call {
            to: target,
            selector: selector!("make_move"),
            calldata: array![0x1].span()
        });

        // Sign with session key (4-element signature)
        let session_pubkey = 0x999;
        let signature = array![
            session_pubkey,  // session public key
            0x333,           // r
            0x444,           // s
            valid_until.into() // valid_until
        ];

        // Execute
        let dispatcher = IOutsideExecutionDispatcher { contract_address: account };
        let results = dispatcher.execute_from_outside_v2(
            outside_execution,
            calls,
            signature
        );

        // Verify nonce was consumed
        assert(!dispatcher.is_valid_outside_execution_nonce(2), 'Nonce should be used');
    }

    #[test]
    #[should_panic(expected: ('OE: Nonce already used',))]
    fn test_nonce_replay_prevention() {
        // Setup
        let account = deploy_account();
        let target = deploy_mock_target();
        let current_time = 1000_u64;
        set_block_timestamp(current_time);
        set_contract_address(account);

        // Create outside execution
        let outside_execution = OutsideExecution {
            caller: contract_address_const::<0>(),
            nonce: 3,
            execute_after: current_time,
            execute_before: current_time + 3600,
        };

        // Create calls
        let mut calls = ArrayTrait::new();
        calls.append(Call {
            to: target,
            selector: selector!("transfer"),
            calldata: array![].span()
        });

        let signature = array![0x111, 0x222];

        let dispatcher = IOutsideExecutionDispatcher { contract_address: account };
        
        // First execution - should succeed
        dispatcher.execute_from_outside_v2(
            outside_execution,
            calls.clone(),
            signature.clone()
        );

        // Second execution with same nonce - should panic
        dispatcher.execute_from_outside_v2(
            outside_execution,
            calls,
            signature
        );
    }

    #[test]
    #[should_panic(expected: ('OE: Invalid timestamp',))]
    fn test_execute_after_validation() {
        // Setup
        let account = deploy_account();
        let target = deploy_mock_target();
        let current_time = 1000_u64;
        set_block_timestamp(current_time);
        set_contract_address(account);

        // Create outside execution with execute_after in the future
        let outside_execution = OutsideExecution {
            caller: contract_address_const::<0>(),
            nonce: 4,
            execute_after: current_time + 100, // Too early!
            execute_before: current_time + 3600,
        };

        let mut calls = ArrayTrait::new();
        calls.append(Call {
            to: target,
            selector: selector!("transfer"),
            calldata: array![].span()
        });

        let signature = array![0x111, 0x222];

        let dispatcher = IOutsideExecutionDispatcher { contract_address: account };
        dispatcher.execute_from_outside_v2(outside_execution, calls, signature);
    }

    #[test]
    #[should_panic(expected: ('OE: Invalid timestamp',))]
    fn test_execute_before_validation() {
        // Setup
        let account = deploy_account();
        let target = deploy_mock_target();
        let current_time = 1000_u64;
        set_block_timestamp(current_time);
        set_contract_address(account);

        // Create outside execution with execute_before in the past
        let outside_execution = OutsideExecution {
            caller: contract_address_const::<0>(),
            nonce: 5,
            execute_after: current_time - 200,
            execute_before: current_time - 100, // Already expired!
        };

        let mut calls = ArrayTrait::new();
        calls.append(Call {
            to: target,
            selector: selector!("transfer"),
            calldata: array![].span()
        });

        let signature = array![0x111, 0x222];

        let dispatcher = IOutsideExecutionDispatcher { contract_address: account };
        dispatcher.execute_from_outside_v2(outside_execution, calls, signature);
    }

    #[test]
    #[should_panic(expected: ('OE: Invalid caller',))]
    fn test_caller_restriction() {
        // Setup
        let account = deploy_account();
        let target = deploy_mock_target();
        let current_time = 1000_u64;
        let trusted_executor = contract_address_const::<'trusted'>();
        let untrusted_executor = contract_address_const::<'untrusted'>();
        
        set_block_timestamp(current_time);
        set_contract_address(account);
        
        // Set actual caller to untrusted
        set_caller_address(untrusted_executor);

        // Create outside execution restricted to trusted_executor only
        let outside_execution = OutsideExecution {
            caller: trusted_executor, // Only this address can execute
            nonce: 6,
            execute_after: current_time,
            execute_before: current_time + 3600,
        };

        let mut calls = ArrayTrait::new();
        calls.append(Call {
            to: target,
            selector: selector!("transfer"),
            calldata: array![].span()
        });

        let signature = array![0x111, 0x222];

        let dispatcher = IOutsideExecutionDispatcher { contract_address: account };
        dispatcher.execute_from_outside_v2(outside_execution, calls, signature);
    }

    #[test]
    fn test_unrestricted_caller() {
        // Setup
        let account = deploy_account();
        let target = deploy_mock_target();
        let current_time = 1000_u64;
        let random_executor = contract_address_const::<'random'>();
        
        set_block_timestamp(current_time);
        set_contract_address(account);
        set_caller_address(random_executor);

        // Create outside execution with ANY_CALLER (0x0)
        let outside_execution = OutsideExecution {
            caller: contract_address_const::<0>(), // Anyone can execute
            nonce: 7,
            execute_after: current_time,
            execute_before: current_time + 3600,
        };

        let mut calls = ArrayTrait::new();
        calls.append(Call {
            to: target,
            selector: selector!("transfer"),
            calldata: array![].span()
        });

        let signature = array![0x111, 0x222];

        let dispatcher = IOutsideExecutionDispatcher { contract_address: account };
        let results = dispatcher.execute_from_outside_v2(
            outside_execution,
            calls,
            signature
        );

        // Should succeed - any caller allowed
        assert(!dispatcher.is_valid_outside_execution_nonce(7), 'Nonce should be used');
    }

    #[test]
    fn test_multiple_calls() {
        // Setup
        let account = deploy_account();
        let target1 = contract_address_const::<'target1'>();
        let target2 = contract_address_const::<'target2'>();
        let current_time = 1000_u64;
        set_block_timestamp(current_time);
        set_contract_address(account);

        // Create outside execution
        let outside_execution = OutsideExecution {
            caller: contract_address_const::<0>(),
            nonce: 8,
            execute_after: current_time,
            execute_before: current_time + 3600,
        };

        // Create multiple calls
        let mut calls = ArrayTrait::new();
        calls.append(Call {
            to: target1,
            selector: selector!("transfer"),
            calldata: array![0x123].span()
        });
        calls.append(Call {
            to: target2,
            selector: selector!("approve"),
            calldata: array![0x456, 0x789].span()
        });

        let signature = array![0x111, 0x222];

        let dispatcher = IOutsideExecutionDispatcher { contract_address: account };
        let results = dispatcher.execute_from_outside_v2(
            outside_execution,
            calls,
            signature
        );

        // Verify both calls were executed
        assert(results.len() == 2, 'Should have 2 results');
    }

    #[test]
    fn test_nonce_validity_check() {
        // Setup
        let account = deploy_account();
        let dispatcher = IOutsideExecutionDispatcher { contract_address: account };

        // Fresh nonce should be valid
        assert(dispatcher.is_valid_outside_execution_nonce(999), 'Nonce 999 should be valid');
        
        // After executing with a nonce, it should be invalid
        // (would need to execute first, but this tests the interface)
    }

    #[test]
    fn test_message_hash_computation() {
        // Setup
        let account = deploy_account();
        let target = deploy_mock_target();
        let current_time = 1000_u64;
        set_block_timestamp(current_time);

        // Create outside execution
        let outside_execution = OutsideExecution {
            caller: contract_address_const::<0>(),
            nonce: 100,
            execute_after: current_time,
            execute_before: current_time + 3600,
        };

        // Create calls
        let mut calls = ArrayTrait::new();
        calls.append(Call {
            to: target,
            selector: selector!("transfer"),
            calldata: array![0x123, 0x456].span()
        });

        let dispatcher = IOutsideExecutionDispatcher { contract_address: account };
        let hash = dispatcher.get_outside_execution_message_hash_rev_1(
            outside_execution,
            calls.span()
        );

        // Verify hash is computed (non-zero)
        assert(hash != 0, 'Hash should be non-zero');
    }

    #[test]
    #[should_panic(expected: ('OE: Invalid signature',))]
    fn test_invalid_signature() {
        // Setup
        let account = deploy_account();
        let target = deploy_mock_target();
        let current_time = 1000_u64;
        set_block_timestamp(current_time);
        set_contract_address(account);

        // Create outside execution
        let outside_execution = OutsideExecution {
            caller: contract_address_const::<0>(),
            nonce: 10,
            execute_after: current_time,
            execute_before: current_time + 3600,
        };

        let mut calls = ArrayTrait::new();
        calls.append(Call {
            to: target,
            selector: selector!("transfer"),
            calldata: array![].span()
        });

        // Invalid signature (wrong r, s values)
        let signature = array![0x000, 0x000];

        let dispatcher = IOutsideExecutionDispatcher { contract_address: account };
        dispatcher.execute_from_outside_v2(outside_execution, calls, signature);
    }

    #[test]
    fn test_session_with_entrypoint_restrictions() {
        // Test that session key can only call allowed entrypoints via outside execution
        let account = deploy_account();
        let target = deploy_mock_target();
        let current_time = 1000_u64;
        let valid_until = current_time + 86400;
        set_block_timestamp(current_time);
        set_contract_address(account);

        // Add session key with entrypoint restriction (mock)
        // Session only allows 'transfer' selector

        // Create outside execution
        let outside_execution = OutsideExecution {
            caller: contract_address_const::<0>(),
            nonce: 11,
            execute_after: current_time,
            execute_before: valid_until,
        };

        // Call allowed entrypoint - should succeed
        let mut calls = ArrayTrait::new();
        calls.append(Call {
            to: target,
            selector: selector!("transfer"), // Allowed
            calldata: array![].span()
        });

        let session_pubkey = 0x999;
        let signature = array![session_pubkey, 0x333, 0x444, valid_until.into()];

        let dispatcher = IOutsideExecutionDispatcher { contract_address: account };
        dispatcher.execute_from_outside_v2(outside_execution, calls, signature);

        // Verify success (no panic)
    }

    #[test]
    #[should_panic(expected: ('OE: Invalid signature',))]
    fn test_session_with_restricted_entrypoint_fails() {
        // Test that session key cannot call non-allowed entrypoints
        let account = deploy_account();
        let target = deploy_mock_target();
        let current_time = 1000_u64;
        let valid_until = current_time + 86400;
        set_block_timestamp(current_time);
        set_contract_address(account);

        // Session only allows 'transfer' selector (mock)

        // Create outside execution
        let outside_execution = OutsideExecution {
            caller: contract_address_const::<0>(),
            nonce: 12,
            execute_after: current_time,
            execute_before: valid_until,
        };

        // Call disallowed entrypoint - should fail
        let mut calls = ArrayTrait::new();
        calls.append(Call {
            to: target,
            selector: selector!("upgrade"), // Not allowed!
            calldata: array![].span()
        });

        let session_pubkey = 0x999;
        let signature = array![session_pubkey, 0x333, 0x444, valid_until.into()];

        let dispatcher = IOutsideExecutionDispatcher { contract_address: account };
        dispatcher.execute_from_outside_v2(outside_execution, calls, signature);
    }

    #[test]
    fn test_session_call_limit() {
        // Test that session key respects max_calls limit
        let account = deploy_account();
        let target = deploy_mock_target();
        let current_time = 1000_u64;
        let valid_until = current_time + 86400;
        set_block_timestamp(current_time);

        // Add session with max_calls = 2 (mock)

        let session_pubkey = 0x999;
        let dispatcher = IOutsideExecutionDispatcher { contract_address: account };

        // First call - should succeed
        set_contract_address(account);
        let outside_execution1 = OutsideExecution {
            caller: contract_address_const::<0>(),
            nonce: 13,
            execute_after: current_time,
            execute_before: valid_until,
        };
        let mut calls1 = ArrayTrait::new();
        calls1.append(Call {
            to: target,
            selector: selector!("transfer"),
            calldata: array![].span()
        });
        let signature1 = array![session_pubkey, 0x333, 0x444, valid_until.into()];
        dispatcher.execute_from_outside_v2(outside_execution1, calls1, signature1);

        // Second call - should succeed
        let outside_execution2 = OutsideExecution {
            caller: contract_address_const::<0>(),
            nonce: 14,
            execute_after: current_time,
            execute_before: valid_until,
        };
        let mut calls2 = ArrayTrait::new();
        calls2.append(Call {
            to: target,
            selector: selector!("transfer"),
            calldata: array![].span()
        });
        let signature2 = array![session_pubkey, 0x555, 0x666, valid_until.into()];
        dispatcher.execute_from_outside_v2(outside_execution2, calls2, signature2);

        // Third call - should fail (max_calls exceeded)
        // (would need mock to actually enforce this)
    }
}

