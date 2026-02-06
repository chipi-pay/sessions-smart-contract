#[cfg(test)]
mod test_snip9_compatibility {
    use starknet::ContractAddress;
    use snforge_std_deprecated::{declare, ContractClassTrait, DeclareResultTrait};
    use sessions_smart_contract::account::{
        SessionData, ISessionKeyManagerDispatcher, ISessionKeyManagerDispatcherTrait
    };
    
    // Test interface for SNIP-9 version check
    #[starknet::interface]
    trait ISNIP9Version<TContractState> {
        fn get_snip9_version(self: @TContractState) -> u8;
        fn get_contract_info(self: @TContractState) -> felt252;
    }

    fn deploy_account() -> ContractAddress {
        let account_class = declare("Account").unwrap().contract_class();
        let owner_pubkey: felt252 = 0x123456789;
        let mut calldata = array![owner_pubkey];
        let (contract_address, _) = account_class.deploy(@calldata).unwrap();
        contract_address
    }

    #[test]
    fn test_snip9_version_returns_v2() {
        // Deploy account
        let account_address = deploy_account();
        
        // Create SNIP9 version dispatcher
        let snip9_dispatcher = ISNIP9VersionDispatcher { contract_address: account_address };
        
        // Check SNIP-9 version
        let version = snip9_dispatcher.get_snip9_version();
        
        // Should return 2 (SNIP-9 v2 compatible)
        assert(version == 2, 'Should be SNIP-9 v2');
    }

    #[test]
    fn test_contract_info_shows_snip9_compatible() {
        // Deploy account
        let account_address = deploy_account();

        // Create SNIP9 version dispatcher
        let snip9_dispatcher = ISNIP9VersionDispatcher { contract_address: account_address };

        // Check contract info
        let info = snip9_dispatcher.get_contract_info();

        // Should indicate audit fixes version
        assert(info == 'v26_audit_fixes', 'Wrong version string');
    }

    #[test]
    fn test_session_keys_still_work_with_snip9() {
        // Verify that session keys work normally with SNIP-9 added
        let account_address = deploy_account();
        let session_manager = ISessionKeyManagerDispatcher { contract_address: account_address };
        
        // Try to get session data (should work even though SNIP-9 is added)
        let session_key: felt252 = 0xABCDEF;
        let data = session_manager.get_session_data(session_key);
        
        // Should return empty/default data (session doesn't exist yet)
        assert(data.valid_until == 0, 'Should be empty');
        assert(data.max_calls == 0, 'Should be zero calls');
    }
}

