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
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::upgrades::interface::IUpgradeable;
    use openzeppelin::upgrades::UpgradeableComponent;
    use starknet::ClassHash;
    use starknet::get_block_timestamp;
    use starknet::storage::{Map, StorageMapReadAccess, StorageMapWriteAccess};
    use starknet::account::Call;
    use starknet::get_tx_info;
    use core::ecdsa::check_ecdsa_signature;
    use core::poseidon::poseidon_hash_span;
    use core::array::ArrayTrait;
    use core::array::SpanTrait;
    use core::traits::Into;

    component!(path: AccountComponent, storage: account, event: AccountEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);

    // Use AccountMixin WITHOUT __validate__ (we'll implement it manually)
    #[abi(embed_v0)]
    impl PublicKeyImpl = AccountComponent::PublicKeyImpl<ContractState>;
    #[abi(embed_v0)]
    impl PublicKeyCamelImpl = AccountComponent::PublicKeyCamelImpl<ContractState>;
    impl AccountInternalImpl = AccountComponent::InternalImpl<ContractState>;

    // Upgradeable
    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        account: AccountComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
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
        UpgradeableEvent: UpgradeableComponent::Event,
        SessionKeyAdded: SessionKeyAdded,
        SessionKeyRevoked: SessionKeyRevoked,
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

    #[constructor]
    fn constructor(ref self: ContractState, public_key: felt252) {
        self.account.initializer(public_key);
    }

    // Manually implement SRC-6 interface with custom __validate__
    #[abi(per_item)]
    #[generate_trait]
    impl SRC6Impl of SRC6Trait {
        #[external(v0)]
        fn __validate__(ref self: ContractState, calls: Array<Call>) -> felt252 {
            // Get signature from transaction
            let tx_info = get_tx_info().unbox();
            let signature = tx_info.signature;

            // Try owner signature first (standard 2-element signature: [r, s])
            if signature.len() == 2 {
                // This is an owner signature, validate using OZ account
                let public_key = self.account.get_public_key();
                let hash = self._calculate_transaction_hash(calls.span());
                
                let is_valid = check_ecdsa_signature(
                    hash,
                    public_key,
                    *signature.at(0),
                    *signature.at(1)
                );
                
                if is_valid {
                    return starknet::VALIDATED;
                }
                return 0;
            }

            // Try session signature (4-element: [session_pubkey, r, s, valid_until])
            if signature.len() == 4 {
                let session_pubkey = *signature.at(0);
                let r = *signature.at(1);
                let s = *signature.at(2);
                let valid_until: u64 = (*signature.at(3)).try_into().unwrap();

                // Check if valid_until hasn't expired
                if get_block_timestamp() > valid_until {
                    return 0; // Session expired
                }

                // Validate session for all calls (this will increment calls_used)
                if !self._validate_session_for_calls(session_pubkey, calls.span()) {
                    return 0; // Session validation failed
                }

                // Compute message hash
                let msg_hash = self._session_message_hash(calls.span(), valid_until);

                // Verify ECDSA signature
                let is_valid = check_ecdsa_signature(
                    msg_hash,
                    session_pubkey,
                    r,
                    s
                );

                if is_valid {
                    return starknet::VALIDATED;
                }
            }

            0 // Invalid signature
        }

        #[external(v0)]
        fn __execute__(ref self: ContractState, calls: Array<Call>) -> Array<Span<felt252>> {
            // Only the account itself can execute
            self.account.assert_only_self();
            self._execute_calls(calls)
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

    #[abi(embed_v0)]
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
            self.session_keys.read(session_key)
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _store_entrypoint(ref self: ContractState, session_key: felt252, index: u32, entrypoint: felt252) {
            self.session_entrypoints.write((session_key, index), entrypoint);
        }

        fn _load_entrypoint(self: @ContractState, session_key: felt252, index: u32) -> felt252 {
            self.session_entrypoints.read((session_key, index))
        }

        /// Validate session for multiple calls
        fn _validate_session_for_calls(
            ref self: ContractState,
            session_key: felt252,
            calls: Span<Call>
        ) -> bool {
            let mut session = self.session_keys.read(session_key);
            
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
            
            // Add transaction info
            hash_data.append(tx_info.transaction_hash);
            hash_data.append(tx_info.chain_id.into());
            hash_data.append(valid_until.into());
            
            // Hash each call
            let mut i = 0;
            loop {
                if i >= calls.len() {
                    break;
                }
                let call = calls.at(i);
                hash_data.append((*call.to).into());
                hash_data.append(*call.selector);
                
                // Hash calldata
                let mut j = 0;
                loop {
                    if j >= call.calldata.len() {
                        break;
                    }
                    hash_data.append(*call.calldata.at(j));
                    j += 1;
                };
                
                i += 1;
            };

            poseidon_hash_span(hash_data.span())
        }

        /// Calculate transaction hash for owner validation
        fn _calculate_transaction_hash(
            self: @ContractState,
            calls: Span<Call>
        ) -> felt252 {
            let tx_info = get_tx_info().unbox();
            let mut hash_data = array![];
            
            hash_data.append(tx_info.transaction_hash);
            hash_data.append(tx_info.chain_id.into());
            
            let mut i = 0;
            loop {
                if i >= calls.len() {
                    break;
                }
                let call = calls.at(i);
                hash_data.append((*call.to).into());
                hash_data.append(*call.selector);
                
                let mut j = 0;
                loop {
                    if j >= call.calldata.len() {
                        break;
                    }
                    hash_data.append(*call.calldata.at(j));
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
