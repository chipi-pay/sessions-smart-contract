// Session Data struct - exposed for tests
#[derive(Drop, Copy, Serde, starknet::Store)]
pub struct SessionData {
    pub valid_until: u64,
    pub max_calls: u32,
    pub calls_used: u32,
    pub allowed_entrypoints_len: u32,
}

// Session Key Management Interface - exposed for tests
#[starknet::interface]
pub trait ISessionKeyManager<TContractState> {
    fn add_or_update_session_key(
        ref self: TContractState,
        session_key: felt252,
        valid_until: u64,
        max_calls: u32,
        allowed_entrypoints: Array<felt252>
    );
    fn revoke_session_key(ref self: TContractState, session_key: felt252);
    fn get_session_data(self: @TContractState, session_key: felt252) -> SessionData;
}

#[starknet::contract(account)]
mod Account {
    use super::SessionData;
    use openzeppelin::account::AccountComponent;
    // SRC9Component for SNIP-9 compatibility
    use openzeppelin::account::extensions::SRC9Component;
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::upgrades::interface::IUpgradeable;
    use openzeppelin::upgrades::UpgradeableComponent;
    use starknet::ClassHash;
    use starknet::get_block_timestamp;
    use starknet::storage::{Map, StorageMapReadAccess, StorageMapWriteAccess};
    use starknet::account::Call;
    use starknet::get_tx_info;
    use starknet::get_contract_address;
    use starknet::get_caller_address;
    use core::ecdsa::check_ecdsa_signature;
    use core::poseidon::poseidon_hash_span;
    use core::array::ArrayTrait;
    use core::array::SpanTrait;
    use core::traits::Into;

    component!(path: AccountComponent, storage: account, event: AccountEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: SRC9Component, storage: src9, event: SRC9Event);
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);

    #[abi(embed_v0)]
    impl PublicKeyImpl = AccountComponent::PublicKeyImpl<ContractState>;
    #[abi(embed_v0)]
    impl PublicKeyCamelImpl = AccountComponent::PublicKeyCamelImpl<ContractState>;
    impl AccountInternalImpl = AccountComponent::InternalImpl<ContractState>;
    // DO NOT embed AccountComponent::SRC6Impl - we implement our own __validate__
