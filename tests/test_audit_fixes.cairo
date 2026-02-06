/// Audit regression tests — one or more tests per Nethermind finding (#1-#10).
/// These tests directly invoke __validate__, __execute__, and is_valid_signature
/// through dispatcher interfaces, exercising every security-critical code path.

use starknet::ContractAddress;
use starknet::account::Call;
use snforge_std_deprecated::{
    declare, ContractClassTrait, DeclareResultTrait,
    start_cheat_caller_address, stop_cheat_caller_address,
    start_cheat_signature_global, stop_cheat_signature_global,
    start_cheat_block_timestamp_global,
};

use sessions_smart_contract::account::{
    ISessionKeyManagerDispatcher, ISessionKeyManagerDispatcherTrait
};

// ---------- dispatcher interfaces for account entrypoints ----------

#[starknet::interface]
trait IAccountValidate<TContractState> {
    fn __validate__(ref self: TContractState, calls: Array<Call>) -> felt252;
}

#[starknet::interface]
trait IAccountExecute<TContractState> {
    fn __execute__(ref self: TContractState, calls: Array<Call>) -> Array<Span<felt252>>;
}

#[starknet::interface]
trait IAccountSignature<TContractState> {
    fn is_valid_signature(self: @TContractState, hash: felt252, signature: Array<felt252>) -> felt252;
}

#[starknet::interface]
trait IAccountEntrypoints<TContractState> {
    fn get_session_allowed_entrypoint_at(self: @TContractState, session_key: felt252, index: u32) -> felt252;
}

// ---------- constants (reuse from test_session_validation) ----------

const OWNER_PUBKEY: felt252 = 0x123456789abcdef123456789abcdef123456789abcdef123456789abcdef;
const SESSION_PUBKEY: felt252 = 0x987654321fedcba987654321fedcba987654321fedcba987654321fedcba;
const TRANSFER_SELECTOR: felt252 = 0x83afd3f4caedc6eebf44246fe54e38c95e3179a5ec9ea81740eca5b482d12e;
const WAVE_SELECTOR: felt252 = 0x36af806f8c6a244b75823a6f3f912e5fad5c6b8a7c5e6d9b2a1f8e7c;

fn deploy_account() -> ContractAddress {
    let contract_class = declare("Account").unwrap().contract_class();
    let constructor_calldata = array![OWNER_PUBKEY];
    let (contract_address, _) = contract_class.deploy(@constructor_calldata).unwrap();
    contract_address
}

/// Helper: add a session key as owner (caller = contract itself).
fn setup_session(
    account: ContractAddress,
    session_key: felt252,
    valid_until: u64,
    max_calls: u32,
    allowed: Array<felt252>,
) {
    let sm = ISessionKeyManagerDispatcher { contract_address: account };
    start_cheat_caller_address(account, account);
    sm.add_or_update_session_key(session_key, valid_until, max_calls, allowed);
    stop_cheat_caller_address(account);
}

// ===================================================================
// Finding #1 — __execute__ caller check
// ===================================================================

#[test]
#[should_panic(expected: ('Account: unauthorized caller',))]
fn test_audit1_execute_rejects_unauthorized_caller() {
    let account = deploy_account();
    let exec = IAccountExecuteDispatcher { contract_address: account };

    // Caller is a random external address — NOT 0 and NOT self.
    let random: ContractAddress = 0xDEAD.try_into().unwrap();
    start_cheat_caller_address(account, random);

    // Should panic with 'Account: unauthorized caller'
    exec.__execute__(array![]);
}

#[test]
fn test_audit1_execute_allows_self_caller() {
    let account = deploy_account();
    let exec = IAccountExecuteDispatcher { contract_address: account };

    // Caller is the account itself — allowed.
    start_cheat_caller_address(account, account);

    let result = exec.__execute__(array![]);
    // Empty calls → empty result array, no panic.
    assert(result.len() == 0, 'Should return empty array');
    stop_cheat_caller_address(account);
}

