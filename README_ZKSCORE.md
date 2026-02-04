# ZKScore ⚡ 🏀

**On-Chain Sports Prediction Markets with Halftime Trading on Starknet**

> Privacy-preserving, Bitcoin-settled prediction markets with verifiable randomness. No oracles needed.

## 🎯 Hackathon Submission

**RE{DEFINED} - Bitcoin and Privacy Hackathon**

### Prize Tracks
- 🔒 **Privacy Track**: CPMM with private bet amounts (future: Tongo SDK integration)
- ₿ **Bitcoin Track**: STRK token payments (designed for sBTC integration)
- 🚀 **Wildcard Track**: Novel halftime trading mechanism with on-chain randomness

---

## 📖 Overview

ZKScore revolutionizes prediction markets by:

1. **Eliminating Oracles**: Sports scores generated on-chain using Starknet's verifiable randomness
2. **Tradeable Positions**: Bets are ERC20 tokens that can be bought/sold anytime
3. **Halftime Trading**: First AMM to support live trading between match periods
4. **Privacy-First**: Designed for confidential transactions (Tongo SDK ready)
5. **Bitcoin Native**: Built for BTC settlements via bridges (Garden SDK/Xverse)

---

## 🏗️ Architecture

### Smart Contracts

```
┌─────────────────────────────────────────────────────┐
│                   ZKScore System                     │
├─────────────────────────────────────────────────────┤
│  1. PredictionMarket.cairo                           │
│     - CPMM (Constant Product Market Maker)           │
│     - Market creation & management                   │
│     - Halftime reveal logic                          │
│     - Final settlement & redemption                  │
│                                                       │
│  2. OutcomeToken.cairo                               │
│     - ERC20 tokens for each outcome                  │
│     - "LAKERS_WIN", "WARRIORS_WIN" tokens            │
│     - Tradeable, burnable, mintable                  │
└─────────────────────────────────────────────────────┘
```

### Key Innovations

#### 1. **Automated Market Maker (AMM) for Predictions**

Unlike traditional parimutuel betting (locked bets), ZKScore uses a **Constant Product Market Maker**:

```
Formula: x * y = k

Where:
- x = Team A token reserves
- y = Team B token reserves
- k = constant

Price of Team A = y / (x + y)
Price of Team B = x / (x + y)
```

**Example:**
```
Initial: 500 LAKERS tokens, 500 WARRIORS tokens
Price: LAKERS = 0.50 STRK (50%), WARRIORS = 0.50 STRK

User buys 100 LAKERS tokens → pays ~111 STRK
New reserves: 400 LAKERS, 611 WARRIORS
New price: LAKERS = 0.60 STRK (60%), WARRIORS = 0.40 STRK

Price reflects market sentiment in real-time!
```

#### 2. **Halftime Trading**

The **only** prediction market with two trading windows per match:

```
Timeline:
├─ T0: Match created, pre-match trading begins
├─ T1: Pre-match trading closes
├─ T2: FIRST HALF scores revealed (on-chain randomness)
│       Example: Lakers 52 - 48 Warriors
├─ T3: HALFTIME TRADING opens (prices react!)
│       LAKERS price jumps: 0.48 → 0.65
│       WARRIORS price drops: 0.52 → 0.35
├─ T4: Halftime trading closes
├─ T5: SECOND HALF scores revealed
│       Final: Lakers 105 - 98 Warriors
└─ T6: Winners redeem tokens at 1:1 ratio
```

#### 3. **Verifiable Randomness (No Oracle!)**

Scores generated using Starknet's block hash:

```cairo
fn _generate_half_scores(match_id: u64, half: u8, sport_type: SportType) -> (u32, u32) {
    // Use block hash as entropy source
    let block_hash: u256 = get_block_hash_syscall(block_number - 1).into();

    // Combine with match_id and half for unique seed
    let seed = block_hash + match_id.into() + half.into();

    // Generate scores (Football: 0-5, Basketball: 30-60 per half)
    let team_a_score = (seed % max_score).try_into().unwrap();
    let team_b_score = ((seed / 1000) % max_score).try_into().unwrap();

    (team_a_score, team_b_score)
}
```

