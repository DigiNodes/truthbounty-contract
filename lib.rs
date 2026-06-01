#![no_std]
use soroban_sdk::{contract, contractimpl, contracttype, Env, Address};

#[contracttype]
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum DataKey {
    ClaimCountPerBlock(u32), // Stores the ledger sequence as the discriminator
}

pub const MAX_CLAIMS_PER_BLOCK: u32 = 5;

#[contract]
pub struct ClaimContract;

#[contractimpl]
impl ClaimContract {
    pub fn claim(env: Env, _user: Address) {
        enforce_block_claim_limit(&env);
        
        // Logic for processing the claim goes here...
    }
}

pub fn enforce_block_claim_limit(env: &Env) {
    let current_ledger = env.ledger().sequence();
    let key = DataKey::ClaimCountPerBlock(current_ledger);
    
    // Retrieve the current count for this specific block or default to 0
    let mut current_claims: u32 = env.storage().temporary().get(&key).unwrap_or(0);
    
    // Enforce invariant limit check
    if current_claims >= MAX_CLAIMS_PER_BLOCK {
        panic!("Execution aborted: Max claims per block limit exceeded to prevent gas spam.");
    }
    
    // Increment and update tracking state
    current_claims += 1;
    env.storage().temporary().set(&key, &current_claims);
}

#[cfg(test)]
mod test {
    use super::*;

    #[test]
    fn test_max_claims_per_block_invariant() {
        let env = Env::default();
        let contract_id = env.register_contract(None, ClaimContract);
        let client = ClaimContractClient::new(&env, &contract_id);
        let user = Address::generate(&env);

        // Set ledger to a specific block sequence
        env.ledger().with_mut(|l| {
            l.sequence = 100_000;
        });

        // Execute valid claims up to the allowed limit boundary
        for _ in 0..MAX_CLAIMS_PER_BLOCK {
            assert!(client.try_claim(&user).is_ok());
        }

        // The next claim invocation within the exact same block sequence MUST fail/panic
        let violation_result = client.try_claim(&user);
        assert!(violation_result.is_err());

        // Advance the block sequence forward to clear the temporary window
        env.ledger().with_mut(|l| {
            l.sequence = 100_001;
        });

        // Claims should naturally succeed again in the fresh block window
        let next_result = client.try_claim(&user);
        assert!(next_result.is_ok(), "Expected claim to succeed in new block sequence");
    }
}