// ===================================================================
// Finding #3 / #8 — Admin selector blocklist
// Session keys must NEVER be able to call upgrade, add_or_update_session_key,
// or revoke_session_key — even with an empty whitelist (allow-all).
// We test via __validate__ which calls _is_session_allowed_for_calls.
// ===================================================================

#[test]
fn test_audit3_session_blocked_from_upgrade() {
    let account = deploy_account();
    let current_time: u64 = 1_000_000;
    start_cheat_block_timestamp_global(current_time);

    let valid_until = current_time + 86400;
    // Empty whitelist = allow all NON-admin selectors
    setup_session(account, SESSION_PUBKEY, valid_until, 10, array![]);

    // Set session signature in tx info
    let sig = array![SESSION_PUBKEY, 0x1, 0x2, valid_until.into()];
    start_cheat_signature_global(sig.span());

    let validate = IAccountValidateDispatcher { contract_address: account };

    // Call with selector!("upgrade")
    let upgrade_selector: felt252 = selector!("upgrade");
    let calls = array![
        Call { to: account, selector: upgrade_selector, calldata: array![0x1].span() }
    ];

    // __validate__ should return 0 (rejected) — NOT VALIDATED
    let result = validate.__validate__(calls);
    assert(result == 0, 'upgrade must be blocked');

    stop_cheat_signature_global();
}

#[test]
fn test_audit3_session_blocked_from_add_session() {
    let account = deploy_account();
    let current_time: u64 = 1_000_000;
    start_cheat_block_timestamp_global(current_time);

    let valid_until = current_time + 86400;
    setup_session(account, SESSION_PUBKEY, valid_until, 10, array![]);

    let sig = array![SESSION_PUBKEY, 0x1, 0x2, valid_until.into()];
    start_cheat_signature_global(sig.span());

    let validate = IAccountValidateDispatcher { contract_address: account };

    let add_session_selector: felt252 = selector!("add_or_update_session_key");
    let calls = array![
        Call { to: account, selector: add_session_selector, calldata: array![].span() }
    ];

    let result = validate.__validate__(calls);
    assert(result == 0, 'add_session must be blocked');

    stop_cheat_signature_global();
}

#[test]
fn test_audit8_session_blocked_from_revoke() {
    let account = deploy_account();
    let current_time: u64 = 1_000_000;
    start_cheat_block_timestamp_global(current_time);

    let valid_until = current_time + 86400;
    setup_session(account, SESSION_PUBKEY, valid_until, 10, array![]);

    let sig = array![SESSION_PUBKEY, 0x1, 0x2, valid_until.into()];
    start_cheat_signature_global(sig.span());

    let validate = IAccountValidateDispatcher { contract_address: account };

    let revoke_selector: felt252 = selector!("revoke_session_key");
    let calls = array![
        Call { to: account, selector: revoke_selector, calldata: array![].span() }
    ];

    let result = validate.__validate__(calls);
    assert(result == 0, 'revoke must be blocked');

    stop_cheat_signature_global();
}

// ===================================================================
// Finding #2 / #4 — Session whitelist in __validate__ path
// A session restricted to WAVE_SELECTOR must reject TRANSFER_SELECTOR.
// ===================================================================

#[test]
fn test_audit2_validate_blocks_disallowed_selector() {
    let account = deploy_account();
    let current_time: u64 = 1_000_000;
    start_cheat_block_timestamp_global(current_time);

    let valid_until = current_time + 86400;
    // Whitelist: only WAVE_SELECTOR
    setup_session(account, SESSION_PUBKEY, valid_until, 10, array![WAVE_SELECTOR]);

    let sig = array![SESSION_PUBKEY, 0x1, 0x2, valid_until.into()];
    start_cheat_signature_global(sig.span());

    let validate = IAccountValidateDispatcher { contract_address: account };

    let target: ContractAddress = 0x1234.try_into().unwrap();
    let calls = array![
        Call { to: target, selector: TRANSFER_SELECTOR, calldata: array![].span() }
    ];

    let result = validate.__validate__(calls);
    assert(result == 0, 'disallowed selector must fail');

    stop_cheat_signature_global();
}