// DO NOT embed SRC9Component::SRC6Impl - we implement our own __validate__

    // Upgradeable
    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;

    // SRC9 (Outside Execution) - Embed ONLY the OutsideExecutionV2 implementation
    // NOTE: We do NOT embed the SRC9Component's __validate__ implementation
    // because we have our own custom __validate__ that handles both owner and session signatures
    #[abi(embed_v0)]
    impl OutsideExecutionV2Impl = SRC9Component::OutsideExecutionV2Impl<ContractState>;
    impl SRC9InternalImpl = SRC9Component::InternalImpl<ContractState>;
    
    // CRITICAL: We do NOT embed SRC9Component::SRC6Impl because it would override our custom __validate__
    // We only use the SRC9Component for outside execution functionality, not validation

    #[storage]
    struct Storage {
        #[substorage(v0)]
        account: AccountComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        src9: SRC9Component::Storage,
        #[substorage(v0)]
        upgradeable: UpgradeableComponent::Storage,
        session_keys: Map<felt252, SessionData>,
        session_entrypoints: Map<(felt252, u32), felt252>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        AccountEvent: AccountComponent::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        #[flat]
        SRC9Event: SRC9Component::Event,
        #[flat]
        UpgradeableEvent: UpgradeableComponent::Event,
        SessionKeyAdded: SessionKeyAdded,
        SessionKeyRevoked: SessionKeyRevoked,
        DebugEvent: DebugEvent,
    }

    #[derive(Drop, starknet::Event)]
    struct SessionKeyAdded {
        #[key]
        session_key: felt252,
        valid_until: u64,
        max_calls: u32,
    }

    #[derive(Drop, starknet::Event)]
    struct SessionKeyRevoked {
        #[key]
        session_key: felt252,
    }

    #[derive(Drop, starknet::Event)]
    struct DebugEvent {
        #[key]
        message: felt252,
    }

    #[constructor]
    fn constructor(ref self: ContractState, public_key: felt252) {
            self.account.initializer(public_key);
        self.src9.initializer();
    }


    // Manually implement SRC-6 interface with custom __validate__
    #[abi(per_item)]
    #[generate_trait]
    impl SRC6Impl of SRC6Trait {
        #[external(v0)]
        fn __validate__(ref self: ContractState, calls: Array<Call>) -> felt252 {
            let tx_info = get_tx_info().unbox();
            let signature = tx_info.signature;
            let caller = get_caller_address();
            let version = tx_info.version;

            // Debug: Emit signature length and version
            self.emit(DebugEvent { message: 'sig_len' });
            self.emit(DebugEvent { message: signature.len().into() });
            self.emit(DebugEvent { message: 'version' });
            self.emit(DebugEvent { message: version });

            // For version 1 transactions (Paymaster/SNIP-9), always delegate to AccountComponent
            // This ensures Paymaster compatibility
            if version == 1 {
                self.emit(DebugEvent { message: 'v1_paymaster_path' });
                return self.account.validate_transaction();
            }

            // Self-calls routed via __execute__ carry no tx signature
            // SECURITY: Only allow empty signatures if caller is the account itself
            if signature.len() == 0 {
                if caller == get_contract_address() {
                    return starknet::VALIDATED;
                } else {
                    // Reject empty signatures from external callers
                    return 0;
                }
            }

            // Owner path: 2-elt signature → delegate to OZ (handles tx v1 and v3 hashing)
            if signature.len() == 2 {
                self.emit(DebugEvent { message: 'owner_path' });
                // Use AccountComponent's validate function for owner signatures
                // This should handle both v1 (Paymaster) and v3 (standard) transactions
                return self.account.validate_transaction();
            }

            // Session path: 4-elt signature [session_pubkey, r, s, valid_until]
            // Works with both v1 (Paymaster) and v3 (standard) transactions
            if signature.len() == 4 {
                self.emit(DebugEvent { message: 'session_path' });
                let session_pubkey = *signature.at(0);
                let r = *signature.at(1);
                let s = *signature.at(2);
                let valid_until: u64 = (*signature.at(3)).try_into().unwrap();

                // Debug: Check timestamp
                if get_block_timestamp() > valid_until {
                    // Debug: Emit event for timestamp failure
                    self.emit(DebugEvent { message: 'timestamp_failed' });
                    return 0;
                }
                
                // Debug: Check session permissions
                if !self._is_session_allowed_for_calls(session_pubkey, calls.span()) {
                    // Debug: Emit event for permission failure
                    self.emit(DebugEvent { message: 'permission_failed' });
                    return 0;
                }

                // Match the front-end's poseidon message layout
                let msg_hash = self._session_message_hash(calls.span(), valid_until);
                
                // Debug: Check signature
                if check_ecdsa_signature(msg_hash, session_pubkey, r, s) {
                    // Only increment counter after valid signature
                    self._consume_session_call(session_pubkey);
                    // Debug: Emit event for success
                    self.emit(DebugEvent { message: 'signature_valid' });
                    return starknet::VALIDATED;
                } else {
                    // Debug: Emit event for signature failure
                    self.emit(DebugEvent { message: 'signature_failed' });
                    return 0;
                }
            }

            // If we reach here, validation failed
            self.emit(DebugEvent { message: 'validation_failed' });
            0
        }

        #[external(v0)]
        fn __execute__(ref self: ContractState, calls: Array<Call>) -> Array<Span<felt252>> {
            // Validation happens in __validate__, not here
            self._execute_calls(calls)
        }

        #[external(v0)]
        fn __validate_deploy__(
            self: @ContractState,
            class_hash: felt252,
            contract_address_salt: felt252,
            public_key: felt252
        ) -> felt252 {
            // Delegate to OpenZeppelin's component for proper V3 deploy validation
            self.account.validate_transaction()
        }

        #[external(v0)]
        fn __validate_declare__(self: @ContractState, class_hash: felt252) -> felt252 {
            // Delegate to OpenZeppelin's component for proper V3 declare validation
            self.account.validate_transaction()
        }

        fn is_valid_signature(
            self: @ContractState, hash: felt252, signature: Array<felt252>
        ) -> felt252 {
            if signature.len() != 2 {
                return 0;
            }
            
            let public_key = self.account.get_public_key();
            let is_valid = check_ecdsa_signature(
                hash,
                public_key,
                *signature.at(0),
                *signature.at(1)
            );
            
            if is_valid {
                starknet::VALIDATED
            } else {
                0
            }
        }
    }

    #[abi(embed_v0)]
    impl UpgradeableImpl of IUpgradeable<ContractState> {
        fn upgrade(ref self: ContractState, new_class_hash: ClassHash) {
            self.account.assert_only_self();
            self.upgradeable.upgrade(new_class_hash);
        }
    }

    // Session key management with external entry points - v13
    impl SessionKeyManagerImpl of super::ISessionKeyManager<ContractState> {
        fn add_or_update_session_key(
            ref self: ContractState,
            session_key: felt252,
            valid_until: u64,
            max_calls: u32,
            allowed_entrypoints: Array<felt252>
        ) {
            self.account.assert_only_self();
            
            let sess = SessionData {
                valid_until,
                max_calls,
                calls_used: 0,
                allowed_entrypoints_len: allowed_entrypoints.len(),
            };
            self.session_keys.write(session_key, sess);
            
            // Store allowed entrypoints separately
            let mut i = 0;
            loop {
                if i >= allowed_entrypoints.len() {
                    break;
                }
                self._store_entrypoint(session_key, i, *allowed_entrypoints.at(i));
                i += 1;
            };

            self.emit(SessionKeyAdded { session_key, valid_until, max_calls });
        }

        fn revoke_session_key(ref self: ContractState, session_key: felt252) {
            self.account.assert_only_self();
            
            // Get the current session data to know how many entrypoints to clear
            let current_session = self.session_keys.read(session_key);
            let entrypoints_to_clear = current_session.allowed_entrypoints_len;
            
            // Clear all stored entrypoints for this session key
            let mut i = 0;
            loop {
                if i >= entrypoints_to_clear {
                    break;
                }
                // Clear the entrypoint by writing 0 (default value)
                self.session_entrypoints.write((session_key, i), 0);
                i += 1;
            };
            
            let sess = SessionData {
                valid_until: 0,
                max_calls: 0,
                calls_used: 0,
                allowed_entrypoints_len: 0,
            };
            self.session_keys.write(session_key, sess);

            self.emit(SessionKeyRevoked { session_key });
        }

        fn get_session_data(self: @ContractState, session_key: felt252) -> SessionData {
            // Return session data for the given key
            self.session_keys.read(session_key)
        }
    }

    // External entry points for session management
    #[external(v0)]
    fn add_or_update_session_key(
        ref self: ContractState,
        session_key: felt252,
        valid_until: u64,
        max_calls: u32,
        allowed_entrypoints: Array<felt252>
    ) {
        SessionKeyManagerImpl::add_or_update_session_key(ref self, session_key, valid_until, max_calls, allowed_entrypoints);
    }

    #[external(v0)]
    fn revoke_session_key(ref self: ContractState, session_key: felt252) {
        SessionKeyManagerImpl::revoke_session_key(ref self, session_key);
    }

    #[external(v0)]
    fn get_session_data(self: @ContractState, session_key: felt252) -> SessionData {
        SessionKeyManagerImpl::get_session_data(self, session_key)
    }

    // Production-safe functions (no security vulnerabilities)
    #[external(v0)]
    fn get_contract_info(self: @ContractState) -> felt252 {
        // Return a version identifier for production with SNIP-9 support
        'v23_snip9_compatible'
    }

    // SNIP-9 version check - returns 2 for SNIP-9 v2 compatibility
    #[external(v0)]
    fn get_snip9_version(self: @ContractState) -> u8 {
        // This account is compatible with SNIP-9 v2 (Outside Execution)
        2
    }

    // Safe debugging: uses real tx_info (no forced parameters)
    #[external(v0)]
    fn compute_session_message_hash(
        self: @ContractState,
        calls: Array<starknet::account::Call>,
        valid_until: u64
    ) -> felt252 {
        self._session_message_hash(calls.span(), valid_until)
    }

    // ERC-1271 compatible signature validation
    #[external(v0)]
    fn is_valid_signature(
        self: @ContractState, 
        hash: felt252, 
        signature: Array<felt252>
    ) -> felt252 {
        if signature.len() != 2 { return 0; }
        let public_key = self.account.get_public_key();
        let ok = check_ecdsa_signature(hash, public_key, *signature.at(0), *signature.at(1));
        if ok { starknet::VALIDATED } else { 0 }
    }

    // Read-only session entrypoint helpers (safe)
    #[external(v0)]
    fn get_session_allowed_entrypoints_len(self: @ContractState, session_key: felt252) -> u32 {
        let s = self.session_keys.read(session_key);
        s.allowed_entrypoints_len
    }

    #[external(v0)]
    fn get_session_allowed_entrypoint_at(
        self: @ContractState, 
        session_key: felt252, 
        index: u32
    ) -> felt252 {
        self._load_entrypoint(session_key, index)
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _store_entrypoint(ref self: ContractState, session_key: felt252, index: u32, entrypoint: felt252) {
            self.session_entrypoints.write((session_key, index), entrypoint);
        }

        fn _load_entrypoint(self: @ContractState, session_key: felt252, index: u32) -> felt252 {
            self.session_entrypoints.read((session_key, index))
        }

        // NEW: Pure session validation check (no mutations)
        fn _is_session_allowed_for_calls(
            self: @ContractState,
            session_key: felt252,
            calls: Span<Call>
        ) -> bool {
            let session = self.session_keys.read(session_key);
            if session.valid_until == 0 { return false; }
            if get_block_timestamp() > session.valid_until { return false; }
            if session.calls_used >= session.max_calls { return false; }

            if session.allowed_entrypoints_len == 0 { return true; }

            let mut i = 0;
            loop {
                if i >= calls.len() { break; }
                let call = calls.at(i);
                let selector = *call.selector;

                let mut j = 0;
                let mut found = false;
                loop {
                    if j >= session.allowed_entrypoints_len { break; }
                    let allowed = self._load_entrypoint(session_key, j);
                    if allowed == selector { found = true; break; }
                    j += 1;
                };
                if !found { return false; }
                i += 1;
            };
            true
        }

        // NEW: Consume session call (increment counter only)
        fn _consume_session_call(ref self: ContractState, session_key: felt252) {
            let mut session = self.session_keys.read(session_key);
            session.calls_used += 1;
            self.session_keys.write(session_key, session);
        }

        /// Validate session for multiple calls
        fn _validate_session_for_calls(
            ref self: ContractState,
            session_key: felt252,
            calls: Span<Call>
        ) -> bool {
            let mut session = self.session_keys.read(session_key);
            
            // Check if session exists (valid_until > 0 means session was added)
            if session.valid_until == 0 {
                return false;
            }
            
            // Check if session is expired
            if get_block_timestamp() > session.valid_until {
                return false;
            }
            
            // Check if max calls exceeded
            if session.calls_used >= session.max_calls {
                return false;
            }

            // If no entrypoints specified, allow all
            if session.allowed_entrypoints_len == 0 {
                session.calls_used += 1;
                self.session_keys.write(session_key, session);
                return true;
            }

            // Check if all call selectors are allowed
            let mut i = 0;
            loop {
                if i >= calls.len() {
                    break;
                }
                let call = calls.at(i);
                let selector = *call.selector;
                
                // Check if this selector is in the allowed list
                let mut j = 0;
                let mut found = false;
                loop {
                    if j >= session.allowed_entrypoints_len {
                        break;
                    }
                    let allowed = self._load_entrypoint(session_key, j);
                    if allowed == selector {
                        found = true;
                        break;
                    }
                    j += 1;
                };

                if !found {
                    return false;
                }
                
                i += 1;
            };

            // All selectors are allowed, increment calls used
            session.calls_used += 1;
            self.session_keys.write(session_key, session);
            true
        }

        /// Compute message hash for session signature
        fn _session_message_hash(
            self: @ContractState,
            calls: Span<Call>,
            valid_until: u64
        ) -> felt252 {
            let tx_info = get_tx_info().unbox();
            let mut hash_data = array![];
            
            // Add base transaction info (matching frontend order)
            hash_data.append(get_contract_address().into());    // ozAddr (contract address)
            hash_data.append(tx_info.chain_id.into());          // chain ID
            hash_data.append(tx_info.nonce.into());             // nonce
            hash_data.append(valid_until.into());               // valid until timestamp
            
            // Hash each call (matching frontend structure)
            let mut i = 0;
            loop {
                if i >= calls.len() {
                    break;
                }
                let call = calls.at(i);
                
                // Add call info (matching frontend order)
                hash_data.append((*call.to).into());            // target contract address
                hash_data.append((*call.selector).into());      // function selector
                hash_data.append(call.calldata.len().into());   // calldata length
                
                // Add calldata elements
                let mut j = 0;
                loop {
                    if j >= call.calldata.len() {
                        break;
                    }
                    hash_data.append((*call.calldata.at(j)).into());
                    j += 1;
                };
                
                i += 1;
            };

            poseidon_hash_span(hash_data.span())
        }

        /// Execute calls and return results
        fn _execute_calls(ref self: ContractState, mut calls: Array<Call>) -> Array<Span<felt252>> {
            let mut res = array![];
            
            loop {
                match calls.pop_front() {
                    Option::Some(call) => {
                        match starknet::syscalls::call_contract_syscall(
                            call.to, call.selector, call.calldata
                        ) {
                            Result::Ok(ret) => res.append(ret),
                            Result::Err(_) => {
                                let mut err = array![];
                                res.append(err.span());
                            }
                        }
                    },
                    Option::None => { break; },
                }
            };
            
            res
        }
    }
}
