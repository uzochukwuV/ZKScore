use starknet::ContractAddress;

#[derive(Drop, Serde, Copy, starknet::Store)]
pub enum SportType {
    Football,   // 0-5 goals per half typical
    Basketball, // 30-60 points per half typical
}

#[derive(Drop, Serde, Copy, starknet::Store, PartialEq)]
pub enum MarketStatus {
    PreMatchTrading,  // Before first half reveal
    HalftimeTrading,  // After first half, before second half
    TradingClosed,    // After halftime window, before settlement
    Settled,          // Final scores revealed, winners can claim
}

#[derive(Drop, Serde, starknet::Store)]
pub struct Market {
    pub match_id: u64,
    pub sport_type: SportType,
    pub team_a_name: ByteArray,
    pub team_b_name: ByteArray,

    // Outcome tokens
    pub team_a_token: ContractAddress,
    pub team_b_token: ContractAddress,

    // CPMM reserves (x * y = k)
    pub team_a_reserve: u256,
    pub team_b_reserve: u256,
    pub k: u256,

    // Scores
    pub first_half_team_a: u32,
    pub first_half_team_b: u32,
    pub second_half_team_a: u32,
    pub second_half_team_b: u32,

    // Timing
    pub pre_match_end_time: u64,
    pub halftime_end_time: u64,

    // Status
    pub status: MarketStatus,
    pub winning_outcome: u8, // 0 = Team A, 1 = Team B, 2 = Draw

    // LP tracking
    pub total_lp_tokens: u256,      // Total LP tokens minted for this market
    pub accumulated_fees: u256,      // Fees collected from trading
    pub initial_pool_value: u256,    // Pool value at creation (for LP calculations)
}

#[starknet::interface]
pub trait IPredictionMarket<TContractState> {
    // Market creation
    fn create_market(
        ref self: TContractState,
        team_a_name: ByteArray,
        team_b_name: ByteArray,
        sport_type: SportType,
        initial_liquidity: u256,
        pre_match_duration: u64,
        halftime_duration: u64,
    ) -> u64;

    // Liquidity Management
    fn add_liquidity(ref self: TContractState, match_id: u64, amount: u256) -> u256; // Returns LP tokens
    fn remove_liquidity(ref self: TContractState, match_id: u64, lp_tokens: u256) -> u256; // Returns STRK
    fn get_lp_balance(self: @TContractState, match_id: u64, provider: ContractAddress) -> u256;
    fn get_lp_value(self: @TContractState, match_id: u64, provider: ContractAddress) -> u256;

    // Trading
    fn buy_outcome(
        ref self: TContractState,
        match_id: u64,
        outcome: u8,
        max_amount_in: u256
    ) -> u256;

    fn sell_outcome(
        ref self: TContractState,
        match_id: u64,
        outcome: u8,
        tokens_in: u256
    ) -> u256;

    // Price queries
    fn get_buy_price(self: @TContractState, match_id: u64, outcome: u8, amount_in: u256) -> u256;
    fn get_sell_price(self: @TContractState, match_id: u64, outcome: u8, tokens_in: u256) -> u256;
    fn get_current_price(self: @TContractState, match_id: u64, outcome: u8) -> u256;

    // Score reveal
    fn reveal_first_half(ref self: TContractState, match_id: u64);
    fn reveal_final_scores(ref self: TContractState, match_id: u64);

    // Settlement
    fn redeem_winning_tokens(ref self: TContractState, match_id: u64, amount: u256);

    // Queries
    fn get_market(self: @TContractState, match_id: u64) -> Market;
    fn get_match_count(self: @TContractState) -> u64;
    fn get_pool_value(self: @TContractState, match_id: u64) -> u256;
}

