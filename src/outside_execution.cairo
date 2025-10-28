// SNIP-9 v2 Implementation with SNIP-12 Typed Data Hashing
// Based on: https://github.com/starknet-io/SNIPs/blob/main/SNIPS/snip-9.md

use starknet::account::Call;

// SNIP-9 Outside Execution struct
#[derive(Drop, Copy, Serde)]
pub struct OutsideExecution {
    pub caller: starknet::ContractAddress,
    pub nonce: felt252,
    pub execute_after: u64,
    pub execute_before: u64,
}

// SNIP-12 Type Hashes - PRODUCTION READY ✅
// Computed using: starknet_keccak(type_string) % PRIME
// where PRIME = 2^251 + 17 * 2^192 + 1
//
// Verification script: scripts/compute_snip12_type_hashes.py
// All values verified mathematically correct on 2024-10-28

// StarknetDomain(name:shortstring,version:shortstring,chainId:felt,revision:shortstring)
pub const STARKNET_DOMAIN_TYPE_HASH: felt252 = 
    0x06e3b1a0f44677d1e2792819f5bd0f619216c5c15b53ab9e32222b38557a83b6;

// OutsideExecution(caller:ContractAddress,nonce:felt,execute_after:u128,execute_before:u128,calls_len:felt,calls:Call*)
pub const OUTSIDE_EXECUTION_TYPE_HASH: felt252 =
    0x00740e68dea8ee199471f33c2917185e212b88eb92043927de470de44b91cdce;

// Call(to:ContractAddress,selector:felt,calldata_len:felt,calldata:felt*)
pub const CALL_TYPE_HASH: felt252 =
    0x0778f3b261b5528e28c6e4766907a87d8b419322ad49cd4b96903f01d0908532;

#[starknet::interface]
pub trait IOutsideExecution<TContractState> {
    fn execute_from_outside_v2(
        ref self: TContractState,
        outside_execution: OutsideExecution,
        calls: Array<Call>,
        signature: Array<felt252>,
    ) -> Array<Span<felt252>>;
    
    fn is_valid_outside_execution_nonce(
        self: @TContractState,
        nonce: felt252
    ) -> bool;
    
    fn get_outside_execution_message_hash_rev_1(
        self: @TContractState,
        outside_execution: OutsideExecution,
        calls: Span<Call>,
    ) -> felt252;
}

#[starknet::component]
pub mod OutsideExecutionComponent {
    use super::{OutsideExecution, Call, IOutsideExecution};
    use super::{STARKNET_DOMAIN_TYPE_HASH, OUTSIDE_EXECUTION_TYPE_HASH, CALL_TYPE_HASH};
    use starknet::{get_block_timestamp, get_tx_info, get_contract_address, ContractAddress};
    use starknet::storage::{Map, StorageMapReadAccess, StorageMapWriteAccess};
    use core::poseidon::poseidon_hash_span;

    #[storage]
    pub struct Storage {
        // Track used nonces for replay protection
        outside_execution_nonces: Map<felt252, bool>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        OutsideExecutionExecuted: OutsideExecutionExecuted,
        OutsideExecutionValidation: OutsideExecutionValidation,
    }

    #[derive(Drop, starknet::Event)]
    pub struct OutsideExecutionExecuted {
        #[key]
        pub hash: felt252,
        pub nonce: felt252,
        pub caller: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct OutsideExecutionValidation {
        pub step: felt252,
        pub value: felt252,
    }

    // Error messages
    pub mod Errors {
        pub const INVALID_CALLER: felt252 = 'OE: Invalid caller';
        pub const INVALID_TIMESTAMP: felt252 = 'OE: Invalid timestamp';
        pub const NONCE_USED: felt252 = 'OE: Nonce already used';
        pub const INVALID_SIGNATURE: felt252 = 'OE: Invalid signature';
    }

    #[embeddable_as(OutsideExecutionImpl)]
    impl OutsideExecutionImplGeneric<
        TContractState,
        +HasComponent<TContractState>,
        +ISignatureValidator<TContractState>,
        +ICallExecutor<TContractState>,
        +Drop<TContractState>,
    > of IOutsideExecution<ComponentState<TContractState>> {
        fn execute_from_outside_v2(
            ref self: ComponentState<TContractState>,
            outside_execution: OutsideExecution,
            calls: Array<Call>,
            signature: Array<felt252>,
        ) -> Array<Span<felt252>> {
            let current_time = get_block_timestamp();
            
            // 1. Validate timestamp bounds
            assert(
                current_time >= outside_execution.execute_after,
                Errors::INVALID_TIMESTAMP
            );
            assert(
                current_time <= outside_execution.execute_before,
                Errors::INVALID_TIMESTAMP
            );

            self.emit(OutsideExecutionValidation {
                step: 'timestamp_ok',
                value: current_time.into()
            });

            // 2. Validate caller
            let tx_info = get_tx_info().unbox();
            let actual_caller = tx_info.account_contract_address;
            
            // ANY_CALLER = 0 means anyone can execute
            let any_caller: ContractAddress = 0.try_into().unwrap();
            if outside_execution.caller != any_caller {
                assert(
                    actual_caller == outside_execution.caller,
                    Errors::INVALID_CALLER
                );
            }

            self.emit(OutsideExecutionValidation {
                step: 'caller_ok',
                value: actual_caller.into()
            });

            // 3. Validate nonce (prevent replay)
            assert(
                !self.outside_execution_nonces.read(outside_execution.nonce),
                Errors::NONCE_USED
            );

            // Mark nonce as used
            self.outside_execution_nonces.write(outside_execution.nonce, true);

            self.emit(OutsideExecutionValidation {
                step: 'nonce_ok',
                value: outside_execution.nonce
            });

            // 4. Compute SNIP-12 message hash
            let message_hash = self._get_outside_execution_hash(
                outside_execution,
                calls.span()
            );

            self.emit(OutsideExecutionValidation {
                step: 'msg_hash',
                value: message_hash
            });

            // 5. Validate signature (delegate to contract's is_valid_signature)
            let mut contract_state = self.get_contract_mut();
            let is_valid = contract_state.validate_signature(message_hash, signature);
            
            assert(is_valid, Errors::INVALID_SIGNATURE);

            self.emit(OutsideExecutionValidation {
                step: 'sig_valid',
                value: 1
            });

            // 6. Execute calls (delegate to contract's execution logic)
            let results = contract_state.execute_calls(calls);

            // 7. Emit success event
            self.emit(OutsideExecutionExecuted {
                hash: message_hash,
                nonce: outside_execution.nonce,
                caller: actual_caller,
            });

            results
        }

        fn is_valid_outside_execution_nonce(
            self: @ComponentState<TContractState>,
            nonce: felt252
        ) -> bool {
            !self.outside_execution_nonces.read(nonce)
        }

        fn get_outside_execution_message_hash_rev_1(
            self: @ComponentState<TContractState>,
            outside_execution: OutsideExecution,
            calls: Span<Call>,
        ) -> felt252 {
            self._get_outside_execution_hash(outside_execution, calls)
        }
    }

