// SNIP-9 v2 Implementation with SNIP-12 Typed Data Hashing
// Based on: https://github.com/starknet-io/SNIPs/blob/main/SNIPS/snip-9.md

use starknet::account::Call;

// SNIP-9 Outside Execution struct
#[derive(Drop, Serde)]
pub struct OutsideExecution {
    pub caller: starknet::ContractAddress,
    pub nonce: felt252,
    pub execute_after: u64,
    pub execute_before: u64,
    pub calls: Span<Call>,
}

// SNIP-12 Revision 1 Type Hashes
// These are computed from QUOTED type strings as per SNIP-12 Rev 1:
//   "StarknetDomain"("name":"shortstring","version":"shortstring","chainId":"shortstring","revision":"shortstring")
//   "Call"("To":"ContractAddress","Selector":"selector","Calldata":"felt*")
//   "OutsideExecution"("Caller":"ContractAddress","Nonce":"felt","Execute After":"felt","Execute Before":"felt","Calls":"Call*")"Call"("To":"ContractAddress","Selector":"selector","Calldata":"felt*")
pub const STARKNET_DOMAIN_TYPE_HASH: felt252 = 
    0x1ff2f602e42168014d405a94f75e8a93d640751d71d16311266e140d8b0a210;
pub const CALL_TYPE_HASH: felt252 = 
    0x3635c7f2a7ba93844c0d064e18e487f35ab90f7c39d00f186a781fc3f0c2ca9;
pub const OUTSIDE_EXECUTION_TYPE_HASH: felt252 = 
    0x5a4b49e17039355cd95d1f0981d75901191d1319b1f4b05a9a791d218d7e0c;

#[starknet::interface]
pub trait IOutsideExecution<TContractState> {
    fn execute_from_outside_v2(
        ref self: TContractState,
        outside_execution: OutsideExecution,
        signature: Array<felt252>,  // SNIP-9 v2 standard requires Array
    ) -> Array<Span<felt252>>;
    
    fn is_valid_outside_execution_nonce(
        self: @TContractState,
        nonce: felt252
    ) -> bool;
    
    fn get_outside_execution_message_hash_rev_1(
        self: @TContractState,
        outside_execution: OutsideExecution,  // Contains calls inside!
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
    }

    #[derive(Drop, starknet::Event)]
    pub struct OutsideExecutionExecuted {
        #[key]
        pub hash: felt252,
        pub nonce: felt252,
        pub caller: ContractAddress,
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

            // 2. Validate caller (ANY_CALLER = 0 means anyone can execute)
            let tx_info = get_tx_info().unbox();
            let actual_caller = tx_info.account_contract_address;
            let any_caller: ContractAddress = 0.try_into().unwrap();
            if outside_execution.caller != any_caller {
                assert(
                    actual_caller == outside_execution.caller,
                    Errors::INVALID_CALLER
                );
            }

            // 3. Validate nonce (prevent replay)
            assert(
                !self.outside_execution_nonces.read(outside_execution.nonce),
                Errors::NONCE_USED
            );
            self.outside_execution_nonces.write(outside_execution.nonce, true);

            // 4. Copy needed values before moving outside_execution
            let calls_span = outside_execution.calls;
            let nonce_copy = outside_execution.nonce;
            
            let mut calls_array = array![];
            let mut i = 0;
            loop {
                if i >= calls_span.len() {
                    break;
                }
                calls_array.append(*calls_span.at(i));
                i += 1;
            };
            
            // 5. Compute SNIP-12 message hash
            let message_hash = self._get_outside_execution_hash(
                outside_execution,
                calls_span
            );

            // 6. Validate signature
            let mut contract_state = self.get_contract_mut();
            let is_valid = contract_state.validate_signature(message_hash, signature);
            assert(is_valid, Errors::INVALID_SIGNATURE);

            // 7. Execute calls
            let results = contract_state.execute_calls(calls_array);

            // 8. Emit success event
            self.emit(OutsideExecutionExecuted {
                hash: message_hash,
                nonce: nonce_copy,
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
        ) -> felt252 {
            let calls = outside_execution.calls;
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

        /// Hash the domain separator (SNIP-12 Revision 1)
        /// Domain: StarknetDomain(name, version, chainId, revision)
        /// Note: version and revision are encoded as NUMERIC values (0x2, 0x1)
        /// not as ASCII shortstrings (0x32, 0x31) to match starknet.js behavior
        fn _hash_domain(
            self: @ComponentState<TContractState>,
            chain_id: felt252
        ) -> felt252 {
            let mut hash_data = array![];
            
            hash_data.append(STARKNET_DOMAIN_TYPE_HASH);
            hash_data.append('Account.execute_from_outside');  // name (shortstring)
            hash_data.append(2);                                // version (numeric, not '2')
            hash_data.append(chain_id);                         // chainId
            hash_data.append(1);                                // revision (numeric, not '1')
            
            poseidon_hash_span(hash_data.span())
        }

        /// Hash the OutsideExecution struct per SNIP-12 Revision 1
        /// The `Call*` suffix means: pre-hash the array of call hashes, then use single hash
        fn _hash_outside_execution(
            self: @ComponentState<TContractState>,
            outside_execution: OutsideExecution,
            calls: Span<Call>,
        ) -> felt252 {
            // First, compute hash for each call
            let mut call_hashes = array![];
            let mut i = 0;
            loop {
                if i >= calls.len() {
                    break;
                }
                call_hashes.append(self._hash_call(*calls.at(i)));
                i += 1;
            };
            
            // Pre-hash the calls array (required for Call* type in SNIP-12 Rev 1)
            let calls_array_hash = poseidon_hash_span(call_hashes.span());
            
            let mut hash_data = array![];
            hash_data.append(OUTSIDE_EXECUTION_TYPE_HASH);
            hash_data.append(outside_execution.caller.into());
            hash_data.append(outside_execution.nonce);
            hash_data.append(outside_execution.execute_after.into());
            hash_data.append(outside_execution.execute_before.into());
            hash_data.append(calls_array_hash);  // Single hash of calls array
            
            poseidon_hash_span(hash_data.span())
        }

        /// Hash a single Call struct per SNIP-12 Revision 1
        /// The `felt*` suffix means: pre-hash the calldata array, then use single hash
        fn _hash_call(
            self: @ComponentState<TContractState>,
            call: Call
        ) -> felt252 {
            // Pre-hash the calldata array (required for felt* type in SNIP-12 Rev 1)
            let calldata_hash = poseidon_hash_span(call.calldata);
            
            let mut hash_data = array![];
            hash_data.append(CALL_TYPE_HASH);
            hash_data.append(call.to.into());
            hash_data.append(call.selector);
            hash_data.append(calldata_hash);  // Single hash of calldata array
            
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

