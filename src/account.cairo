// Re-export for backward compatibility (tests import from sessions_smart_contract::account)
pub use crate::session_key::interface::{
    SessionData, ISessionKeyManager,
    ISessionKeyManagerDispatcher, ISessionKeyManagerDispatcherTrait,
};
pub use crate::session_key::spending_policy::interface::{
    SpendingPolicy, ISessionSpendingPolicy,
    ISessionSpendingPolicyDispatcher, ISessionSpendingPolicyDispatcherTrait,
};

#[starknet::contract(account)]
mod Account {
    use crate::session_key::interface::SessionData;
    use crate::session_key::interface::SESSION_KEY_MANAGER_ID;
    use crate::session_key::component::SessionKeyComponent;
    use crate::session_key::spending_policy::component::SpendingPolicyComponent;
    use crate::session_key::spending_policy::interface::SpendingPolicy;
    use openzeppelin_account::AccountComponent;
    // SRC9Component for SNIP-9 compatibility
    use openzeppelin_account::extensions::SRC9Component;
    use openzeppelin_interfaces::src9::{OutsideExecution, ISRC9_V2};
    use openzeppelin_account::extensions::src9::snip12_utils::OutsideExecutionStructHash;
    use openzeppelin_introspection::src5::SRC5Component;
    use openzeppelin_interfaces::upgrades::IUpgradeable;
    use openzeppelin_upgrades::UpgradeableComponent;
    use openzeppelin_utils::cryptography::snip12::{OffchainMessageHash, SNIP12Metadata};
    use starknet::ClassHash;
    use starknet::get_block_timestamp;
    use starknet::storage::{StorageMapReadAccess, StorageMapWriteAccess};
    use starknet::account::Call;
    use starknet::get_tx_info;
    use starknet::get_contract_address;
    use starknet::get_caller_address;
    use core::ecdsa::check_ecdsa_signature;
    use core::poseidon::poseidon_hash_span;
    use core::array::ArrayTrait;
    use core::array::SpanTrait;
    use core::traits::Into;
    use core::num::traits::Zero;

    // SNIP-12 type hashes for legacy paymaster fallback
    // Primary path uses OZ standard (u128 timestamps via SNIP-12 Rev 1).
    // Fallback path uses felt timestamps for older paymaster versions.
    // Computed via starknetKeccak(type_string)
    //
    // Fallback type hash for OutsideExecution (with felt timestamps):
    // starknetKeccak("OutsideExecution"("Caller":"ContractAddress","Nonce":"felt","Execute After":"felt","Execute Before":"felt","Calls":"Call*")"Call"(...))
    const OUTSIDE_EXECUTION_TYPE_HASH_REV1: felt252 =
        0x5a4b49e17039355cd95d1f0981d75901191d1319b1f4b05a9a791d218d7e0c;

    // Type hash for Call struct:
    // starknetKeccak("Call"("To":"ContractAddress","Selector":"selector","Calldata":"felt*"))
    const CALL_TYPE_HASH_REV1: felt252 =
        0x3635c7f2a7ba93844c0d064e18e487f35ab90f7c39d00f186a781fc3f0c2ca9;

    // Domain type hash for StarknetDomain:
    // starknetKeccak("StarknetDomain"("name":"shortstring","version":"shortstring","chainId":"shortstring","revision":"shortstring"))
    const STARKNET_DOMAIN_TYPE_HASH_REV1: felt252 =
        0x1ff2f602e42168014d405a94f75e8a93d640751d71d16311266e140d8b0a210;

    // SNIP-12 message prefix
    const STARKNET_MESSAGE_PREFIX: felt252 = 'StarkNet Message';