#[starknet::contract]
pub mod PredictionMarket {
    use openzeppelin_access::ownable::OwnableComponent;
    use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{
        ContractAddress, get_caller_address, get_contract_address, get_block_timestamp,
        get_block_number, ClassHash, syscalls::deploy_syscall, syscalls::get_block_hash_syscall
    };
    use super::{
        IPredictionMarket, Market, MarketStatus, SportType,
    };
    use crate::outcome_token::{IOutcomeTokenDispatcher, IOutcomeTokenDispatcherTrait};

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    // STRK token on Sepolia testnet
    pub const STRK_TOKEN: felt252 =
        0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d;

    // Fee: 0.3% = 30 basis points (30/10000)
    pub const FEE_BPS: u256 = 30;
    pub const BPS_DENOMINATOR: u256 = 10000;

    #[storage]
    struct Storage {
        markets: Map<u64, Market>,
        match_count: u64,
        outcome_token_class_hash: ClassHash,
        // LP tokens: (match_id, provider) => lp_token_balance
        lp_balances: Map<(u64, ContractAddress), u256>,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        MarketCreated: MarketCreated,
        LiquidityAdded: LiquidityAdded,
        LiquidityRemoved: LiquidityRemoved,
        OutcomePurchased: OutcomePurchased,
        OutcomeSold: OutcomeSold,
        FirstHalfRevealed: FirstHalfRevealed,
        MatchSettled: MatchSettled,
        TokensRedeemed: TokensRedeemed,
    }