// ===================================================================
// Finding #5 / #6 — is_valid_signature with sessions
// ===================================================================

#[test]
fn test_audit5_is_valid_signature_session_expired_returns_zero() {
    let account = deploy_account();
    let current_time: u64 = 1_000_000;
    start_cheat_block_timestamp_global(current_time);

    let valid_until = current_time + 100;
    setup_session(account, SESSION_PUBKEY, valid_until, 10, array![]);

    // Advance time past expiration
    start_cheat_block_timestamp_global(valid_until + 1);

    let sig_checker = IAccountSignatureDispatcher { contract_address: account };

    // 4-element session signature with an expired valid_until
    let sig = array![SESSION_PUBKEY, 0x1, 0x2, valid_until.into()];

    let result = sig_checker.is_valid_signature(0xABC, sig);
    assert(result == 0, 'expired session must return 0');
}

#[test]
fn test_audit6_is_valid_signature_does_not_consume_calls() {
    let account = deploy_account();
    let current_time: u64 = 1_000_000;
    start_cheat_block_timestamp_global(current_time);

    let valid_until = current_time + 86400;
    setup_session(account, SESSION_PUBKEY, valid_until, 10, array![]);

    let sig_checker = IAccountSignatureDispatcher { contract_address: account };
    let sm = ISessionKeyManagerDispatcher { contract_address: account };

    // Call is_valid_signature twice — calls_used must stay 0 both times (read-only).
    let sig1 = array![SESSION_PUBKEY, 0x1, 0x2, valid_until.into()];
    let _ = sig_checker.is_valid_signature(0xABC, sig1);
    let data1 = sm.get_session_data(SESSION_PUBKEY);
    assert(data1.calls_used == 0, 'first call must not consume');

    let sig2 = array![SESSION_PUBKEY, 0x1, 0x2, valid_until.into()];
    let _ = sig_checker.is_valid_signature(0xDEF, sig2);
    let data2 = sm.get_session_data(SESSION_PUBKEY);
    assert(data2.calls_used == 0, 'second call must not consume');
}

// ===================================================================
// Finding #7 — Non-atomic multicall
// __execute__ continues after a failed subcall, returning an empty span.
// ===================================================================

#[test]
fn test_audit7_execute_continues_after_failed_subcall() {
    let account = deploy_account();
    let exec = IAccountExecuteDispatcher { contract_address: account };

    start_cheat_caller_address(account, account);

    // First call: invoke a selector that doesn't exist on the account contract.
    // This will fail inside call_contract_syscall → Result::Err → empty span.
    // Second call: get_contract_info (exists, will succeed).
    let get_info_selector: felt252 = selector!("get_contract_info");
    let bogus_selector: felt252 = 0xDEAD;

    let calls = array![
        Call { to: account, selector: bogus_selector, calldata: array![].span() },
        Call { to: account, selector: get_info_selector, calldata: array![].span() },
    ];

    let result = exec.__execute__(calls);
    // Non-atomic: both calls produce entries. First is empty span (failure), second succeeds.
    assert(result.len() == 2, 'should have 2 result entries');

    // Second result should contain 'v26_audit_fixes' (the return value of get_contract_info).
    let second = *result.at(1);
    assert(second.len() > 0, 'second call should succeed');
    assert(*second.at(0) == 'v26_audit_fixes', 'wrong return value');

    stop_cheat_caller_address(account);
}

// ===================================================================
// Finding #9 — Safe try_into() for valid_until
// An overflowing felt252 value for valid_until must not panic; __validate__
// should silently return 0.
// ===================================================================

