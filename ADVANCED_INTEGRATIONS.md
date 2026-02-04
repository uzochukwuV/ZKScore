# ZKScore - Advanced Integrations (Tier 3)

This document covers advanced privacy and DeFi integrations for ZKScore.

---

## 🔒 Garaga - ZK Proof Verification

**Purpose:** Verify Noir/Circom ZK proofs on Starknet for enhanced fairness verification

**Hackathon Value:** 🔒 Privacy showcase + Technical complexity
**Effort:** High
**Status:** Tier 3 (Nice-to-have)

### Use Cases

1. **Fair Randomness Proof**: Prove that match scores were generated fairly
2. **Bet Validity Proof**: Prove a bet is within valid range without revealing amount
3. **Payout Verification**: Prove correct winner calculation

### Architecture

```
┌─────────────────────────────────────────────────┐
│         ZKScore with Garaga                      │
├─────────────────────────────────────────────────┤
│  1. Generate Noir proof (off-chain)              │
│     - Prove: score = hash(block_hash + match_id) │
│     - Input: block_hash, match_id, secret       │
│     - Output: score, proof                       │
│                                                   │
│  2. Submit proof to Starknet                     │
│     - Call: verify_fairness_proof()              │
│     - Garaga verifies proof on-chain             │
│                                                   │
│  3. If valid, reveal scores                      │
│     - Update market state                        │
│     - Emit event with verified scores            │
└─────────────────────────────────────────────────┘
```

### Implementation

#### 1. Install Dependencies

```bash
# Install Garaga
npm install @garaga/sdk

# Install Noir (for proof generation)
curl -L https://raw.githubusercontent.com/noir-lang/noirup/main/install | bash
noirup
```

#### 2. Create Noir Circuit

Create `circuits/fairness_proof.nr`:

```rust
// Noir circuit to prove fair score generation
fn main(
    block_hash: pub Field,
    match_id: pub Field,
    secret: Field,
    score: pub Field,
) {
    // Prove: score = hash(block_hash + match_id + secret) % max_score
    let computed_score = poseidon_hash([block_hash, match_id, secret]);
    let max_score = 100; // Basketball max score

    assert(score == computed_score % max_score);
}
```

#### 3. Generate Proof (Frontend)

```typescript
import { generateProof } from "@garaga/sdk";

async function generateFairnessProof(
  blockHash: string,
  matchId: number,
  secret: string,
  score: number
) {
  const proof = await generateProof({
    circuit: "fairness_proof",
    inputs: {
      block_hash: blockHash,
      match_id: matchId,
      secret: secret,
      score: score,
    },
  });

  return {
    proof: proof.proof,
    publicInputs: [blockHash, matchId, score],
  };
}
```

#### 4. Verify on Starknet (Smart Contract)

```cairo
use garaga::groth16::verify_proof;

#[starknet::interface]
pub trait IGaragaVerifier<TContractState> {
    fn verify_fairness_proof(
        ref self: TContractState,
        match_id: u64,
        score: u32,
        proof: Span<felt252>,
        public_inputs: Span<felt252>,
    ) -> bool;
}

#[starknet::contract]
pub mod GaragaVerifier {
    use super::*;

    #[storage]
    struct Storage {
        verifying_key: felt252, // Groth16 verifying key
        verified_scores: Map<u64, bool>,
    }

    #[abi(embed_v0)]
    impl GaragaVerifierImpl of IGaragaVerifier<ContractState> {
        fn verify_fairness_proof(
            ref self: ContractState,
            match_id: u64,
            score: u32,
            proof: Span<felt252>,
            public_inputs: Span<felt252>,
        ) -> bool {
            // Verify proof using Garaga
            let is_valid = verify_proof(
                self.verifying_key.read(),
                proof,
                public_inputs
            );

            if is_valid {
                self.verified_scores.write(match_id, true);
            }

            is_valid
        }
    }
}
```

### Benefits

- **Provable Fairness**: Users can verify scores were generated correctly
- **Trustless**: No need to trust contract owner
- **Privacy**: Can prove properties without revealing secrets

### References