    #[derive(Drop, starknet::Event)]
    pub struct MarketCreated {
        #[key]
        pub match_id: u64,
        pub team_a_name: ByteArray,
        pub team_b_name: ByteArray,
        pub team_a_token: ContractAddress,
        pub team_b_token: ContractAddress,
        pub initial_liquidity: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct LiquidityAdded {
        #[key]
        pub match_id: u64,
        #[key]
        pub provider: ContractAddress,
        pub amount: u256,
        pub lp_tokens_minted: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct LiquidityRemoved {
        #[key]
        pub match_id: u64,
        #[key]
        pub provider: ContractAddress,
        pub lp_tokens_burned: u256,
        pub amount_returned: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct OutcomePurchased {
        #[key]
        pub match_id: u64,
        #[key]
        pub buyer: ContractAddress,
        pub outcome: u8,
        pub amount_in: u256,
        pub fee_collected: u256,
        pub tokens_out: u256,
        pub new_price: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct OutcomeSold {
        #[key]
        pub match_id: u64,
        #[key]
        pub seller: ContractAddress,
        pub outcome: u8,
        pub tokens_in: u256,
        pub fee_collected: u256,
        pub amount_out: u256,
        pub new_price: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct FirstHalfRevealed {
        #[key]
        pub match_id: u64,
        pub team_a_score: u32,
        pub team_b_score: u32,
    }

    #[derive(Drop, starknet::Event)]
    pub struct MatchSettled {
        #[key]
        pub match_id: u64,
        pub final_team_a_score: u32,
        pub final_team_b_score: u32,
        pub winner: u8,
    }

    #[derive(Drop, starknet::Event)]
    pub struct TokensRedeemed {
        #[key]
        pub match_id: u64,
        #[key]
        pub redeemer: ContractAddress,
        pub amount: u256,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        outcome_token_class_hash: ClassHash,
    ) {
        self.ownable.initializer(owner);
        self.outcome_token_class_hash.write(outcome_token_class_hash);
        self.match_count.write(0);
    }

    #[abi(embed_v0)]
    impl PredictionMarketImpl of IPredictionMarket<ContractState> {
        fn create_market(
            ref self: ContractState,
            team_a_name: ByteArray,
            team_b_name: ByteArray,
            sport_type: SportType,
            initial_liquidity: u256,
            pre_match_duration: u64,
            halftime_duration: u64,
        ) -> u64 {
            assert(initial_liquidity > 0, 'Liquidity must be > 0');

            let match_id = self.match_count.read();
            let now = get_block_timestamp();
            let caller = get_caller_address();

            // Deploy outcome tokens
            let team_a_token = self._deploy_outcome_token(
                match_id,
                0,
                format!("{} Wins", team_a_name),
                format!("{}WIN", team_a_name.clone())
            );

            let team_b_token = self._deploy_outcome_token(
                match_id,
                1,
                format!("{} Wins", team_b_name),
                format!("{}WIN", team_b_name.clone())
            );

            // Initialize CPMM with equal reserves (50/50 odds)
            let half_liquidity = initial_liquidity / 2;
            let k = half_liquidity * half_liquidity;

            // Transfer initial liquidity from creator
            let strk_token: ContractAddress = STRK_TOKEN.try_into().unwrap();
            let strk = IERC20Dispatcher { contract_address: strk_token };
            strk.transfer_from(caller, get_contract_address(), initial_liquidity);

            // First LP gets LP tokens = initial_liquidity (1:1 ratio at start)
            let lp_tokens_minted = initial_liquidity;

            // Create market
            let market = Market {
                match_id,
                sport_type,
                team_a_name: team_a_name.clone(),
                team_b_name: team_b_name.clone(),
                team_a_token,
                team_b_token,
                team_a_reserve: half_liquidity,
                team_b_reserve: half_liquidity,
                k,
                first_half_team_a: 0,
                first_half_team_b: 0,
                second_half_team_a: 0,
                second_half_team_b: 0,
                pre_match_end_time: now + pre_match_duration,
                halftime_end_time: now + pre_match_duration + halftime_duration,
                status: MarketStatus::PreMatchTrading,
                winning_outcome: 2, // 2 = not yet determined
                total_lp_tokens: lp_tokens_minted,
                accumulated_fees: 0,
                initial_pool_value: initial_liquidity,
            };

            self.markets.write(match_id, market);
            self.match_count.write(match_id + 1);

            // Record LP tokens for creator
            self.lp_balances.write((match_id, caller), lp_tokens_minted);

            self.emit(MarketCreated {
                match_id,
                team_a_name,
                team_b_name,
                team_a_token,
                team_b_token,
                initial_liquidity,
            });

            self.emit(LiquidityAdded {
                match_id,
                provider: caller,
                amount: initial_liquidity,
                lp_tokens_minted,
            });

            match_id
        }

        fn add_liquidity(ref self: ContractState, match_id: u64, amount: u256) -> u256 {
            let mut market = self.markets.read(match_id);
            let caller = get_caller_address();

            // Can only add liquidity during trading periods
            assert(
                market.status == MarketStatus::PreMatchTrading
                || market.status == MarketStatus::HalftimeTrading,
                'Cannot add liquidity now'
            );
            assert(amount > 0, 'Amount must be > 0');

            // Calculate current pool value (reserves + fees)
            let current_pool_value = market.team_a_reserve + market.team_b_reserve + market.accumulated_fees;

            // Calculate LP tokens to mint based on current pool value
            // LP tokens = (amount / current_pool_value) * total_lp_tokens
            // This ensures late LPs don't dilute early LPs
            let lp_tokens_to_mint = (amount * market.total_lp_tokens) / current_pool_value;

            // Transfer STRK from provider
            let strk_token: ContractAddress = STRK_TOKEN.try_into().unwrap();
            let strk = IERC20Dispatcher { contract_address: strk_token };
            strk.transfer_from(caller, get_contract_address(), amount);

            // Add to reserves proportionally (maintain current ratio)
            let total_reserve = market.team_a_reserve + market.team_b_reserve;
            let team_a_addition = (amount * market.team_a_reserve) / total_reserve;
            let team_b_addition = amount - team_a_addition;

            market.team_a_reserve = market.team_a_reserve + team_a_addition;
            market.team_b_reserve = market.team_b_reserve + team_b_addition;
            market.k = market.team_a_reserve * market.team_b_reserve;
            market.total_lp_tokens = market.total_lp_tokens + lp_tokens_to_mint;

            self.markets.write(match_id, market);

            // Update LP balance
            let current_balance = self.lp_balances.read((match_id, caller));
            self.lp_balances.write((match_id, caller), current_balance + lp_tokens_to_mint);

            self.emit(LiquidityAdded {
                match_id,
                provider: caller,
                amount,
                lp_tokens_minted: lp_tokens_to_mint,
            });

            lp_tokens_to_mint
        }

        fn remove_liquidity(ref self: ContractState, match_id: u64, lp_tokens: u256) -> u256 {
            let mut market = self.markets.read(match_id);
            let caller = get_caller_address();

            // Can only remove liquidity after settlement
            assert(market.status == MarketStatus::Settled, 'Wait for settlement');

            let lp_balance = self.lp_balances.read((match_id, caller));
            assert(lp_tokens <= lp_balance, 'Insufficient LP tokens');

            // Calculate share of pool
            // LP share = lp_tokens / total_lp_tokens
            // Amount to return = LP share * (remaining pool after payouts + accumulated fees)
            let strk_token: ContractAddress = STRK_TOKEN.try_into().unwrap();
            let strk = IERC20Dispatcher { contract_address: strk_token };
            let contract_balance = strk.balance_of(get_contract_address());

            // LP gets proportional share of remaining contract balance
            let amount_to_return = (lp_tokens * contract_balance) / market.total_lp_tokens;

            // Update state
            market.total_lp_tokens = market.total_lp_tokens - lp_tokens;
            self.markets.write(match_id, market);

            self.lp_balances.write((match_id, caller), lp_balance - lp_tokens);

            // Transfer STRK to provider
            strk.transfer(caller, amount_to_return);

            self.emit(LiquidityRemoved {
                match_id,
                provider: caller,
                lp_tokens_burned: lp_tokens,
                amount_returned: amount_to_return,
            });

            amount_to_return
        }

        fn get_lp_balance(self: @ContractState, match_id: u64, provider: ContractAddress) -> u256 {
            self.lp_balances.read((match_id, provider))
        }

        fn get_lp_value(self: @ContractState, match_id: u64, provider: ContractAddress) -> u256 {
            let market = self.markets.read(match_id);
            let lp_balance = self.lp_balances.read((match_id, provider));

            if market.total_lp_tokens == 0 {
                return 0;
            }

            // Current pool value
            let pool_value = market.team_a_reserve + market.team_b_reserve + market.accumulated_fees;

            // LP's share of pool
            (lp_balance * pool_value) / market.total_lp_tokens
        }

        fn buy_outcome(
            ref self: ContractState,
            match_id: u64,
            outcome: u8,
            max_amount_in: u256
        ) -> u256 {
            let mut market = self.markets.read(match_id);

            // Check trading is open
            assert(
                market.status == MarketStatus::PreMatchTrading
                || market.status == MarketStatus::HalftimeTrading,
                'Trading not open'
            );

            assert(outcome == 0 || outcome == 1, 'Invalid outcome');

            // Calculate fee (0.3%)
            let fee = (max_amount_in * FEE_BPS) / BPS_DENOMINATOR;
            let amount_after_fee = max_amount_in - fee;

            // Calculate tokens out using CPMM formula (with amount after fee)
            let (amount_in, tokens_out) = if outcome == 0 {
                self._calculate_buy_team_a(market.team_a_reserve, market.team_b_reserve, market.k, amount_after_fee)
            } else {
                self._calculate_buy_team_b(market.team_a_reserve, market.team_b_reserve, market.k, amount_after_fee)
            };

            // Transfer STRK from user (full amount including fee)
            let strk_token: ContractAddress = STRK_TOKEN.try_into().unwrap();
            let strk = IERC20Dispatcher { contract_address: strk_token };
            strk.transfer_from(get_caller_address(), get_contract_address(), max_amount_in);

            // Update reserves (only amount_after_fee goes to reserves)
            if outcome == 0 {
                market.team_b_reserve = market.team_b_reserve + amount_in;
                market.team_a_reserve = market.k / market.team_b_reserve;
            } else {
                market.team_a_reserve = market.team_a_reserve + amount_in;
                market.team_b_reserve = market.k / market.team_a_reserve;
            }

            // Accumulate fees for LPs
            market.accumulated_fees = market.accumulated_fees + fee;

            // Mint outcome tokens to user
            let token_address = if outcome == 0 { market.team_a_token } else { market.team_b_token };
            let token = IOutcomeTokenDispatcher { contract_address: token_address };
            token.mint(get_caller_address(), tokens_out);

            // Save updated market
            self.markets.write(match_id, market);

            // Get new price
            let new_price = self.get_current_price(match_id, outcome);

            self.emit(OutcomePurchased {
                match_id,
                buyer: get_caller_address(),
                outcome,
                amount_in: max_amount_in,
                fee_collected: fee,
                tokens_out,
                new_price,
            });

            tokens_out
        }

        fn sell_outcome(
            ref self: ContractState,
            match_id: u64,
            outcome: u8,
            tokens_in: u256
        ) -> u256 {
            let mut market = self.markets.read(match_id);

            // Check trading is open
            assert(
                market.status == MarketStatus::PreMatchTrading
                || market.status == MarketStatus::HalftimeTrading,
                'Trading not open'
            );

            assert(outcome == 0 || outcome == 1, 'Invalid outcome');

            // Calculate amount out using CPMM formula
            let gross_amount_out = if outcome == 0 {
                self._calculate_sell_team_a(market.team_a_reserve, market.team_b_reserve, market.k, tokens_in)
            } else {
                self._calculate_sell_team_b(market.team_a_reserve, market.team_b_reserve, market.k, tokens_in)
            };

            // Calculate fee (0.3%)
            let fee = (gross_amount_out * FEE_BPS) / BPS_DENOMINATOR;
            let amount_out = gross_amount_out - fee;

            // Burn user's outcome tokens
            let token_address = if outcome == 0 { market.team_a_token } else { market.team_b_token };
            let token = IOutcomeTokenDispatcher { contract_address: token_address };
            token.burn(get_caller_address(), tokens_in);

            // Update reserves
            if outcome == 0 {
                market.team_a_reserve = market.team_a_reserve + tokens_in;
                market.team_b_reserve = market.k / market.team_a_reserve;
            } else {
                market.team_b_reserve = market.team_b_reserve + tokens_in;
                market.team_a_reserve = market.k / market.team_b_reserve;
            }

            // Accumulate fees for LPs
            market.accumulated_fees = market.accumulated_fees + fee;

            // Transfer STRK to user (minus fee)
            let strk_token: ContractAddress = STRK_TOKEN.try_into().unwrap();
            let strk = IERC20Dispatcher { contract_address: strk_token };
            strk.transfer(get_caller_address(), amount_out);

            // Save updated market
            self.markets.write(match_id, market);

            // Get new price
            let new_price = self.get_current_price(match_id, outcome);

            self.emit(OutcomeSold {
                match_id,
                seller: get_caller_address(),
                outcome,
                tokens_in,
                fee_collected: fee,
                amount_out,
                new_price,
            });

            amount_out
        }

        fn get_buy_price(
            self: @ContractState,
            match_id: u64,
            outcome: u8,
            amount_in: u256
        ) -> u256 {
            let market = self.markets.read(match_id);

            // Account for fee
            let amount_after_fee = amount_in - (amount_in * FEE_BPS) / BPS_DENOMINATOR;

            let (_, tokens_out) = if outcome == 0 {
                self._calculate_buy_team_a(market.team_a_reserve, market.team_b_reserve, market.k, amount_after_fee)
            } else {
                self._calculate_buy_team_b(market.team_a_reserve, market.team_b_reserve, market.k, amount_after_fee)
            };

            tokens_out
        }

        fn get_sell_price(
            self: @ContractState,
            match_id: u64,
            outcome: u8,
            tokens_in: u256
        ) -> u256 {
            let market = self.markets.read(match_id);

            let gross_out = if outcome == 0 {
                self._calculate_sell_team_a(market.team_a_reserve, market.team_b_reserve, market.k, tokens_in)
            } else {
                self._calculate_sell_team_b(market.team_a_reserve, market.team_b_reserve, market.k, tokens_in)
            };

            // Subtract fee
            gross_out - (gross_out * FEE_BPS) / BPS_DENOMINATOR
        }

        fn get_current_price(self: @ContractState, match_id: u64, outcome: u8) -> u256 {
            let market = self.markets.read(match_id);
            let total_reserve = market.team_a_reserve + market.team_b_reserve;

            if outcome == 0 {
                // Price of Team A = team_b_reserve / total_reserve
                // Multiply by 1e18 for precision
                (market.team_b_reserve * 1_000_000_000_000_000_000) / total_reserve
            } else {
                // Price of Team B = team_a_reserve / total_reserve
                (market.team_a_reserve * 1_000_000_000_000_000_000) / total_reserve
            }
        }

        fn reveal_first_half(ref self: ContractState, match_id: u64) {
            let mut market = self.markets.read(match_id);

            // Check timing
            assert(get_block_timestamp() >= market.pre_match_end_time, 'Pre-match period not ended');
            assert(market.status == MarketStatus::PreMatchTrading, 'Already revealed');

            // Generate first half scores using randomness
            let (team_a_score, team_b_score) = self._generate_half_scores(match_id, 1, market.sport_type);

            market.first_half_team_a = team_a_score;
            market.first_half_team_b = team_b_score;
            market.status = MarketStatus::HalftimeTrading;

            self.markets.write(match_id, market);

            self.emit(FirstHalfRevealed {
                match_id,
                team_a_score,
                team_b_score,
            });
        }

        fn reveal_final_scores(ref self: ContractState, match_id: u64) {
            let mut market = self.markets.read(match_id);

            // Check timing
            assert(get_block_timestamp() >= market.halftime_end_time, 'Halftime period not ended');
            assert(market.status == MarketStatus::HalftimeTrading, 'Not in halftime');

            // Generate second half scores
            let (team_a_score, team_b_score) = self._generate_half_scores(match_id, 2, market.sport_type);

            market.second_half_team_a = team_a_score;
            market.second_half_team_b = team_b_score;

            // Calculate final scores
            let final_team_a = market.first_half_team_a + market.second_half_team_a;
            let final_team_b = market.first_half_team_b + market.second_half_team_b;

            // Determine winner
            market.winning_outcome = if final_team_a > final_team_b {
                0 // Team A wins
            } else if final_team_b > final_team_a {
                1 // Team B wins
            } else {
                2 // Draw (both sides can redeem at 0.5:1)
            };

            market.status = MarketStatus::Settled;

            // Save winner before moving market
            let winner = market.winning_outcome;

            self.markets.write(match_id, market);

            self.emit(MatchSettled {
                match_id,
                final_team_a_score: final_team_a,
                final_team_b_score: final_team_b,
                winner,
            });
        }

        fn redeem_winning_tokens(ref self: ContractState, match_id: u64, amount: u256) {
            let market = self.markets.read(match_id);

            assert(market.status == MarketStatus::Settled, 'Match not settled');

            let caller = get_caller_address();
            let strk_token: ContractAddress = STRK_TOKEN.try_into().unwrap();
            let strk = IERC20Dispatcher { contract_address: strk_token };

            if market.winning_outcome == 2 {
                // Draw: both tokens can be redeemed at 0.5:1
                let token = IOutcomeTokenDispatcher { contract_address: market.team_a_token };
                token.burn(caller, amount);

                let payout = amount / 2;
                strk.transfer(caller, payout);
            } else {
                // Clear winner: redeem winning tokens at 1:1
                let winning_token = if market.winning_outcome == 0 {
                    market.team_a_token
                } else {
                    market.team_b_token
                };

                let token = IOutcomeTokenDispatcher { contract_address: winning_token };
                token.burn(caller, amount);

                strk.transfer(caller, amount);
            }

            self.emit(TokensRedeemed {
                match_id,
                redeemer: caller,
                amount,
            });
        }

        fn get_market(self: @ContractState, match_id: u64) -> Market {
            self.markets.read(match_id)
        }

        fn get_match_count(self: @ContractState) -> u64 {
            self.match_count.read()
        }

        fn get_pool_value(self: @ContractState, match_id: u64) -> u256 {
            let market = self.markets.read(match_id);
            market.team_a_reserve + market.team_b_reserve + market.accumulated_fees
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _deploy_outcome_token(
            ref self: ContractState,
            match_id: u64,
            outcome: u8,
            name: ByteArray,
            symbol: ByteArray,
        ) -> ContractAddress {
            let mut constructor_calldata = ArrayTrait::new();
            match_id.serialize(ref constructor_calldata);
            outcome.serialize(ref constructor_calldata);
            name.serialize(ref constructor_calldata);
            symbol.serialize(ref constructor_calldata);
            get_contract_address().serialize(ref constructor_calldata);

            let (address, _) = deploy_syscall(
                self.outcome_token_class_hash.read(),
                0, // salt
                constructor_calldata.span(),
                false
            ).unwrap();

            address
        }

        fn _calculate_buy_team_a(
            self: @ContractState,
            team_a_reserve: u256,
            team_b_reserve: u256,
            k: u256,
            max_amount_in: u256,
        ) -> (u256, u256) {
            let new_team_b_reserve = team_b_reserve + max_amount_in;
            let new_team_a_reserve = k / new_team_b_reserve;
            let tokens_out = team_a_reserve - new_team_a_reserve;

            (max_amount_in, tokens_out)
        }

        fn _calculate_buy_team_b(
            self: @ContractState,
            team_a_reserve: u256,
            team_b_reserve: u256,
            k: u256,
            max_amount_in: u256,
        ) -> (u256, u256) {
            let new_team_a_reserve = team_a_reserve + max_amount_in;
            let new_team_b_reserve = k / new_team_a_reserve;
            let tokens_out = team_b_reserve - new_team_b_reserve;

            (max_amount_in, tokens_out)
        }

        fn _calculate_sell_team_a(
            self: @ContractState,
            team_a_reserve: u256,
            team_b_reserve: u256,
            k: u256,
            tokens_in: u256,
        ) -> u256 {
            let new_team_a_reserve = team_a_reserve + tokens_in;
            let new_team_b_reserve = k / new_team_a_reserve;
            let amount_out = team_b_reserve - new_team_b_reserve;

            amount_out
        }

        fn _calculate_sell_team_b(
            self: @ContractState,
            team_a_reserve: u256,
            team_b_reserve: u256,
            k: u256,
            tokens_in: u256,
        ) -> u256 {
            let new_team_b_reserve = team_b_reserve + tokens_in;
            let new_team_a_reserve = k / new_team_b_reserve;
            let amount_out = team_a_reserve - new_team_a_reserve;

            amount_out
        }

        fn _generate_half_scores(
            self: @ContractState,
            match_id: u64,
            half: u8,
            sport_type: SportType,
        ) -> (u32, u32) {
            let block_num = get_block_number();
            let block_hash: u256 = get_block_hash_syscall(block_num - 1).unwrap().into();

            let seed = block_hash + match_id.into() + half.into();

            let (max_score_a, max_score_b) = match sport_type {
                SportType::Football => (5, 5),
                SportType::Basketball => (60, 60),
            };

            let team_a_score = (seed % (max_score_a + 1).into()).try_into().unwrap();
            let team_b_score = ((seed / 1000) % (max_score_b + 1).into()).try_into().unwrap();

            (team_a_score, team_b_score)
        }
    }
}
