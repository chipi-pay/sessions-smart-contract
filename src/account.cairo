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
    use openzeppelin::account::extensions::src9::{OutsideExecution, ISRC9_V2};
    use openzeppelin::account::extensions::src9::snip12_utils::OutsideExecutionStructHash;
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::upgrades::interface::IUpgradeable;
    use openzeppelin::upgrades::UpgradeableComponent;
    use openzeppelin::utils::cryptography::snip12::{OffchainMessageHash, SNIP12Metadata};
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

    #[abi(embed_v0)]
    impl PublicKeyImpl = AccountComponent::PublicKeyImpl<ContractState>;
    #[abi(embed_v0)]
    impl PublicKeyCamelImpl = AccountComponent::PublicKeyCamelImpl<ContractState>;
    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;
    impl AccountInternalImpl = AccountComponent::InternalImpl<ContractState>;
    // DO NOT embed AccountComponent::SRC6Impl - we implement our own __validate__
// DO NOT embed SRC9Component::SRC6Impl - we implement our own __validate__

    // Upgradeable
    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;

    // SRC9 (Outside Execution) - Custom implementation with session whitelist enforcement
    // NOTE: We do NOT embed SRC9Component::OutsideExecutionV2Impl because we need to
    // enforce session key whitelist and consume calls only AFTER signature validation
    impl SRC9InternalImpl = SRC9Component::InternalImpl<ContractState>;

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
                if !self._is_session_allowed_for_calls(session_pubkey, calls.span()) {
                    return 0;
                }

                // Compute message hash and verify signature
                let msg_hash = self._session_message_hash(calls.span(), valid_until);
                if check_ecdsa_signature(msg_hash, session_pubkey, r, s) {
                    self._consume_session_call(session_pubkey);
                    return starknet::VALIDATED;
                } else {
                    return 0;
                }
            }

            // Owner path: 2-element signature → delegate to OZ
            if signature.len() == 2 {
                return self.account.validate_transaction();
            }

            // Invalid signature format
            0
        }

        #[external(v0)]
        fn __execute__(ref self: ContractState, calls: Array<Call>) -> Array<Span<felt252>> {
            // Defense in depth: verify caller is either 0 (sequencer) or self
            let caller = get_caller_address();
            assert(
                caller.is_zero() || caller == get_contract_address(),
                'Account: unauthorized caller'
            );

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
            // Note: For SNIP-9 outside execution, the hash is already computed by SRC9Component
            // We just need to verify the session key signature
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
                let session = self.session_keys.read(session_pubkey);
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
        /// Allows anyone to submit a transaction on behalf of the account as long as they
        /// provide the relevant signatures.
        ///
        /// SECURITY: For session signatures, this enforces the whitelist BEFORE signature validation.
        /// This prevents session keys from executing unauthorized selectors via SNIP-9/Paymaster flow.
        fn execute_from_outside_v2(
            ref self: ContractState,
            outside_execution: OutsideExecution,
            signature: Span<felt252>,
        ) -> Array<Span<felt252>> {
            // 1. Validate caller (0 or 'ANY_CALLER' means any caller is allowed - SNIP-9 standard)
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
            // This is the key fix for audit findings #2, #4
            let mut is_session_sig = false;
            let mut session_pubkey: felt252 = 0;
            if signature.len() == 4 {
                is_session_sig = true;
                session_pubkey = *signature.at(0);
                assert(
                    self._is_session_allowed_for_calls(session_pubkey, outside_execution.calls),
                    'Session: unauthorized selector'
                );
            }

            // 5. Compute message hash and validate signature
            // We support TWO hash formats for compatibility:
            // - OZ/Standard format: uses 'u128' for timestamps
            // - Chipi Pay format: uses 'felt' for timestamps

            // Convert signature span to arrays (need two copies for trying both hashes)
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
                self._consume_session_call(session_pubkey);
            }

            // 6. Execute the calls
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

    // Session key management with external entry points - v26 (audit fixes)
    impl SessionKeyManagerImpl of super::ISessionKeyManager<ContractState> {
        fn add_or_update_session_key(
            ref self: ContractState,
            session_key: felt252,
            valid_until: u64,
            max_calls: u32,
            allowed_entrypoints: Array<felt252>
        ) {
            self.account.assert_only_self();

            // SECURITY: Clear stale entrypoints first (audit fix #10)
            // When updating a session from N entrypoints to M < N, clear indices M to N-1
            let old_session = self.session_keys.read(session_key);
            let mut i = 0;
            loop {
                if i >= old_session.allowed_entrypoints_len {
                    break;
                }
                self.session_entrypoints.write((session_key, i), 0);
                i += 1;
            };

            let sess = SessionData {
                valid_until,
                max_calls,
                calls_used: 0,
                allowed_entrypoints_len: allowed_entrypoints.len(),
            };
            self.session_keys.write(session_key, sess);

            // Store new allowed entrypoints
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
        'v31'
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
    // Delegates to SRC6Impl::is_valid_signature to avoid duplicate logic
    #[external(v0)]
    fn is_valid_signature(
        self: @ContractState,
        hash: felt252,
        signature: Array<felt252>
    ) -> felt252 {
        SRC6Impl::is_valid_signature(self, hash, signature)
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
        // SECURITY: Includes admin selector blocklist (audit fix #3, #8)
        fn _is_session_allowed_for_calls(
            self: @ContractState,
            session_key: felt252,
            calls: Span<Call>
        ) -> bool {
            let session = self.session_keys.read(session_key);
            if session.valid_until == 0 { return false; }
            if get_block_timestamp() > session.valid_until { return false; }
            if session.calls_used >= session.max_calls { return false; }

            // SECURITY: Admin selector blocklist - sessions can NEVER call these
            // This prevents session keys from upgrading the account or managing sessions
            // even with an empty whitelist (which means "allow all user functions")
            let UPGRADE_SELECTOR: felt252 = selector!("upgrade");
            let ADD_SESSION_SELECTOR: felt252 = selector!("add_or_update_session_key");
            let REVOKE_SESSION_SELECTOR: felt252 = selector!("revoke_session_key");
            // Block __execute__ to prevent nested execution privilege escalation
            let EXECUTE_SELECTOR: felt252 = selector!("__execute__");

            // First pass: check for blocked admin selectors
            let mut i = 0;
            loop {
                if i >= calls.len() { break; }
                let call = calls.at(i);
                let sel = *call.selector;

                // Block admin functions regardless of whitelist
                if sel == UPGRADE_SELECTOR
                    || sel == ADD_SESSION_SELECTOR
                    || sel == REVOKE_SESSION_SELECTOR
                    || sel == EXECUTE_SELECTOR {
                    return false;
                }
                i += 1;
            };

            // If no whitelist (allowed_entrypoints_len == 0), allow all non-admin selectors
            if session.allowed_entrypoints_len == 0 { return true; }

            // Second pass: verify all selectors are in the whitelist
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

        /// Compute SNIP-12 message hash for OutsideExecution using felt timestamps (legacy fallback).
        /// The primary path uses OZ standard (u128 timestamps). This fallback handles older
        /// paymaster versions that encode timestamps as felt instead of u128.
        fn _compute_outside_execution_hash(
            self: @ContractState,
            outside_execution: @OutsideExecution,
        ) -> felt252 {
            // Domain: {name: 'Account.execute_from_outside', version: '2', chainId: chain_id, revision: '1'}
            let chain_id = get_tx_info().unbox().chain_id;

            // Domain hash: H(DOMAIN_TYPE_HASH, name, version, chainId, revision)
            let domain_hash = poseidon_hash_span(
                array![
                    STARKNET_DOMAIN_TYPE_HASH_REV1,
                    'Account.execute_from_outside',  // name
                    2,                                // version (as shortstring/felt)
                    chain_id,                         // chainId
                    1                                 // revision
                ].span()
            );

            // Hash each Call struct
            let calls = *outside_execution.calls;
            let mut calls_hashes: Array<felt252> = array![];
            let mut i: u32 = 0;
            loop {
                if i >= calls.len() { break; }
                let call = calls.at(i);

                // Hash calldata array
                let calldata_hash = poseidon_hash_span(*call.calldata);

                // Call struct hash: H(CALL_TYPE_HASH, to, selector, calldata_hash)
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

            // Hash the calls array
            let calls_array_hash = poseidon_hash_span(calls_hashes.span());

            // OutsideExecution struct hash: H(TYPE_HASH, caller, nonce, execute_after, execute_before, calls_hash)
            // NOTE: Using felt for timestamps to match Chipi Pay paymaster
            let struct_hash = poseidon_hash_span(
                array![
                    OUTSIDE_EXECUTION_TYPE_HASH_REV1,
                    (*outside_execution.caller).into(),
                    *outside_execution.nonce,
                    (*outside_execution.execute_after).into(),  // u64 -> felt252
                    (*outside_execution.execute_before).into(), // u64 -> felt252
                    calls_array_hash
                ].span()
            );

            // Final message hash: H(prefix, domain_hash, account_address, struct_hash)
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