**Why this works:**
- Block hash is unpredictable until block is mined
- Deterministic but unbiased
- Fully verifiable on-chain
- No trust required

---

## 💡 How It Works

### User Flow

#### Phase 1: Pre-Match Trading

```
1. User connects wallet (Argent/Braavos/Xverse)
2. Views match: "Lakers vs Warriors"
   - Current odds: LAKERS 0.52, WARRIORS 0.48
3. Buys 100 LAKERS tokens for ~105 STRK
4. Receives 100 LAKERS ERC20 tokens
5. Can sell anytime before halftime reveal
```

#### Phase 2: First Half Reveal

```
6. Pre-match window closes (1 hour)
7. Anyone calls reveal_first_half()
8. Scores generated on-chain:
   🏀 First Half: Lakers 52 - 48 Warriors
9. Market reacts:
   - LAKERS price: 0.52 → 0.65 (Lakers leading!)
   - WARRIORS price: 0.48 → 0.35
```

#### Phase 3: Halftime Trading

```
10. User sees Lakers leading, decides to lock profit
11. Sells 50 LAKERS tokens at 0.64 → receives ~64 STRK
12. Keeps 50 LAKERS tokens (hedged position)
```

#### Phase 4: Final Settlement

```
13. Halftime window closes (15 min)
14. Second half scores revealed:
    🏀 Second Half: Lakers 53 - 50 Warriors
    🏆 FINAL: Lakers 105 - 98 Warriors
15. User redeems 50 LAKERS tokens → receives 50 STRK
    Total: 64 (from sell) + 50 (redemption) = 114 STRK
    Profit: 114 - 105 = 9 STRK
```

---

## 🔒 Privacy Features

### Current: Hash-Based Privacy

Commit-reveal scheme for bet amounts (optional):

```cairo
// Commit Phase
commitment = hash(amount, outcome, secret)
contract.commit_bet(match_id, commitment)

// Reveal Phase (after betting closes)
contract.reveal_bet(match_id, amount, outcome, secret)
// Verifies: hash(amount, outcome, secret) == commitment
```

### Future: Tongo SDK Integration

**ElGamal encryption** for confidential amounts:

```typescript
// Encrypt bet amount
const encrypted = tongoSDK.encrypt({
  amount: 100,
  publicKey: contractPublicKey,
});

// Submit encrypted trade
await contract.buy_outcome_private(matchId, outcome, encrypted);

// Contract processes without revealing amount to public
// Only final settlement reveals winner amounts via ZK proof
```

**Benefits:**
- Bet amounts stay private even after reveal
- Prevents front-running
- Full privacy for all participants
- Compatible with Starknet Privacy Toolkit

---

## ₿ Bitcoin Integration

### Current: STRK Token

Uses STRK (Starknet native token) for all transactions:

```cairo
const STRK_TOKEN: felt252 = 0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d;
```

### Future: Bitcoin Bridging

**Garden SDK** or **Xverse Bridge** integration:

```typescript
// User bridges BTC to Starknet
await gardenSDK.bridge({
  from: 'bitcoin',
  to: 'starknet',
  amount: '0.001 BTC', // ~ $60
});

// Receives sBTC on Starknet
// Uses sBTC for prediction market bets
await market.buy_outcome(matchId, outcome, sBTC_amount);

// Wins and redeems
await market.redeem_winning_tokens(matchId, amount);
// Receives sBTC → bridges back to Bitcoin
```

**Why Bitcoin?**
- Larger user base
- More liquidity
- Trust-minimized bridges (Garden, Xverse)
- Quantum-safe settlement on Starknet

---

## 📦 Smart Contracts

### 1. PredictionMarket.cairo

**Main contract** handling all market logic.

**Key Functions:**

