#![no_std]

use soroban_sdk::{
    contract, contractimpl, contracttype, panic_with_error,
    token, Address, BytesN, Env, Symbol, Vec,
};

// ----------------------------------------------------------------
// Error Types
// ----------------------------------------------------------------

#[contracttype]
#[derive(Clone, Debug, PartialEq)]
pub enum BridgeError {
    NotInitialized       = 1,
    AlreadyInitialized   = 2,
    Unauthorized         = 3,
    TimelockNotExpired   = 4,
    NoPendingRoot        = 5,
    ProofAlreadyUsed     = 6,
    InvalidProof         = 7,
    InvalidAmount        = 8,
    InvalidLeaf          = 9,
}

// ----------------------------------------------------------------
// Storage Keys
// ----------------------------------------------------------------

#[contracttype]
#[derive(Clone)]
pub enum DataKey {
    Admin,
    TokenAddress,
    SnapshotRoot,
    PendingRoot,
    ExecuteAfter,
    UsedProof(BytesN<32>),
    Initialized,
}

// ----------------------------------------------------------------
// Constants
// ----------------------------------------------------------------

/// 1-day timelock in ledger seconds
const DELAY: u64 = 86_400;

/// TTL bump thresholds (in ledgers, ~5s each)
const LEDGER_BUMP: u32 = 17_280; // ~1 day
const LEDGER_THRESHOLD: u32 = 8_640; // bump when below ~12hrs

// ----------------------------------------------------------------
// Contract
// ----------------------------------------------------------------

#[contract]
pub struct ReputationBridge;

#[contractimpl]
impl ReputationBridge {

    // ----------------------------------------------------------------
    // Initialization
    // ----------------------------------------------------------------

    /// Initialize the contract. Can only be called once.
    pub fn initialize(
        env: Env,
        admin: Address,
        token: Address,
        initial_root: BytesN<32>,
    ) {
        // Prevent re-initialization
        if env.storage().instance().has(&DataKey::Initialized) {
            panic_with_error!(&env, BridgeError::AlreadyInitialized);
        }

        admin.require_auth();

        env.storage().instance().set(&DataKey::Initialized,   &true);
        env.storage().instance().set(&DataKey::Admin,         &admin);
        env.storage().instance().set(&DataKey::TokenAddress,  &token);
        env.storage().instance().set(&DataKey::SnapshotRoot,  &initial_root);

        Self::bump_instance(&env);

        env.events().publish(
            (Symbol::new(&env, "initialized"), admin),
            initial_root,
        );
    }

    // ----------------------------------------------------------------
    // Admin: Root Management (Timelock)
    // ----------------------------------------------------------------

    /// Step 1 — Propose a new Merkle root. Starts the timelock.
    pub fn propose_root(env: Env, new_root: BytesN<32>) {
        Self::assert_initialized(&env);

        let admin = Self::get_admin(&env);
        admin.require_auth();

        let execute_after = env.ledger().timestamp() + DELAY;

        env.storage().instance().set(&DataKey::PendingRoot,   &new_root);
        env.storage().instance().set(&DataKey::ExecuteAfter,  &execute_after);

        Self::bump_instance(&env);

        env.events().publish(
            (Symbol::new(&env, "root_proposed"), admin),
            (new_root, execute_after),
        );
    }

    /// Step 2 — Execute root update after timelock has expired.
    pub fn execute_root_update(env: Env) {
        Self::assert_initialized(&env);

        let pending: BytesN<32> = env
            .storage()
            .instance()
            .get(&DataKey::PendingRoot)
            .unwrap_or_else(|| panic_with_error!(&env, BridgeError::NoPendingRoot));

        let execute_after: u64 = env
            .storage()
            .instance()
            .get(&DataKey::ExecuteAfter)
            .unwrap_or_else(|| panic_with_error!(&env, BridgeError::NoPendingRoot));

        if env.ledger().timestamp() < execute_after {
            panic_with_error!(&env, BridgeError::TimelockNotExpired);
        }

        // Rotate root
        let old_root: BytesN<32> = env
            .storage()
            .instance()
            .get(&DataKey::SnapshotRoot)
            .unwrap();

        env.storage().instance().set(&DataKey::SnapshotRoot, &pending);

        // Clear pending state
        env.storage().instance().remove(&DataKey::PendingRoot);
        env.storage().instance().remove(&DataKey::ExecuteAfter);

        Self::bump_instance(&env);

        env.events().publish(
            (Symbol::new(&env, "root_updated"),),
            (old_root, pending),
        );
    }

    /// Cancel a pending root proposal. Admin only.
    pub fn cancel_root(env: Env) {
        Self::assert_initialized(&env);

        let admin = Self::get_admin(&env);
        admin.require_auth();

        env.storage().instance().remove(&DataKey::PendingRoot);
        env.storage().instance().remove(&DataKey::ExecuteAfter);

        env.events().publish(
            (Symbol::new(&env, "root_cancelled"), admin),
            (),
        );
    }

