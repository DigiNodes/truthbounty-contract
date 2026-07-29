# SC-032: Protocol Economic Simulation & Stress Testing Framework

## Overview

Implements the **Protocol Economic Simulation & Stress Testing Framework** — enabling deterministic simulation of protocol economics under a wide range of scenarios without affecting live protocol state.

The framework is intended for governance decision-making, audit validation, and continuous economic verification. Simulation results are **advisory only** and must never directly execute protocol changes.

## Changes

### New Contracts

- **`contracts/simulation/IEconomicSimulation.sol`** — Interface defining:
  - `Scenario` enum (6 predefined scenarios)
  - `EconomicMetrics`, `GovernanceParams`, `SimulationConfig`, `SimulationReport` structs
  - Core `simulate()` / `previewSimulation()` functions
  - `validateGovernanceParams()` for governance proposal validation
  - Events: `SimulationExecuted`, `EconomicThresholdExceeded`, `SimulationCompleted`
  - Read interfaces for scenarios, reports, and history

- **`contracts/simulation/EconomicSimulation.sol`** — Implementation with:
  - **Economic Simulation Engine** — Pure-memory day-by-day simulation of:
    - Reward emissions based on active verifiers, total staked, governance params
    - Treasury growth/revenue collection with scenario-specific multipliers
    - Verifier participation dynamics (stable, declining, or fluctuating)
    - Staking dynamics with growth modelling
    - Reputation evolution through update engine interaction
    - Governance parameter changes impact analysis
  - **Scenario Library** (6 predefined scenarios):
    - `NORMAL_GROWTH` — Steady growth baseline
    - `HIGH_GROWTH` — 3x claim volume, 2x revenue
    - `LOW_PARTICIPATION` — Declining verifier activity, 33% claims
    - `ADVERSARIAL_BEHAVIOUR` — 2x spam claims, 33% revenue
    - `TREASURY_STRESS` — 25% revenue, small treasury
    - `GOVERNANCE_CHANGE` — 100% verifier bonus from policy changes
  - **Economic Metrics** computed:
    - `treasurySolvency` — Remaining treasury balance
    - `totalRewardEmissions` — Total rewards distributed
    - `protocolRevenue` — Revenue collected from fees/slashing
    - `verifierProfitability` — Average profit per verifier
    - `averageSettlementCost` — Average cost per claim settlement
    - `inflationRate` — Effective inflation rate (annualised BPS)
    - `reserveUtilisation` — Treasury reserve usage (BPS)
    - `sustainabilityIndex` — Composite score (0–10000)
  - **Governance Parameter Validation** — Rejects unsafe combinations:
    - Detects excessive inflation, treasury insolvency, impossible configs
    - Generates machine-readable warnings and recommendations
  - **Economic Threshold Warnings** — Configurable metric thresholds
  - **Access Control** — `SIMULATOR_ROLE`-gated simulation execution
  - **Read Interfaces** — Paginated history, scenario names/descriptions

### New Tests

- **`test/simulation/EconomicSimulation.t.sol`** — Unit and integration tests:
  - All 6 scenario simulations produce valid reports
  - Preview simulation (no state mutation)
  - Governance parameter validation (valid + invalid)
  - Simulation determinism across repeated runs
  - Simulation isolation from protocol state
  - Access control (only SIMULATOR_ROLE)
  - Economic threshold configuration
  - View functions (scenarios, names, descriptions, pagination)
  - Edge cases (simulation not found, zero duration)

- **`test/invariant/SimulationInvariant.t.sol`** — Invariant tests:
  - Simulations are completely isolated (append-only storage)
  - Repeated configurations produce identical metrics
  - Metrics are internally consistent
  - All scenarios produce valid reports
  - Invalid governance params are always rejected
  - Simulation storage is append-only

## Architecture

```
┌─────────────────────────────────────────────┐
│          EconomicSimulation                 │
│  ┌─────────────────────────────────────┐   │
│  │      Simulation Engine              │   │
│  │  (pure memory, no side effects)     │   │
│  │  - Day-by-day iteration             │   │
│  │  - Scenario-specific multipliers    │   │
│  │  - Economic calculations            │   │
│  └─────────────────────────────────────┘   │
│  ┌─────────────────────────────────────┐   │
│  │      Scenario Library               │   │
│  │  - Normal Growth                    │   │
│  │  - High Growth                      │   │
│  │  - Low Participation                │   │
│  │  - Adversarial Behaviour            │   │
│  │  - Treasury Stress                  │   │
│  │  - Governance Change                │   │
│  └─────────────────────────────────────┘   │
│  ┌─────────────────────────────────────┐   │
│  │      Governance Validator           │   │
│  │  - Parameter validation             │   │
│  │  - Warning generation               │   │
│  │  - Sustainability scoring           │   │
│  └─────────────────────────────────────┘   │
│  ┌─────────────────────────────────────┐   │
│  │      Report Storage                 │   │
│  │  - Append-only simulation history   │   │
│  │  - Machine-readable reports         │   │
│  │  - Paginated queries                │   │
│  └─────────────────────────────────────┘   │
└─────────────────────────────────────────────┘
```

## Security Considerations

- Simulation execution is completely isolated from protocol state (pure memory computation within VM)
- Simulation results are **advisory** — they never execute protocol changes
- Access control via `SIMULATOR_ROLE` prevents unauthorised simulation
- Input validation rejects invalid configurations
- Overflow protection via safe arithmetic
- No external contract calls that could be re-entered

## Gas Benchmarks

| Operation | Gas (estimated) |
|-----------|----------------|
| Normal Growth (365 days) | ~200,000 |
| Preview simulation | ~180,000 |
| Governance validation | ~20,000 |
| Report retrieval | ~15,000 |

## ⛓ Dependencies

- SC-019 — Governance Parameter Management
- SC-023 — Protocol Observability Framework
- SC-027 — Tokenomics & Incentive Distribution Framework
- SC-029 — Dynamic Reward Calculation Engine
- SC-031 — Protocol Insurance Fund Framework

## ✅ Acceptance Checklist

- [x] Simulation Engine implemented
- [x] Scenario library completed (6 scenarios)
- [x] Economic metrics generated (6+ metrics)
- [x] Governance parameter validation implemented
- [x] Simulation reports generated (machine-readable)
- [x] Read interfaces available (scenarios, history, pagination)
- [x] Documentation completed (PR + comments)
- [x] Unit tests added (all scenarios)
- [x] Integration tests pass
- [x] Invariant tests pass
- [x] CI passes successfully
- [x] Deterministic and reproducible across all supported scenarios
