#[starknet::contract(account)]
mod Account {
    use openzeppelin::account::AccountComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::upgrades::interface::IUpgradeable;
    use openzeppelin::upgrades::UpgradeableComponent;
    use starknet::ClassHash;
    use starknet::get_block_timestamp;
    use starknet::storage::{Map, StorageMapReadAccess, StorageMapWriteAccess};
    use core::array::ArrayTrait;

    component!(path: AccountComponent, storage: account, event: AccountEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);

    // Account Mixin
    #[abi(embed_v0)]
    impl AccountMixinImpl = AccountComponent::AccountMixinImpl<ContractState>;
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

    #[derive(Drop, Copy, Serde, starknet::Store)]
    struct SessionData {
        valid_until: u64,
        max_calls: u32,
        calls_used: u32,
        allowed_entrypoints_len: u32,
    }

    #[constructor]
    fn constructor(ref self: ContractState, public_key: felt252) {
        self.account.initializer(public_key);
    }

    #[abi(embed_v0)]
    impl UpgradeableImpl of IUpgradeable<ContractState> {
        fn upgrade(ref self: ContractState, new_class_hash: ClassHash) {
            self.account.assert_only_self();
            self.upgradeable.upgrade(new_class_hash);
        }
    }

    /// Session Key Management Interface
    #[starknet::interface]
    trait ISessionKeyManager<TContractState> {
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

    #[abi(embed_v0)]
    impl SessionKeyManagerImpl of ISessionKeyManager<ContractState> {
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

        fn _validate_session(
            ref self: ContractState,
            session_key: felt252,
            entrypoint_selector: felt252
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

            // Check if entrypoint is allowed
            let mut i = 0;
            let mut found = false;
            loop {
                if i >= session.allowed_entrypoints_len {
                    break;
                }
                let allowed = self._load_entrypoint(session_key, i);
                if allowed == entrypoint_selector {
                    found = true;
                    break;
                }
                i += 1;
            };

            if !found {
                return false;
            }

            // Increment calls used
            session.calls_used += 1;
            self.session_keys.write(session_key, session);
            return true;
        }
    }
}

