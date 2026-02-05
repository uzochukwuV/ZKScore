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

    // Stats
    pub total_liquidity: u256,
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
}

#[starknet::contract]
pub mod PredictionMarket {
    use core::num::traits::Zero;
    use openzeppelin_access::ownable::OwnableComponent;
    use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{
        ContractAddress, get_caller_address, get_contract_address, get_block_timestamp,
        get_block_number, ClassHash, syscalls::deploy_syscall
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

    #[storage]
    struct Storage {
        markets: Map<u64, Market>,
        match_count: u64,
        outcome_token_class_hash: ClassHash,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        MarketCreated: MarketCreated,
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
    pub struct OutcomePurchased {
        #[key]
        pub match_id: u64,
        #[key]
        pub buyer: ContractAddress,
        pub outcome: u8,
        pub amount_in: u256,
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
            self.ownable.assert_only_owner();

            let match_id = self.match_count.read();
            let now = get_block_timestamp();

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

            // Transfer initial liquidity from owner
            let strk_token: ContractAddress = STRK_TOKEN.try_into().unwrap();
            let strk = IERC20Dispatcher { contract_address: strk_token };
            strk.transfer_from(get_caller_address(), get_contract_address(), initial_liquidity);

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
                total_liquidity: initial_liquidity,
            };

            self.markets.write(match_id, market);
            self.match_count.write(match_id + 1);

            self.emit(MarketCreated {
                match_id,
                team_a_name,
                team_b_name,
                team_a_token,
                team_b_token,
                initial_liquidity,
            });

            match_id
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

            // Calculate tokens out using CPMM formula
            let (amount_in, tokens_out) = if outcome == 0 {
                // Buying Team A tokens
                self._calculate_buy_team_a(market.team_a_reserve, market.team_b_reserve, market.k, max_amount_in)
            } else {
                // Buying Team B tokens
                self._calculate_buy_team_b(market.team_a_reserve, market.team_b_reserve, market.k, max_amount_in)
            };

            assert(amount_in <= max_amount_in, 'Slippage exceeded');

            // Transfer STRK from user
            let strk_token: ContractAddress = STRK_TOKEN.try_into().unwrap();
            let strk = IERC20Dispatcher { contract_address: strk_token };
            strk.transfer_from(get_caller_address(), get_contract_address(), amount_in);

            // Update reserves
            if outcome == 0 {
                market.team_b_reserve = market.team_b_reserve + amount_in;
                market.team_a_reserve = market.k / market.team_b_reserve;
            } else {
                market.team_a_reserve = market.team_a_reserve + amount_in;
                market.team_b_reserve = market.k / market.team_a_reserve;
            }

            market.total_liquidity = market.total_liquidity + amount_in;

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
                amount_in,
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
            let amount_out = if outcome == 0 {
                // Selling Team A tokens
                self._calculate_sell_team_a(market.team_a_reserve, market.team_b_reserve, market.k, tokens_in)
            } else {
                // Selling Team B tokens
                self._calculate_sell_team_b(market.team_a_reserve, market.team_b_reserve, market.k, tokens_in)
            };

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

            market.total_liquidity = market.total_liquidity - amount_out;

            // Transfer STRK to user
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

            let (_, tokens_out) = if outcome == 0 {
                self._calculate_buy_team_a(market.team_a_reserve, market.team_b_reserve, market.k, amount_in)
            } else {
                self._calculate_buy_team_b(market.team_a_reserve, market.team_b_reserve, market.k, amount_in)
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

            if outcome == 0 {
                self._calculate_sell_team_a(market.team_a_reserve, market.team_b_reserve, market.k, tokens_in)
            } else {
                self._calculate_sell_team_b(market.team_a_reserve, market.team_b_reserve, market.k, tokens_in)
            }
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

            self.markets.write(match_id, market);

            self.emit(MatchSettled {
                match_id,
                final_team_a_score: final_team_a,
                final_team_b_score: final_team_b,
                winner: market.winning_outcome,
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
                // User can redeem either token type
                // For simplicity, assume they're redeeming Team A tokens
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
            // When buying Team A tokens:
            // - We add STRK to team_b_reserve
            // - We remove Team A tokens from team_a_reserve
            // Formula: new_team_b_reserve = team_b_reserve + amount_in
            //          new_team_a_reserve = k / new_team_b_reserve
            //          tokens_out = team_a_reserve - new_team_a_reserve

            // We need to find amount_in that satisfies the formula
            // For simplicity, use max_amount_in
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
            // When selling Team A tokens:
            // - We add tokens to team_a_reserve
            // - We remove STRK from team_b_reserve
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
            half: u8, // 1 = first half, 2 = second half
            sport_type: SportType,
        ) -> (u32, u32) {
            // Use block hash as source of randomness
            // In production, would use Starknet VRF or Pragma randomness
            let block_num = get_block_number();
            let block_hash: u256 = starknet::get_block_hash_syscall(block_num - 1).unwrap().into();

            // Combine with match_id and half for unique seed
            let seed = block_hash + match_id.into() + half.into();

            // Generate scores based on sport type
            let (max_score_a, max_score_b) = match sport_type {
                SportType::Football => (5, 5),      // 0-5 goals per half
                SportType::Basketball => (60, 60),  // 30-60 points per half
            };

            // Simple pseudo-random score generation
            // Team A score: seed % (max_score + 1)
            let team_a_score = (seed % (max_score_a + 1).into()).try_into().unwrap();

            // Team B score: (seed / 1000) % (max_score + 1)
            let team_b_score = ((seed / 1000) % (max_score_b + 1).into()).try_into().unwrap();

            (team_a_score, team_b_score)
        }
    }
}