#[test]
fn test_audit9_overflow_valid_until_returns_zero() {
    let account = deploy_account();
    let current_time: u64 = 1_000_000;
    start_cheat_block_timestamp_global(current_time);

    // Session exists so we reach the try_into path.
    setup_session(account, SESSION_PUBKEY, current_time + 86400, 10, array![]);

    // Signature element [3] is a value > u64::MAX — can't convert to u64.
    // felt252 max is huge; use a value above 2^64 - 1.
    let overflow_value: felt252 = 0x10000000000000000; // 2^64, exceeds u64::MAX

    let sig = array![SESSION_PUBKEY, 0x1, 0x2, overflow_value];
    start_cheat_signature_global(sig.span());

    let validate = IAccountValidateDispatcher { contract_address: account };

    let target: ContractAddress = 0x1234.try_into().unwrap();
    let calls = array![
        Call { to: target, selector: TRANSFER_SELECTOR, calldata: array![].span() }
    ];

    // Must NOT panic — returns 0 thanks to safe match pattern.
    let result = validate.__validate__(calls);
    assert(result == 0, 'overflow must return 0');

    stop_cheat_signature_global();
}

// Also test overflow in is_valid_signature (same fix applied there).
#[test]
fn test_audit9_is_valid_signature_overflow_returns_zero() {
    let account = deploy_account();
    let current_time: u64 = 1_000_000;
    start_cheat_block_timestamp_global(current_time);

    setup_session(account, SESSION_PUBKEY, current_time + 86400, 10, array![]);

    let sig_checker = IAccountSignatureDispatcher { contract_address: account };

    let overflow_value: felt252 = 0x10000000000000000;
    let sig = array![SESSION_PUBKEY, 0x1, 0x2, overflow_value];

    let result = sig_checker.is_valid_signature(0xABC, sig);
    assert(result == 0, 'overflow sig must return 0');
}

// ===================================================================
// Finding #10 — Stale entrypoints on update
// Updating a session from N entrypoints to M < N must clear indices M..N-1.
// ===================================================================

#[test]
fn test_audit10_update_session_clears_old_entrypoints() {
    let account = deploy_account();
    let ep = IAccountEntrypointsDispatcher { contract_address: account };
    let sm = ISessionKeyManagerDispatcher { contract_address: account };
    let current_time: u64 = 1_000_000;
    start_cheat_block_timestamp_global(current_time);

    let valid_until = current_time + 86400;

    // Add session with 3 entrypoints
    let ep1: felt252 = 0xAAA;
    let ep2: felt252 = 0xBBB;
    let ep3: felt252 = 0xCCC;
    start_cheat_caller_address(account, account);
    sm.add_or_update_session_key(SESSION_PUBKEY, valid_until, 10, array![ep1, ep2, ep3]);
    stop_cheat_caller_address(account);

    // Verify all 3 stored
    assert(ep.get_session_allowed_entrypoint_at(SESSION_PUBKEY, 0) == ep1, 'idx0 should be ep1');
    assert(ep.get_session_allowed_entrypoint_at(SESSION_PUBKEY, 1) == ep2, 'idx1 should be ep2');
    assert(ep.get_session_allowed_entrypoint_at(SESSION_PUBKEY, 2) == ep3, 'idx2 should be ep3');

    // Update session to only 1 entrypoint — old indices 1,2 must be cleared.
    let new_ep: felt252 = 0xDDD;
    start_cheat_caller_address(account, account);
    sm.add_or_update_session_key(SESSION_PUBKEY, valid_until, 5, array![new_ep]);
    stop_cheat_caller_address(account);

    // Index 0 is the new entrypoint
    assert(ep.get_session_allowed_entrypoint_at(SESSION_PUBKEY, 0) == new_ep, 'idx0 should be new');
    // Stale indices must be 0
    assert(ep.get_session_allowed_entrypoint_at(SESSION_PUBKEY, 1) == 0, 'idx1 must be cleared');
    assert(ep.get_session_allowed_entrypoint_at(SESSION_PUBKEY, 2) == 0, 'idx2 must be cleared');

    // Session data should reflect new values
    let data = sm.get_session_data(SESSION_PUBKEY);
    assert(data.allowed_entrypoints_len == 1, 'should have 1 entrypoint');
    assert(data.max_calls == 5, 'should have new max_calls');
    assert(data.calls_used == 0, 'calls_used reset on update');
}