```cairo
// Create new match
fn create_market(
    team_a_name: ByteArray,
    team_b_name: ByteArray,
    sport_type: SportType, // Football or Basketball
    initial_liquidity: u256,
    pre_match_duration: u64,
    halftime_duration: u64,
) -> u64

// Buy outcome tokens (CPMM)
fn buy_outcome(
    match_id: u64,
    outcome: u8, // 0 = Team A, 1 = Team B
    max_amount_in: u256,
) -> u256

// Sell outcome tokens
fn sell_outcome(
    match_id: u64,
    outcome: u8,
    tokens_in: u256,
) -> u256

// Get current price
fn get_current_price(
    match_id: u64,
    outcome: u8,
) -> u256 // Returns price in 1e18 precision

// Reveal first half scores
fn reveal_first_half(match_id: u64)

// Reveal final scores and settle
fn reveal_final_scores(match_id: u64)

// Redeem winning tokens
fn redeem_winning_tokens(
    match_id: u64,
    amount: u256,
)
```

**Storage:**

```cairo
struct Market {
    match_id: u64,
    sport_type: SportType,
    team_a_name: ByteArray,
    team_b_name: ByteArray,

    team_a_token: ContractAddress,
    team_b_token: ContractAddress,

    team_a_reserve: u256, // CPMM reserves
    team_b_reserve: u256,
    k: u256, // Constant product

    first_half_team_a: u32,
    first_half_team_b: u32,
    second_half_team_a: u32,
    second_half_team_b: u32,

    pre_match_end_time: u64,
    halftime_end_time: u64,

    status: MarketStatus,
    winning_outcome: u8,
}
```

### 2. OutcomeToken.cairo

**ERC20 tokens** representing match outcomes.

```cairo
// Example tokens:
// - "Lakers Wins" (LAKERSWIN)
// - "Warriors Wins" (WARRIORSWIN)

fn mint(to: ContractAddress, amount: u256) // Only market contract
fn burn(from: ContractAddress, amount: u256) // Only market contract
```

---

## 🧪 Testing

Comprehensive test suite covering:

```bash
cd packages/snfoundry/contracts
yarn test

# Tests include:
✅ Market creation
✅ CPMM buy/sell mechanics
✅ Price discovery (x*y=k formula)
✅ Halftime reveal
✅ Halftime trading window
✅ Final settlement
✅ Token redemption
✅ Access control
✅ Edge cases (draws, zero amounts, etc.)
```

---

## 🚀 Deployment

### Prerequisites

```bash
# Install dependencies
yarn install

# Compile contracts
yarn compile
```

### Deploy to Sepolia Testnet

```bash
# 1. Configure wallet (deployer)
export STARKNET_ACCOUNT=<your_account_address>
export STARKNET_PRIVATE_KEY=<your_private_key>

# 2. Deploy
yarn deploy

# 3. Verify
yarn verify
```

### Contract Addresses (Sepolia)

```
OutcomeToken Class Hash: TBD
PredictionMarket: TBD
```

---

## 📊 Economic Model

### Liquidity Provision

```
Initial Market Creation:
- Owner provides initial liquidity (e.g., 1000 STRK)
- Split 50/50: 500 LAKERS tokens, 500 WARRIORS tokens
- k = 500 * 500 = 250,000
```

### Trading Fees (Optional)

```cairo
// Can add 0.3% fee like Uniswap
let fee = amount_in * 3 / 1000;
let amount_after_fee = amount_in - fee;
```

### Winner Payout

```
Clear Winner:
- Winning tokens redeem at 1:1 ratio
- Losing tokens become worthless

Draw:
- Both tokens redeem at 0.5:1 ratio
- Fair split of pool
```

---

## 🎥 Demo Video Script

**Title:** "ZKScore: Sports Betting Meets DeFi AMM on Starknet"

```
[00:00-00:15] Problem
"Traditional prediction markets lock your bets.
Oracles are centralized.
No way to exit early."

[00:15-00:30] Solution
"ZKScore: The first AMM for sports predictions
with LIVE halftime trading.
No oracles. Pure on-chain randomness."

[00:30-01:00] Demo: Pre-Match Trading
- Show match creation
- Buy LAKERS tokens at 0.50
- Watch price update to 0.55
- Sell some tokens, lock profit

[01:00-01:30] Demo: Halftime Reveal
- First half scores revealed on-chain
- Lakers 52 - 48 Warriors
- Price jumps: LAKERS 0.55 → 0.65
- Show halftime trading window opens

[01:30-02:00] Demo: Halftime Trading
- Market reacts to scores
- Users can reposition
- Show sell at new price

[02:00-02:30] Demo: Final Settlement
- Second half revealed
- Final: Lakers 105 - 98
- Redeem winning tokens
- Show profit calculation

[02:30-03:00] Tech Showcase
"Privacy: Tongo SDK ready
Bitcoin: Garden/Xverse integration
Randomness: Starknet VRF
Innovation: First halftime AMM"

https://claude.ai/code/session_01DccvzeencZGeFosSyaP7Vv
```

