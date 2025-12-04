// Test suite for hash computation functions
// Verifies SNIP-12 type hashing implementation

#[cfg(test)]
mod test_hash_computation {
    use starknet::ContractAddress;
    use starknet::account::Call;
    use snforge_std_deprecated::{
        declare, ContractClassTrait, DeclareResultTrait,
        start_cheat_block_timestamp_global, start_cheat_chain_id_global
    };
    
    use sessions_smart_contract::outside_execution::{
        OutsideExecution, IOutsideExecutionDispatcher, IOutsideExecutionDispatcherTrait,
        STARKNET_DOMAIN_TYPE_HASH, CALL_TYPE_HASH, OUTSIDE_EXECUTION_TYPE_HASH
    };

    // Test interface for hash computation
    #[starknet::interface]
    trait IHashComputation<TContractState> {
        fn compute_session_message_hash(
            self: @TContractState,
            calls: Array<Call>,
            valid_until: u64
        ) -> felt252;
        fn get_outside_execution_message_hash_rev_1(
            self: @TContractState,
            outside_execution: OutsideExecution,
        ) -> felt252;
    }

    fn deploy_account() -> ContractAddress {
        let account_class = declare("Account").unwrap().contract_class();
        let owner_pubkey: felt252 = 0x123456789abcdef;
        let mut calldata = array![owner_pubkey];
        let (contract_address, _) = account_class.deploy(@calldata).unwrap();
        contract_address
    }

    // Helper to create contract address
    fn addr(val: felt252) -> ContractAddress {
        val.try_into().unwrap()
    }

    // ========== TYPE HASH VERIFICATION ==========

    #[test]
    fn test_starknet_domain_type_hash_is_correct() {
        // SNIP-12 Rev 1 StarknetDomain type hash
        let expected: felt252 = 0x1ff2f602e42168014d405a94f75e8a93d640751d71d16311266e140d8b0a210;
        assert(STARKNET_DOMAIN_TYPE_HASH == expected, 'Wrong domain type hash');
    }

    #[test]
    fn test_call_type_hash_is_correct() {
        // SNIP-12 Rev 1 Call type hash
        let expected: felt252 = 0x3635c7f2a7ba93844c0d064e18e487f35ab90f7c39d00f186a781fc3f0c2ca9;
        assert(CALL_TYPE_HASH == expected, 'Wrong call type hash');
    }

    #[test]
    fn test_outside_execution_type_hash_is_correct() {
        // SNIP-12 Rev 1 OutsideExecution type hash
        let expected: felt252 = 0x5a4b49e17039355cd95d1f0981d75901191d1319b1f4b05a9a791d218d7e0c;
        assert(OUTSIDE_EXECUTION_TYPE_HASH == expected, 'Wrong OE type hash');
    }

    // ========== OUTSIDE EXECUTION MESSAGE HASH ==========

    #[test]
    fn test_outside_execution_hash_deterministic() {
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
                calldata: array![0x111].span()
            }
        ];
        let calls2 = array![
            Call {
                to: target,
                selector: 0xabcdef,
                calldata: array![0x111].span()
            }
        ];
        
        let oe1 = OutsideExecution {
            caller: caller,
            nonce: 100,
            execute_after: current_time,
            execute_before: current_time + 3600,
            calls: calls1.span(),
        };
        let oe2 = OutsideExecution {
            caller: caller,
            nonce: 100,
            execute_after: current_time,
            execute_before: current_time + 3600,
            calls: calls2.span(),
        };
        
        let hash1 = dispatcher.get_outside_execution_message_hash_rev_1(oe1);
        let hash2 = dispatcher.get_outside_execution_message_hash_rev_1(oe2);
        
        assert(hash1 == hash2, 'OE hashes should match');
        assert(hash1 != 0, 'OE hash nonzero');
    }

    #[test]
    fn test_outside_execution_hash_changes_with_nonce() {
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
                selector: 0xabcdef,
                calldata: array![].span()
            }
        ];
        
        let oe1 = OutsideExecution {
            caller: caller,
            nonce: 1,
            execute_after: current_time,
            execute_before: current_time + 3600,
            calls: calls.span(),
        };
        
        let calls2 = array![
            Call {
                to: target,
                selector: 0xabcdef,
                calldata: array![].span()
            }
        ];
        
        let oe2 = OutsideExecution {
            caller: caller,
            nonce: 2,
            execute_after: current_time,
            execute_before: current_time + 3600,
            calls: calls2.span(),
        };
        
        let hash1 = dispatcher.get_outside_execution_message_hash_rev_1(oe1);
        let hash2 = dispatcher.get_outside_execution_message_hash_rev_1(oe2);
        
        assert(hash1 != hash2, 'Diff nonce diff hash');
    }

    #[test]
    fn test_outside_execution_hash_changes_with_caller() {
        let account = deploy_account();
        let current_time = 1000000_u64;
        
        start_cheat_block_timestamp_global(current_time);
        start_cheat_chain_id_global('SN_MAIN');
        
        let dispatcher = IOutsideExecutionDispatcher { contract_address: account };
        
        let target: ContractAddress = addr(0x1234);
        let caller1: ContractAddress = addr(0x1111);
        let caller2: ContractAddress = addr(0x2222);
        
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
        
        let oe1 = OutsideExecution {
            caller: caller1,
            nonce: 1,
            execute_after: current_time,
            execute_before: current_time + 3600,
            calls: calls1.span(),
        };
        let oe2 = OutsideExecution {
            caller: caller2,
            nonce: 1,
            execute_after: current_time,
            execute_before: current_time + 3600,
            calls: calls2.span(),
        };
        
        let hash1 = dispatcher.get_outside_execution_message_hash_rev_1(oe1);
        let hash2 = dispatcher.get_outside_execution_message_hash_rev_1(oe2);
        
        assert(hash1 != hash2, 'Diff caller diff hash');
    }

    #[test]
    fn test_outside_execution_nonce_validity() {
        let account = deploy_account();
        let dispatcher = IOutsideExecutionDispatcher { contract_address: account };
        
        // Fresh nonces should be valid
        assert(dispatcher.is_valid_outside_execution_nonce(1), 'Nonce 1 valid');
        assert(dispatcher.is_valid_outside_execution_nonce(999), 'Nonce 999 valid');
        assert(dispatcher.is_valid_outside_execution_nonce(0), 'Nonce 0 valid');
    }
}