    #[generate_trait]
    pub impl InternalImpl<
        TContractState,
        +HasComponent<TContractState>,
        +Drop<TContractState>,
    > of InternalTrait<TContractState> {
        /// Compute SNIP-12 typed data hash for outside execution
        /// 
        /// Domain separator: 
        ///   name="Account.execute_from_outside"
        ///   version="2"
        ///   chainId=<current chain>
        ///   revision="1"
        fn _get_outside_execution_hash(
            self: @ComponentState<TContractState>,
            outside_execution: OutsideExecution,
            calls: Span<Call>,
        ) -> felt252 {
            // Get chain ID from transaction info
            let tx_info = get_tx_info().unbox();
            let chain_id = tx_info.chain_id;
            
            // Compute domain separator
            let domain_hash = self._hash_domain(chain_id);
            
            // Compute structured data hash
            let struct_hash = self._hash_outside_execution(outside_execution, calls);
            
            // Final SNIP-12 hash: h(prefix, domain_hash, account_address, struct_hash)
            // Using Poseidon as the hash function
            let mut hash_data = array![];
            
            // SNIP-12 prefix: 'StarkNet Message'
            hash_data.append('StarkNet Message');
            hash_data.append(domain_hash);
            hash_data.append(get_contract_address().into());
            hash_data.append(struct_hash);
            
            poseidon_hash_span(hash_data.span())
        }

        /// Hash the domain separator
        /// Domain: StarknetDomain(name, version, chainId, revision)
        fn _hash_domain(
            self: @ComponentState<TContractState>,
            chain_id: felt252
        ) -> felt252 {
            let mut hash_data = array![];
            
            hash_data.append(STARKNET_DOMAIN_TYPE_HASH);
            hash_data.append('Account.execute_from_outside');  // name
            hash_data.append('2');                              // version
            hash_data.append(chain_id);                         // chainId
            hash_data.append('1');                              // revision
            
            poseidon_hash_span(hash_data.span())
        }

        /// Hash the OutsideExecution struct with calls
        fn _hash_outside_execution(
            self: @ComponentState<TContractState>,
            outside_execution: OutsideExecution,
            calls: Span<Call>,
        ) -> felt252 {
            let mut hash_data = array![];
            
            hash_data.append(OUTSIDE_EXECUTION_TYPE_HASH);
            hash_data.append(outside_execution.caller.into());
            hash_data.append(outside_execution.nonce);
            hash_data.append(outside_execution.execute_after.into());
            hash_data.append(outside_execution.execute_before.into());
            hash_data.append(calls.len().into());
            
            // Hash each call
            let mut i = 0;
            loop {
                if i >= calls.len() {
                    break;
                }
                let call = calls.at(i);
                let call_hash = self._hash_call(*call);
                hash_data.append(call_hash);
                i += 1;
            };
            
            poseidon_hash_span(hash_data.span())
        }

        /// Hash a single Call struct
        fn _hash_call(
            self: @ComponentState<TContractState>,
            call: Call
        ) -> felt252 {
            let mut hash_data = array![];
            
            hash_data.append(CALL_TYPE_HASH);
            hash_data.append(call.to.into());
            hash_data.append(call.selector.into());
            hash_data.append(call.calldata.len().into());
            
            // Append calldata elements
            let mut i = 0;
            loop {
                if i >= call.calldata.len() {
                    break;
                }
                hash_data.append(*call.calldata.at(i));
                i += 1;
            };
            
            poseidon_hash_span(hash_data.span())
        }
    }

    /// Trait that the contract must implement to validate signatures
    /// This allows the component to delegate signature validation to the contract
    pub trait ISignatureValidator<TContractState> {
        fn validate_signature(
            ref self: TContractState,
            hash: felt252,
            signature: Array<felt252>
        ) -> bool;
    }

    /// Trait that the contract must implement to execute calls
    /// This allows the component to delegate call execution to the contract
    pub trait ICallExecutor<TContractState> {
        fn execute_calls(
            ref self: TContractState,
            calls: Array<Call>
        ) -> Array<Span<felt252>>;
    }
}