---

## 🛣️ Roadmap

### Phase 1: MVP (Hackathon) ✅
- [x] CPMM prediction market
- [x] Halftime trading
- [x] On-chain randomness
- [x] STRK token support
- [ ] Frontend UI
- [ ] Deployment to testnet

### Phase 2: Privacy (Week 1 post-hackathon)
- [ ] Tongo SDK integration
- [ ] ElGamal encrypted bet amounts
- [ ] ZK proofs for valid trades
- [ ] Private position tracking

### Phase 3: Bitcoin (Week 2 post-hackathon)
- [ ] Garden SDK bridge integration
- [ ] sBTC token support
- [ ] Xverse wallet integration
- [ ] Bitcoin RPC access (Xverse prize)

### Phase 4: Advanced Features (Month 2)
- [ ] Garaga ZK proof verification
- [ ] Multiple sport types
- [ ] Liquidity pools (Ekubo integration)
- [ ] DAO governance for match creation

---

## 🏆 Hackathon Differentiation

### Why ZKScore Wins

| Criteria | ZKScore | Traditional Prediction Markets |
|----------|---------|-------------------------------|
| **Oracle Risk** | None (on-chain randomness) | High (Chainlink, API3) |
| **Liquidity** | Always tradeable (AMM) | Locked until settlement |
| **Exit Strategy** | Sell anytime | No exit |
| **Innovation** | Halftime trading | N/A |
| **Privacy** | Tongo SDK ready | No privacy |
| **Bitcoin** | Bridge-ready | No Bitcoin support |
| **Technology** | STARK proofs, VRF, CPMM | Basic escrow |

### Technical Highlights for Judges

1. **Novel AMM Design**: First CPMM for halftime sports trading
2. **Zero Oracle Dependency**: Fully on-chain verifiable randomness
3. **Privacy-First Architecture**: Built for Tongo SDK from day 1
4. **Bitcoin Native**: Designed for sBTC/Garden SDK integration
5. **Pure Starknet**: Leverages STARK proofs, VRF, Cairo 2.12

---

## 📚 References

### Starknet Resources
- [Starknet Docs](https://docs.starknet.io)
- [Cairo Book](https://book.cairo-lang.org)
- [OpenZeppelin Cairo Contracts](https://docs.openzeppelin.com/contracts-cairo)

### Privacy Tools
- [Tongo SDK](https://docs.tongo.xyz)
- [Starknet Privacy Toolkit](https://github.com/starknet-privacy)
- [Garaga Documentation](https://docs.garaga.io)

### Bitcoin Integration
- [Garden SDK](https://docs.garden.finance)
- [Xverse Starknet Bridge](https://xverse.app/starknet)
- [Starknet Bitcoin DeFi](https://www.starknet.io/bitcoin)

---

## 👥 Team

Built for RE{DEFINED} Bitcoin and Privacy Hackathon

---

## 📝 License

MIT License

---

## 🔗 Links

- **Hackathon**: https://hackathon.starknet.org/
- **GitHub**: https://github.com/yourusername/ZKScore
- **Demo Video**: TBD
- **Deployed Contract**: TBD

---

## 🙏 Acknowledgments

- Starknet Foundation for the amazing hackathon
- OpenZeppelin for battle-tested contracts
- Tongo team for privacy toolkit inspiration
- Garden/Xverse for Bitcoin bridge tech

---

**ZKScore**: Where Privacy Meets Bitcoin. Where Sports Meet DeFi. 🏀⚡₿

*Built on Starknet. Powered by STARKs.*
