#![no_std]

use soroban_sdk::{
    contract, contractimpl, contracttype, Env, Address, BytesN, Vec, symbol_short
};

#[contract]
pub struct ReputationBridge;

#[contracttype]
#[derive(Clone)]
pub enum DataKey {
    Admin,
    SnapshotRoot,
    PendingRoot,
    ExecuteAfter,
    UsedProof(BytesN<32>),
}

// ⏳ 1 day timelock (in ledger seconds approx)
const DELAY: u64 = 86400;

#[contractimpl]
impl ReputationBridge {

    // 🏗 Initialize contract
    pub fn initialize(env: Env, admin: Address, initial_root: BytesN<32>) {
        admin.require_auth();

        env.storage().instance().set(&DataKey::Admin, &admin);
        env.storage().instance().set(&DataKey::SnapshotRoot, &initial_root);
    }

    // 🔐 Get admin
    fn get_admin(env: &Env) -> Address {
        env.storage().instance().get(&DataKey::Admin).unwrap()
    }

    // ✅ Step 1: Propose new root
    pub fn propose_root(env: Env, new_root: BytesN<32>) {
        let admin = Self::get_admin(&env);
        admin.require_auth();

        let current_time = env.ledger().timestamp();

        env.storage().instance().set(&DataKey::PendingRoot, &new_root);
        env.storage().instance().set(&DataKey::ExecuteAfter, &(current_time + DELAY));
    }

    // ✅ Step 2: Execute root update after delay
    pub fn execute_root_update(env: Env) {
        let pending: BytesN<32> = env.storage()
            .instance()
            .get(&DataKey::PendingRoot)
            .unwrap();

        let execute_after: u64 = env.storage()
            .instance()
            .get(&DataKey::ExecuteAfter)
            .unwrap();

        let now = env.ledger().timestamp();

        if now < execute_after {
            panic!("Timelock not expired");
        }

        env.storage().instance().set(&DataKey::SnapshotRoot, &pending);

        // Clear pending
        env.storage().instance().remove(&DataKey::PendingRoot);
        env.storage().instance().remove(&DataKey::ExecuteAfter);
    }

    // 🔍 Verify Merkle proof (basic)
    fn verify_proof(
        env: &Env,
        proof: Vec<BytesN<32>>,
        root: BytesN<32>,
        leaf: BytesN<32>,
    ) -> bool {
        let mut computed = leaf;

        for p in proof.iter() {
            if computed < p {
                computed = env.crypto().sha256(&(computed, p));
            } else {
                computed = env.crypto().sha256(&(p, computed));
            }
        }

        computed == root
    }

    // ✅ Claim rewards with replay protection
    pub fn claim(
        env: Env,
        user: Address,
        amount: u128,
        proof: Vec<BytesN<32>>,
    ) {
        user.require_auth();

        // 🔒 Unique proof hash
        let proof_hash = env.crypto().sha256(&(user.clone(), amount));

        // 🚫 Replay protection
        if env.storage().instance().has(&DataKey::UsedProof(proof_hash.clone())) {
            panic!("Proof already used");
        }

        let root: BytesN<32> = env.storage()
            .instance()
            .get(&DataKey::SnapshotRoot)
            .unwrap();

        let leaf = env.crypto().sha256(&(user.clone(), amount));

        if !Self::verify_proof(&env, proof, root, leaf) {
            panic!("Invalid proof");
        }

        // ✅ Mark as used BEFORE effects
        env.storage().instance().set(
            &DataKey::UsedProof(proof_hash.clone()),
            &true,
        );

        // 💰 Transfer logic goes here (token contract call)
        // Example:
        // token_client.transfer(&env.current_contract_address(), &user, &amount);

        // Optional event
        env.events().publish(
            (symbol_short!("claim"), user),
            amount
        );
    }
}