    // ----------------------------------------------------------------
    // Claim
    // ----------------------------------------------------------------

    /// Claim rewards using a valid Merkle proof.
    pub fn claim(
        env: Env,
        user: Address,
        amount: i128,
        proof: Vec<BytesN<32>>,
    ) {
        Self::assert_initialized(&env);

        user.require_auth();

        // Validate amount
        if amount <= 0 {
            panic_with_error!(&env, BridgeError::InvalidAmount);
        }

        // Build leaf from user + amount
        let leaf = Self::make_leaf(&env, &user, amount);

        // Replay protection: unique key per (user, amount)
        let proof_key = DataKey::UsedProof(leaf.clone());

        if env.storage().persistent().has(&proof_key) {
            panic_with_error!(&env, BridgeError::ProofAlreadyUsed);
        }

        // Fetch current snapshot root
        let root: BytesN<32> = env
            .storage()
            .instance()
            .get(&DataKey::SnapshotRoot)
            .unwrap_or_else(|| panic_with_error!(&env, BridgeError::NotInitialized));

        // Verify Merkle proof
        if !Self::verify_proof(&env, proof, root, leaf.clone()) {
            panic_with_error!(&env, BridgeError::InvalidProof);
        }

        // ✅ Mark proof as used BEFORE transfer (checks-effects-interactions)
        env.storage().persistent().set(&proof_key, &true);
        env.storage().persistent().extend_ttl(
            &proof_key,
            LEDGER_THRESHOLD,
            LEDGER_BUMP,
        );

        // 💰 Execute token transfer
        let token_address: Address = env
            .storage()
            .instance()
            .get(&DataKey::TokenAddress)
            .unwrap();

        let token_client = token::Client::new(&env, &token_address);
        token_client.transfer(
            &env.current_contract_address(),
            &user,
            &amount,
        );

        Self::bump_instance(&env);

        env.events().publish(
            (Symbol::new(&env, "claimed"), user.clone()),
            (amount, leaf),
        );
    }

    // ----------------------------------------------------------------
    // Admin Transfer
    // ----------------------------------------------------------------

    /// Transfer admin rights to a new address.
    pub fn transfer_admin(env: Env, new_admin: Address) {
        Self::assert_initialized(&env);

        let admin = Self::get_admin(&env);
        admin.require_auth();

        env.storage().instance().set(&DataKey::Admin, &new_admin);

        Self::bump_instance(&env);

        env.events().publish(
            (Symbol::new(&env, "admin_transferred"), admin),
            new_admin,
        );
    }

    // ----------------------------------------------------------------
    // View Functions
    // ----------------------------------------------------------------

    pub fn get_root(env: Env) -> BytesN<32> {
        Self::assert_initialized(&env);
        env.storage().instance().get(&DataKey::SnapshotRoot).unwrap()
    }

    pub fn get_pending_root(env: Env) -> Option<BytesN<32>> {
        env.storage().instance().get(&DataKey::PendingRoot)
    }

    pub fn get_execute_after(env: Env) -> Option<u64> {
        env.storage().instance().get(&DataKey::ExecuteAfter)
    }

    pub fn is_proof_used(env: Env, proof_hash: BytesN<32>) -> bool {
        env.storage()
            .persistent()
            .has(&DataKey::UsedProof(proof_hash))
    }

    pub fn get_admin_address(env: Env) -> Address {
        Self::get_admin(&env)
    }

    // ----------------------------------------------------------------
    // Internal Helpers
    // ----------------------------------------------------------------

    fn assert_initialized(env: &Env) {
        if !env.storage().instance().has(&DataKey::Initialized) {
            panic_with_error!(env, BridgeError::NotInitialized);
        }
    }

    fn get_admin(env: &Env) -> Address {
        env.storage()
            .instance()
            .get(&DataKey::Admin)
            .unwrap_or_else(|| panic_with_error!(env, BridgeError::Unauthorized))
    }

    /// Produce a canonical leaf hash: SHA256(user_address || amount)
    fn make_leaf(env: &Env, user: &Address, amount: i128) -> BytesN<32> {
        env.crypto().sha256(&(user.clone(), amount))
    }

    /// Standard binary Merkle proof verification.
    /// Nodes are sorted before hashing to match off-chain tree construction.
    fn verify_proof(
        env: &Env,
        proof: Vec<BytesN<32>>,
        root: BytesN<32>,
        leaf: BytesN<32>,
    ) -> bool {
        let mut computed = leaf;

        for sibling in proof.iter() {
            computed = if computed <= sibling {
                env.crypto().sha256(&(computed, sibling))
            } else {
                env.crypto().sha256(&(sibling, computed))
            };
        }

        computed == root
    }

    /// Bump instance storage TTL to keep contract alive.
    fn bump_instance(env: &Env) {
        env.storage()
            .instance()
            .extend_ttl(LEDGER_THRESHOLD, LEDGER_BUMP);
    }
}