- [Garaga Documentation](https://docs.garaga.io)
- [Garaga npm package](https://www.npmjs.com/package/@garaga/sdk)
- [scaffold-garaga](https://github.com/garaga-team/scaffold-garaga)

---

## 👻 Semaphore - Anonymous Betting Identities

**Purpose:** Enable anonymous betting using zero-knowledge group membership proofs

**Hackathon Value:** 🔒 Privacy + 🚀 Wildcard (Novel use case)
**Effort:** High
**Status:** Tier 3 (Nice-to-have)

### Use Cases

1. **Anonymous High-Value Bets**: Hide whale bets from market
2. **Privacy-Preserving Leaderboards**: Show top bettors without revealing identities
3. **Sybil Resistance**: Prove uniqueness without revealing identity

### Architecture

```
┌─────────────────────────────────────────────────┐
│         ZKScore with Semaphore                   │
├─────────────────────────────────────────────────┤
│  1. User joins anonymous betting group           │
│     - Generate identity commitment               │
│     - Add to Merkle tree                         │
│                                                   │
│  2. Place anonymous bet                          │
│     - Generate ZK proof of group membership      │
│     - Prove: "I'm in the group but don't        │
│       reveal which member I am"                  │
│                                                   │
│  3. Claim winnings anonymously                   │
│     - Generate proof with nullifier              │
│     - Prevent double claims                      │
│     - Withdraw to fresh address                  │
└─────────────────────────────────────────────────┘
```

### Implementation

#### 1. Install Semaphore

```bash
npm install @semaphore-protocol/core
npm install @semaphore-protocol/contracts
```

#### 2. Create Anonymous Betting Group (Smart Contract)

```cairo
use semaphore::group::Group;
use semaphore::proof::Proof;

#[starknet::contract]
pub mod AnonymousBetting {
    use super::*;

    #[storage]
    struct Storage {
        // Semaphore group for anonymous bettors
        betting_group: Group,

        // Nullifiers to prevent double spending
        used_nullifiers: Map<felt252, bool>,

        // Anonymous bet commitments
        anonymous_bets: Map<felt252, AnonymousBet>,
    }

    #[derive(Drop, Serde, starknet::Store)]
    struct AnonymousBet {
        match_id: u64,
        outcome: u8,
        amount: u256, // Encrypted or in zero-knowledge range
        merkle_root: felt252,
    }

    #[abi(embed_v0)]
    impl AnonymousBettingImpl {
        fn join_betting_group(
            ref self: ContractState,
            identity_commitment: felt252,
        ) {
            // Add user to anonymous betting group
            self.betting_group.add_member(identity_commitment);
        }

        fn place_anonymous_bet(
            ref self: ContractState,
            match_id: u64,
            outcome: u8,
            amount: u256,
            proof: Proof,
            nullifier: felt252,
        ) {
            // Verify Semaphore proof
            assert(
                semaphore::verify_proof(
                    self.betting_group.get_root(),
                    nullifier,
                    proof,
                ),
                'Invalid proof'
            );

            // Check nullifier hasn't been used
            assert(
                !self.used_nullifiers.read(nullifier),
                'Nullifier already used'
            );

            // Mark nullifier as used
            self.used_nullifiers.write(nullifier, true);

            // Store anonymous bet
            // Amount is committed but not revealed
            let bet = AnonymousBet {
                match_id,
                outcome,
                amount, // Could be encrypted or ZK range proof
                merkle_root: self.betting_group.get_root(),
            };

            self.anonymous_bets.write(nullifier, bet);
        }

        fn claim_anonymous_winnings(
            ref self: ContractState,
            nullifier: felt252,
            proof: Proof,
            withdrawal_address: ContractAddress,
        ) {
            // Verify proof and nullifier
            let bet = self.anonymous_bets.read(nullifier);

            // Check if bet won
            // ...

            // Transfer winnings to withdrawal address
            // No link between original bettor and withdrawal address!
        }
    }
}
```

#### 3. Frontend Integration

```typescript
import { Identity } from "@semaphore-protocol/identity";
import { Group } from "@semaphore-protocol/group";
import { generateProof } from "@semaphore-protocol/proof";

async function placeAnonymousBet(
  matchId: number,
  outcome: 0 | 1,
  amount: bigint
) {
  // 1. Create or load user's Semaphore identity
  const identity = new Identity();

  // 2. Get current betting group
  const group = await fetchBettingGroup();

  // 3. Generate zero-knowledge proof
  const { proof, nullifier, merkleTreeRoot } = await generateProof(
    identity,
    group,
    matchId, // External nullifier (prevents betting twice on same match)
    amount.toString() // Signal
  );

  // 4. Submit anonymous bet
  await contract.place_anonymous_bet(
    matchId,
    outcome,
    amount,
    proof,
    nullifier
  );

  console.log("Anonymous bet placed! No one knows it was you 👻");
}
```

### Benefits

- **Full Anonymity**: No link between bettor and bet
- **Sybil Resistance**: Prevent multiple bets from same user
- **Privacy Leaderboards**: Show "Anonymous Bettor #1234 won 10 BTC"

### References

- [Semaphore Protocol](https://semaphore.pse.dev/)
- [Semaphore Docs](https://docs.semaphore.pse.dev/)
- [Semaphore Learn](https://semaphore.pse.dev/learn)

---

## 💧 Ekubo - Liquidity Pools for Betting Tokens

**Purpose:** Create liquid markets for outcome tokens using Ekubo AMM

**Hackathon Value:** 🚀 Wildcard (DeFi innovation)
**Effort:** Medium
**Status:** Tier 3 (Nice-to-have)

### Use Cases

1. **Outcome Token Trading**: Trade "Lakers Win" tokens on Ekubo
2. **Liquidity Provision**: LPs earn fees from traders
3. **Price Discovery**: Market-driven odds via Ekubo pools

### Architecture

```
┌─────────────────────────────────────────────────┐
│         ZKScore + Ekubo Integration              │
├─────────────────────────────────────────────────┤
│  ZKScore creates outcome tokens                 │
│      ↓                                            │
│  Deploy Ekubo pool: LAKERS_WIN / STRK           │
│      ↓                                            │
│  LPs provide liquidity                           │
│      ↓                                            │
│  Traders swap on Ekubo                           │
│  - Buy LAKERS_WIN with STRK                      │
│  - Sell LAKERS_WIN for STRK                      │
│      ↓                                            │
│  After match settles:                            │
│  - Winning tokens redeemed 1:1                   │
│  - Losing tokens go to 0                         │
└─────────────────────────────────────────────────┘
```

### Implementation

#### 1. Deploy Ekubo Pool

```typescript
import { Pool } from "@ekubo/sdk";

async function deployOutcomeTokenPool(
  outcomeToken: string,
  baseToken: string, // STRK
  initialPrice: number
) {
  const pool = await Pool.deploy({
    token0: outcomeToken,
    token1: baseToken,
    fee: 3000, // 0.3% fee
    tickSpacing: 60,
    initialPrice: initialPrice,
  });

  console.log(`Ekubo pool deployed: ${pool.address}`);
  return pool;
}
```

#### 2. Add Liquidity

```typescript
async function provideLiquidity(
  poolAddress: string,
  amountToken: bigint,
  amountSTRK: bigint
) {
  const pool = new Pool(poolAddress);

  const position = await pool.mint({
    tickLower: -887220, // Full range liquidity
    tickUpper: 887220,
    amount0: amountToken,
    amount1: amountSTRK,
  });

  console.log(`Liquidity position: ${position.id}`);
}
```

#### 3. Swap on Ekubo

```typescript
async function buyOutcomeToken(
  poolAddress: string,
  amountSTRK: bigint
): Promise<bigint> {
  const pool = new Pool(poolAddress);

  const { amountOut } = await pool.swap({
    zeroForOne: false, // Swapping STRK for outcome token
    amountIn: amountSTRK,
    sqrtPriceLimitX96: 0, // No limit
  });

  return amountOut;
}
```

#### 4. Integration with PredictionMarket

```cairo
#[starknet::contract]
pub mod EkuboIntegration {
    use ekubo::pool::IPoolDispatcher;

    #[storage]
    struct Storage {
        // Ekubo pool for each outcome token
        ekubo_pools: Map<ContractAddress, ContractAddress>,
    }

    #[abi(embed_v0)]
    impl EkuboIntegrationImpl {
        fn create_market_with_ekubo(
            ref self: ContractState,
            team_a_name: ByteArray,
            team_b_name: ByteArray,
            initial_liquidity: u256,
        ) -> u64 {
            // 1. Create prediction market (standard flow)
            let match_id = self.create_market(
                team_a_name,
                team_b_name,
                initial_liquidity
            );

            let market = self.markets.read(match_id);

            // 2. Deploy Ekubo pools for outcome tokens
            let team_a_pool = self.deploy_ekubo_pool(
                market.team_a_token,
                STRK_TOKEN,
                500000, // Initial price: 0.5 STRK
            );

            let team_b_pool = self.deploy_ekubo_pool(
                market.team_b_token,
                STRK_TOKEN,
                500000, // Initial price: 0.5 STRK
            );

            // Store pool addresses
            self.ekubo_pools.write(market.team_a_token, team_a_pool);
            self.ekubo_pools.write(market.team_b_token, team_b_pool);

            match_id
        }

        fn trade_on_ekubo(
            ref self: ContractState,
            outcome_token: ContractAddress,
            amount_in: u256,
            zero_for_one: bool,
        ) -> u256 {
            let pool_address = self.ekubo_pools.read(outcome_token);
            let pool = IPoolDispatcher { contract_address: pool_address };

            // Execute swap on Ekubo
            let (amount_out, _) = pool.swap(
                zero_for_one,
                amount_in,
                0, // No price limit
            );

            amount_out
        }
    }
}
```

### Benefits

- **Deeper Liquidity**: Ekubo's concentrated liquidity
- **Better Prices**: Efficient price discovery
- **LP Incentives**: Earn fees from trading volume
- **Composability**: Integrate with other DeFi protocols

### References

- [Ekubo Docs](https://docs.ekubo.org)
- [Ekubo Protocol](https://ekubo.org)

---

## 🎯 Integration Priority Roadmap

### Week 3 (Tier 2 - Should Have)

**Priority 1:** Tongo SDK
- **Time:** 3-4 days
- **Impact:** 🔒🔒🔒 Huge privacy boost
- **Action:** Implement commit-reveal + ElGamal encryption

**Priority 2:** Garden SDK
- **Time:** 3-4 days
- **Impact:** ₿₿₿ Bitcoin track winner
- **Action:** Integrate BTC → Starknet bridge

**Priority 3:** Xverse Wallet
- **Time:** 1-2 days
- **Impact:** ₿₿ Better UX
- **Action:** Add dual wallet support

### Week 4 (Tier 3 - Nice to Have)

**Priority 4:** Garaga
- **Time:** 4-5 days
- **Impact:** 🔒 Privacy showcase
- **Action:** ZK proof verification for fairness

**Priority 5:** Semaphore
- **Time:** 4-5 days
- **Impact:** 🔒 + 🚀 Privacy + Innovation
- **Action:** Anonymous betting groups

**Priority 6:** Ekubo
- **Time:** 2-3 days
- **Impact:** 🚀 DeFi composability
- **Action:** Liquidity pools for outcome tokens

---

## 📊 Decision Matrix

| Integration | Privacy | Bitcoin | Wildcard | Effort | ROI |
|-------------|---------|---------|----------|--------|-----|
| Tongo SDK | ⭐⭐⭐⭐⭐ | ⭐ | ⭐⭐ | Medium | 🔥🔥🔥🔥🔥 |
| Garden SDK | ⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐ | Medium | 🔥🔥🔥🔥🔥 |
| Xverse | ⭐ | ⭐⭐⭐⭐ | ⭐ | Low | 🔥🔥🔥🔥 |
| Garaga | ⭐⭐⭐⭐ | ⭐ | ⭐⭐⭐ | High | 🔥🔥🔥 |
| Semaphore | ⭐⭐⭐⭐⭐ | ⭐ | ⭐⭐⭐⭐ | High | 🔥🔥🔥 |
| Ekubo | ⭐ | ⭐ | ⭐⭐⭐⭐⭐ | Medium | 🔥🔥 |

## 🎯 Recommendation for Hackathon

**MUST HAVE (for winning):**
1. **Tongo SDK** - Privacy track essential
2. **Garden SDK** - Bitcoin track essential

**NICE TO HAVE (bonus points):**
3. **Xverse Wallet** - Better Bitcoin UX
4. **Garaga** - Technical showcase

**SKIP FOR NOW (post-hackathon):**
5. **Semaphore** - Cool but time-intensive
6. **Ekubo** - Good for mainnet, not critical for demo

---

## 🚀 Quick Start

### Tier 2 Implementation (This Week)

```bash
# 1. Install Tongo SDK
npm install @tongo/sdk

# 2. Install Garden SDK
npm install @catalogfi/garden-sdk

# 3. Install Xverse SDK
npm install @xverse/wallet-sdk

# 4. Implement integrations (see code files)
# - packages/nextjs/utils/tongoIntegration.ts ✅
# - packages/nextjs/utils/gardenIntegration.ts ✅
# - packages/nextjs/utils/xverseIntegration.ts ✅
```

### Tier 3 Implementation (Next Week, if time)

```bash
# 1. Install Garaga
npm install @garaga/sdk
noirup

# 2. Install Semaphore
npm install @semaphore-protocol/core

# 3. Install Ekubo SDK
npm install @ekubo/sdk
```

---

**With these integrations, ZKScore becomes a comprehensive DeFi x Bitcoin x Privacy platform! 🚀**