    component!(path: AccountComponent, storage: account, event: AccountEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: SRC9Component, storage: src9, event: SRC9Event);
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);
    component!(path: SessionKeyComponent, storage: session_key, event: SessionKeyEvent);
    component!(path: SpendingPolicyComponent, storage: spending_policy, event: SpendingPolicyEvent);

    #[abi(embed_v0)]
    impl PublicKeyImpl = AccountComponent::PublicKeyImpl<ContractState>;
    #[abi(embed_v0)]
    impl PublicKeyCamelImpl = AccountComponent::PublicKeyCamelImpl<ContractState>;
    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;
    impl AccountInternalImpl = AccountComponent::InternalImpl<ContractState>;
    impl SRC5InternalImpl = SRC5Component::InternalImpl<ContractState>;
    // DO NOT embed AccountComponent::SRC6Impl - we implement our own __validate__
    // DO NOT embed SRC9Component::SRC6Impl - we implement our own __validate__

    // Upgradeable
    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;

    // SRC9 (Outside Execution) - Custom implementation with session whitelist enforcement
    // NOTE: We do NOT embed SRC9Component::OutsideExecutionV2Impl because we need to
    // enforce session key whitelist and consume calls only AFTER signature validation
    impl SRC9InternalImpl = SRC9Component::InternalImpl<ContractState>;

    // Session Key component internal impl
    impl SessionKeyInternalImpl = SessionKeyComponent::InternalImpl<ContractState>;

    // Spending Policy component internal impl
    impl SpendingPolicyInternalImpl = SpendingPolicyComponent::InternalImpl<ContractState>;

    // Provide HasAccountOwner so the session key component can enforce owner-only access
    impl HasAccountOwnerImpl of SessionKeyComponent::HasAccountOwner<ContractState> {
        fn assert_only_self(self: @ContractState) {
            self.account.assert_only_self();
        }
    }

    // Provide HasAccountOwner so the spending policy component can enforce owner-only access
    impl SpendingPolicyHasAccountOwnerImpl of SpendingPolicyComponent::HasAccountOwner<ContractState> {
        fn assert_only_self(self: @ContractState) {
            self.account.assert_only_self();
        }
    }

    // SNIP-12 Metadata for Outside Execution message hashing (required for get_message_hash)
    impl SNIP12MetadataImpl of SNIP12Metadata {
        fn name() -> felt252 {
            'Account.execute_from_outside'
        }
        fn version() -> felt252 {
            2
        }
    }

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
        #[substorage(v0)]
        session_key: SessionKeyComponent::Storage,
        #[substorage(v0)]
        spending_policy: SpendingPolicyComponent::Storage,
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
        #[flat]
        SessionKeyEvent: SessionKeyComponent::Event,
        #[flat]
        SpendingPolicyEvent: SpendingPolicyComponent::Event,
    }

    #[constructor]
    fn constructor(ref self: ContractState, public_key: felt252) {
        self.account.initializer(public_key);   // registers ISRC6
        self.src9.initializer();                 // registers ISRC9_V2
        // Register custom session key manager interface (SRC-5)
        self.src5.register_interface(SESSION_KEY_MANAGER_ID);
    }


    // Manually implement SRC-6 interface with custom __validate__
    #[abi(per_item)]
    #[generate_trait]
    impl SRC6Impl of SRC6Trait {
        /// Validates a transaction before execution.
        ///
        /// Dual-path validation:
        /// - Empty signature (len=0): Accepts only self-calls (routed via __execute__)
        /// - Session signature (len=4): [session_pubkey, r, s, valid_until] -- validates
        ///   session existence, expiry, call limit, admin blocklist, self-call block,
        ///   whitelist, then ECDSA signature. Consumes a call only after validation.
        /// - Owner signature (len=2): [r, s] -- delegates to OZ AccountComponent
        ///
        /// Returns VALIDATED on success, 0 on failure. Never panics for invalid input.
        #[external(v0)]
        fn __validate__(ref self: ContractState, calls: Array<Call>) -> felt252 {
            let tx_info = get_tx_info().unbox();
            let signature = tx_info.signature;
            let caller = get_caller_address();

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

            // Session path: 4-element signature [session_pubkey, r, s, valid_until]
            // Works with both v1 (Paymaster) and v3 (standard) transactions
            if signature.len() == 4 {
                let session_pubkey = *signature.at(0);
                let r = *signature.at(1);
                let s = *signature.at(2);
                // SECURITY: Safe type conversion (audit fix #9)
                let valid_until: u64 = match (*signature.at(3)).try_into() {
                    Option::Some(v) => v,
                    Option::None => { return 0; }
                };

                // Check session expiration
                if get_block_timestamp() > valid_until {
                    return 0;
                }

                // SECURITY: Check session permissions (audit fix #2, #4)
                if !self.session_key.is_session_allowed_for_calls(session_pubkey, calls.span()) {
                    return 0;
                }

                // Compute message hash and verify signature
                let msg_hash = self.session_key.session_message_hash(calls.span(), valid_until);
                if check_ecdsa_signature(msg_hash, session_pubkey, r, s) {
                    self.session_key.consume_session_call(session_pubkey);
                    return starknet::VALIDATED;
                } else {
                    return 0;
                }
            }

            // Owner path: 2-element signature -> delegate to OZ
            if signature.len() == 2 {
                return self.account.validate_transaction();
            }

            // Invalid signature format
            0
        }

        /// Executes validated calls. Only callable by the sequencer (caller=0) or self.
        ///
        /// SECURITY: Caller restriction prevents external contracts from invoking
        /// __execute__ directly. Non-atomic: failed subcalls return empty spans
        /// without reverting the batch (by design -- see audit 1 finding #7).
        #[external(v0)]
        fn __execute__(ref self: ContractState, calls: Array<Call>) -> Array<Span<felt252>> {
            // Defense in depth: verify caller is either 0 (sequencer) or self
            let caller = get_caller_address();
            assert(
                caller.is_zero() || caller == get_contract_address(),
                'Account: unauthorized caller'
            );

            // Spending policy enforcement for session key transactions.
            // Must happen in __execute__ (not __validate__) because spending state
            // mutations in validate would be reverted on execution failure.
            let tx_info = get_tx_info().unbox();
            let signature = tx_info.signature;
            if signature.len() == 4 {
                let session_pubkey = *signature.at(0);
                self.spending_policy.check_and_update_spending(session_pubkey, calls.span());
            }

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

        /// Read-only signature validation (ERC-1271 / SRC-6).
        ///
        /// Validates both owner (2-element) and session (4-element) signatures.
        /// DOES NOT consume session calls or execute any calls -- purely read-only.
        /// Cannot enforce selector whitelists (no call context available).
        /// Audit 1 finding #5: accepted tradeoff for paymaster compatibility.
        fn is_valid_signature(
            self: @ContractState, hash: felt252, signature: Array<felt252>
        ) -> felt252 {
            // Owner path: 2-element signature [r, s]
            if signature.len() == 2 {
                let public_key = self.account.get_public_key();
                let is_valid = check_ecdsa_signature(
                    hash,
                    public_key,
                    *signature.at(0),
                    *signature.at(1)
                );

                if is_valid {
                    return starknet::VALIDATED;
                } else {
                    return 0;
                }
            }

            // Session path: 4-element signature [session_pubkey, r, s, valid_until]
            if signature.len() == 4 {
                let session_pubkey = *signature.at(0);
                let r = *signature.at(1);
                let s = *signature.at(2);
                // SECURITY: Safe type conversion (audit fix #9)
                let valid_until: u64 = match (*signature.at(3)).try_into() {
                    Option::Some(v) => v,
                    Option::None => { return 0; }  // Invalid timestamp format
                };

                // Check timestamp
                if get_block_timestamp() > valid_until {
                    return 0;
                }

                // Verify session key exists and is valid
                let session = self.session_key.session_keys.read(session_pubkey);
                if session.valid_until == 0 {
                    return 0;
                }
                if get_block_timestamp() > session.valid_until {
                    return 0;
                }
                if session.calls_used >= session.max_calls {
                    return 0;
                }

                // Verify ECDSA signature with session key
                let is_valid = check_ecdsa_signature(
                    hash,
                    session_pubkey,
                    r,
                    s
                );

                if is_valid {
                    return starknet::VALIDATED;
                } else {
                    return 0;
                }
            }

            // Invalid signature format
            0
        }
    }

    // Custom SNIP-9 v2 implementation with session whitelist enforcement
    // This replaces the embedded SRC9Component::OutsideExecutionV2Impl to add security checks
    #[abi(embed_v0)]
    impl CustomSRC9V2Impl of ISRC9_V2<ContractState> {
        /// Executes calls on behalf of the account via SNIP-9 outside execution.
        fn execute_from_outside_v2(
            ref self: ContractState,
            outside_execution: OutsideExecution,
            signature: Span<felt252>,
        ) -> Array<Span<felt252>> {
            // 1. Validate caller
            let caller_felt: felt252 = outside_execution.caller.into();
            let is_any_caller = caller_felt == 0 || caller_felt == 'ANY_CALLER';
            if !is_any_caller {
                assert(
                    get_caller_address() == outside_execution.caller,
                    'SRC9: invalid caller'
                );
            }

            // 2. Validate execution time span
            let now = get_block_timestamp();
            assert(outside_execution.execute_after < now, 'SRC9: now <= execute_after');
            assert(now < outside_execution.execute_before, 'SRC9: now >= execute_before');

            // 3. Validate and mark nonce as used
            assert(!self.src9.SRC9_nonces.read(outside_execution.nonce), 'SRC9: duplicated nonce');
            self.src9.SRC9_nonces.write(outside_execution.nonce, true);

            // 4. SECURITY: For session signatures, enforce whitelist BEFORE signature validation
            let mut is_session_sig = false;
            let mut session_pubkey: felt252 = 0;
            if signature.len() == 4 {
                is_session_sig = true;
                session_pubkey = *signature.at(0);

                // SECURITY (audit 3 fix #5): Bind valid_until to stored session value.
                let sig_valid_until: u64 = match (*signature.at(3)).try_into() {
                    Option::Some(v) => v,
                    Option::None => {
                        core::panic_with_felt252('Session: invalid timestamp')
                    }
                };
                let session = self.session_key.session_keys.read(session_pubkey);
                assert(sig_valid_until <= session.valid_until, 'Session: valid_until exceeded');

                assert(
                    self.session_key.is_session_allowed_for_calls(session_pubkey, outside_execution.calls),
                    'Session: unauthorized selector'
                );
            }

            // 5. Compute message hash and validate signature
            let mut sig_copy1: Array<felt252> = array![];
            let mut sig_copy2: Array<felt252> = array![];
            let mut i: u32 = 0;
            loop {
                if i >= signature.len() { break; }
                sig_copy1.append(*signature.at(i));
                sig_copy2.append(*signature.at(i));
                i += 1;
            };

            // Try OZ standard hash first (u128 timestamps)
            let oz_hash = outside_execution.get_message_hash(get_contract_address());
            let is_valid_oz = SRC6Impl::is_valid_signature(@self, oz_hash, sig_copy1);
            let mut is_valid_signature = is_valid_oz == starknet::VALIDATED || is_valid_oz == 1;

            // If OZ hash fails, try Chipi Pay format (felt timestamps)
            if !is_valid_signature {
                let felt_hash = self._compute_outside_execution_hash(@outside_execution);
                let is_valid_felt = SRC6Impl::is_valid_signature(@self, felt_hash, sig_copy2);
                is_valid_signature = is_valid_felt == starknet::VALIDATED || is_valid_felt == 1;
            }

            assert(is_valid_signature, 'SRC9: invalid signature');
            if is_session_sig {
                self.session_key.consume_session_call(session_pubkey);
            }

            // 6. Spending enforcement for session keys (mirrors __execute__ check)
            if is_session_sig {
                self.spending_policy.check_and_update_spending(session_pubkey, outside_execution.calls);
            }

            // 7. Execute the calls
            self._execute_calls(outside_execution.calls.into())
        }

        /// Returns the status of a given nonce. `true` if the nonce is available to use.
        fn is_valid_outside_execution_nonce(self: @ContractState, nonce: felt252) -> bool {
            !self.src9.SRC9_nonces.read(nonce)
        }
    }

    #[abi(embed_v0)]
    impl UpgradeableImpl of IUpgradeable<ContractState> {
        fn upgrade(ref self: ContractState, new_class_hash: ClassHash) {
            self.account.assert_only_self();
            self.upgradeable.upgrade(new_class_hash);
        }
    }

    /// Session key management -- owner-only access control via component.
    impl SessionKeyManagerImpl of super::ISessionKeyManager<ContractState> {
        fn add_or_update_session_key(
            ref self: ContractState,
            session_key: felt252,
            valid_until: u64,
            max_calls: u32,
            allowed_entrypoints: Array<felt252>
        ) {
            self.session_key.add_or_update_session_key(session_key, valid_until, max_calls, allowed_entrypoints);
        }

        fn revoke_session_key(ref self: ContractState, session_key: felt252) {
            self.session_key.revoke_session_key(session_key);
        }

        fn get_session_data(self: @ContractState, session_key: felt252) -> SessionData {
            self.session_key.get_session_data(session_key)
        }
    }

    /// Spending policy management -- owner-only access control via component.
    impl SpendingPolicyManagerImpl of super::ISessionSpendingPolicy<ContractState> {
        fn set_spending_policy(
            ref self: ContractState,
            session_key: felt252,
            token: starknet::ContractAddress,
            max_per_call: u256,
            max_per_window: u256,
            window_seconds: u64,
        ) {
            self.spending_policy.set_spending_policy(session_key, token, max_per_call, max_per_window, window_seconds);
        }

        fn get_spending_policy(
            self: @ContractState,
            session_key: felt252,
            token: starknet::ContractAddress,
        ) -> SpendingPolicy {
            self.spending_policy.get_spending_policy(session_key, token)
        }

        fn remove_spending_policy(
            ref self: ContractState,
            session_key: felt252,
            token: starknet::ContractAddress,
        ) {
            self.spending_policy.remove_spending_policy(session_key, token);
        }
    }

    #[external(v0)]
    fn set_spending_policy(
        ref self: ContractState,
        session_key: felt252,
        token: starknet::ContractAddress,
        max_per_call: u256,
        max_per_window: u256,
        window_seconds: u64,
    ) {
        SpendingPolicyManagerImpl::set_spending_policy(ref self, session_key, token, max_per_call, max_per_window, window_seconds);
    }

    #[external(v0)]
    fn get_spending_policy(
        self: @ContractState,
        session_key: felt252,
        token: starknet::ContractAddress,
    ) -> SpendingPolicy {
        SpendingPolicyManagerImpl::get_spending_policy(self, session_key, token)
    }

    #[external(v0)]
    fn remove_spending_policy(
        ref self: ContractState,
        session_key: felt252,
        token: starknet::ContractAddress,
    ) {
        SpendingPolicyManagerImpl::remove_spending_policy(ref self, session_key, token);
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

    /// One-time post-upgrade initializer: registers SRC-5 interface IDs.
    #[external(v0)]
    fn register_interfaces(ref self: ContractState) {
        self.account.assert_only_self();
        self.src5.register_interface(SESSION_KEY_MANAGER_ID);
    }

    #[external(v0)]
    fn get_contract_info(self: @ContractState) -> felt252 {
        'v33'
    }

    #[external(v0)]
    fn get_snip9_version(self: @ContractState) -> u8 {
        2
    }

    #[external(v0)]
    fn compute_session_message_hash(
        self: @ContractState,
        calls: Array<starknet::account::Call>,
        valid_until: u64
    ) -> felt252 {
        self.session_key.session_message_hash(calls.span(), valid_until)
    }

    #[external(v0)]
    fn is_valid_signature(
        self: @ContractState,
        hash: felt252,
        signature: Array<felt252>
    ) -> felt252 {
        SRC6Impl::is_valid_signature(self, hash, signature)
    }

    #[external(v0)]
    fn get_session_allowed_entrypoints_len(self: @ContractState, session_key: felt252) -> u32 {
        self.session_key.get_session_allowed_entrypoints_len(session_key)
    }

    #[external(v0)]
    fn get_session_allowed_entrypoint_at(
        self: @ContractState,
        session_key: felt252,
        index: u32
    ) -> felt252 {
        self.session_key.get_session_allowed_entrypoint_at(session_key, index)
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        /// Compute SNIP-12 message hash for OutsideExecution using felt timestamps (legacy fallback).
        fn _compute_outside_execution_hash(
            self: @ContractState,
            outside_execution: @OutsideExecution,
        ) -> felt252 {
            let chain_id = get_tx_info().unbox().chain_id;

            let domain_hash = poseidon_hash_span(
                array![
                    STARKNET_DOMAIN_TYPE_HASH_REV1,
                    'Account.execute_from_outside',
                    2,
                    chain_id,
                    1
                ].span()
            );

            let calls = *outside_execution.calls;
            let mut calls_hashes: Array<felt252> = array![];
            let mut i: u32 = 0;
            loop {
                if i >= calls.len() { break; }
                let call = calls.at(i);

                let calldata_hash = poseidon_hash_span(*call.calldata);

                let call_hash = poseidon_hash_span(
                    array![
                        CALL_TYPE_HASH_REV1,
                        (*call.to).into(),
                        *call.selector,
                        calldata_hash
                    ].span()
                );
                calls_hashes.append(call_hash);
                i += 1;
            };

            let calls_array_hash = poseidon_hash_span(calls_hashes.span());

            let struct_hash = poseidon_hash_span(
                array![
                    OUTSIDE_EXECUTION_TYPE_HASH_REV1,
                    (*outside_execution.caller).into(),
                    *outside_execution.nonce,
                    (*outside_execution.execute_after).into(),
                    (*outside_execution.execute_before).into(),
                    calls_array_hash
                ].span()
            );

            poseidon_hash_span(
                array![
                    STARKNET_MESSAGE_PREFIX,
                    domain_hash,
                    get_contract_address().into(),
                    struct_hash
                ].span()
            )
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
                            Result::Err(_) => res.append(array![].span()),
                        }
                    },
                    Option::None => { break; },
                }
            };

            res
        }
    }
}
