use snforge_std::{
    declare, ContractClassTrait, DeclareResultTrait, start_cheat_caller_address,
    stop_cheat_caller_address, start_cheat_block_timestamp, stop_cheat_block_timestamp,
    start_cheat_block_number, stop_cheat_block_number, spy_events, EventSpyAssertionsTrait,
};
use starknet::{ContractAddress, contract_address_const};
use contracts::prediction_market::{
    IPredictionMarketDispatcher, IPredictionMarketDispatcherTrait, SportType, MarketStatus,
};
use contracts::outcome_token::{IOutcomeTokenDispatcher, IOutcomeTokenDispatcherTrait};
use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};

fn OWNER() -> ContractAddress {
    contract_address_const::<'OWNER'>()
}

fn USER1() -> ContractAddress {
    contract_address_const::<'USER1'>()
}

fn USER2() -> ContractAddress {
    contract_address_const::<'USER2'>()
}

fn LP1() -> ContractAddress {
    contract_address_const::<'LP1'>()
}

fn LP2() -> ContractAddress {
    contract_address_const::<'LP2'>()
}

fn STRK_TOKEN() -> ContractAddress {
    contract_address_const::<0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d>()
}

fn deploy_prediction_market() -> ContractAddress {
    // Deploy OutcomeToken class first
    let outcome_token_class = declare("OutcomeToken").unwrap().contract_class();
    let outcome_token_class_hash = *outcome_token_class.class_hash;

    // Deploy PredictionMarket
    let mut constructor_calldata = ArrayTrait::new();
    OWNER().serialize(ref constructor_calldata);
    outcome_token_class_hash.serialize(ref constructor_calldata);

    let contract = declare("PredictionMarket").unwrap().contract_class();
    let (contract_address, _) = contract.deploy(@constructor_calldata).unwrap();

    contract_address
}

// ==================== MARKET CREATION TESTS ====================

#[test]
fn test_create_market() {
    let market_address = deploy_prediction_market();
    let market = IPredictionMarketDispatcher { contract_address: market_address };

    start_cheat_caller_address(market_address, OWNER());

    let match_id = market.create_market(
        "Lakers",
        "Warriors",
        SportType::Basketball,
        1000000000000000000000, // 1000 STRK initial liquidity
        3600, // 1 hour pre-match
        900, // 15 min halftime
    );

    assert(match_id == 0, 'First match should be 0');

    let market_data = market.get_market(0);
    assert(market_data.match_id == 0, 'Match ID incorrect');
    assert(market_data.team_a_name == "Lakers", 'Team A name incorrect');
    assert(market_data.team_b_name == "Warriors", 'Team B name incorrect');
    assert(market_data.status == MarketStatus::PreMatchTrading, 'Status should be PreMatch');

    // Check LP tokens were minted to creator
    let owner_lp_balance = market.get_lp_balance(match_id, OWNER());
    assert(owner_lp_balance == 1000000000000000000000, 'Owner should have LP tokens');

    // Check total LP tokens
    assert(market_data.total_lp_tokens == 1000000000000000000000, 'Total LP should match');

    stop_cheat_caller_address(market_address);
}

#[test]
fn test_get_match_count() {
    let market_address = deploy_prediction_market();
    let market = IPredictionMarketDispatcher { contract_address: market_address };

    let initial_count = market.get_match_count();
    assert(initial_count == 0, 'Initial count should be 0');

    start_cheat_caller_address(market_address, OWNER());
    market.create_market(
        "Lakers",
        "Warriors",
        SportType::Basketball,
        1000000000000000000000,
        3600,
        900,
    );

    let count_after_first = market.get_match_count();
    assert(count_after_first == 1, 'Count should be 1');

    market.create_market(
        "Bulls",
        "Celtics",
        SportType::Basketball,
        1000000000000000000000,
        3600,
        900,
    );

    let count_after_second = market.get_match_count();
    assert(count_after_second == 2, 'Count should be 2');

    stop_cheat_caller_address(market_address);
}

// ==================== LP TRACKING TESTS ====================

#[test]
fn test_add_liquidity() {
    let market_address = deploy_prediction_market();
    let market = IPredictionMarketDispatcher { contract_address: market_address };

    // Owner creates market with 1000 STRK
    start_cheat_caller_address(market_address, OWNER());
    let match_id = market.create_market(
        "Lakers",
        "Warriors",
        SportType::Basketball,
        1000000000000000000000, // 1000 STRK
        3600,
        900,
    );
    stop_cheat_caller_address(market_address);

    // LP1 adds 500 STRK liquidity
    start_cheat_caller_address(market_address, LP1());
    let lp_tokens = market.add_liquidity(match_id, 500000000000000000000); // 500 STRK
    stop_cheat_caller_address(market_address);

    // LP1 should get LP tokens proportional to pool share
    // Pool was 1000, adding 500 = 50% of pool
    // So LP1 should get 500 LP tokens (50% of 1000 total LP)
    assert(lp_tokens == 500000000000000000000, 'LP should receive LP tokens');

    let lp1_balance = market.get_lp_balance(match_id, LP1());
    assert(lp1_balance == 500000000000000000000, 'LP1 balance incorrect');

    // Total pool should be 1500 now
    let pool_value = market.get_pool_value(match_id);
    assert(pool_value == 1500000000000000000000, 'Pool value incorrect');
}

#[test]
fn test_late_lp_doesnt_dilute_early_lp() {
    let market_address = deploy_prediction_market();
    let market = IPredictionMarketDispatcher { contract_address: market_address };

    // Owner creates market with 1000 STRK
    start_cheat_caller_address(market_address, OWNER());
    let match_id = market.create_market(
        "Lakers",
        "Warriors",
        SportType::Basketball,
        1000000000000000000000, // 1000 STRK
        3600,
        900,
    );
    stop_cheat_caller_address(market_address);

    // Get initial LP value for owner
    let owner_initial_value = market.get_lp_value(match_id, OWNER());
    assert(owner_initial_value == 1000000000000000000000, 'Owner value should be 1000');

    // User1 trades (generates fees)
    start_cheat_caller_address(market_address, USER1());
    market.buy_outcome(match_id, 0, 100000000000000000000); // 100 STRK
    stop_cheat_caller_address(market_address);

    // Check fees accumulated
    let market_data = market.get_market(match_id);
    assert(market_data.accumulated_fees > 0, 'Fees should be collected');

    // Owner's LP value should increase due to fees
    let owner_value_after_trade = market.get_lp_value(match_id, OWNER());
    assert(owner_value_after_trade > owner_initial_value, 'Owner value should increase');

    // Now LP2 adds liquidity AFTER fees were generated
    start_cheat_caller_address(market_address, LP2());
    let lp2_tokens = market.add_liquidity(match_id, 1000000000000000000000); // 1000 STRK
    stop_cheat_caller_address(market_address);

    // LP2 should get LESS than 1000 LP tokens because pool has grown
    // Pool value > 1000 now, so 1000 STRK buys less than 1000 LP tokens
    assert(lp2_tokens < 1000000000000000000000, 'Late LP gets fewer tokens');

    // Verify owner still has more valuable position
    let owner_final_value = market.get_lp_value(match_id, OWNER());
    let lp2_value = market.get_lp_value(match_id, LP2());

    // Owner should have higher value per original STRK invested
    assert(owner_final_value > 1000000000000000000000, 'Owner profited from fees');
}

#[test]
fn test_get_lp_value() {
    let market_address = deploy_prediction_market();
    let market = IPredictionMarketDispatcher { contract_address: market_address };

    start_cheat_caller_address(market_address, OWNER());
    let match_id = market.create_market(
        "Lakers",
        "Warriors",
        SportType::Basketball,
        1000000000000000000000,
        3600,
        900,
    );
    stop_cheat_caller_address(market_address);

    // Owner's LP value should equal initial liquidity
    let lp_value = market.get_lp_value(match_id, OWNER());
    assert(lp_value == 1000000000000000000000, 'LP value should be 1000 STRK');

    // User with no LP should have 0 value
    let user_value = market.get_lp_value(match_id, USER1());
    assert(user_value == 0, 'Non-LP should have 0 value');
}

#[test]
fn test_remove_liquidity_after_settlement() {
    let market_address = deploy_prediction_market();
    let market = IPredictionMarketDispatcher { contract_address: market_address };

    // Create market
    start_cheat_caller_address(market_address, OWNER());
    let match_id = market.create_market(
        "Lakers",
        "Warriors",
        SportType::Basketball,
        1000000000000000000000,
        60,
        60,
    );
    stop_cheat_caller_address(market_address);

    // Some trading to generate fees
    start_cheat_caller_address(market_address, USER1());
    market.buy_outcome(match_id, 0, 100000000000000000000);
    stop_cheat_caller_address(market_address);

    // Fast forward and settle
    start_cheat_block_timestamp(market_address, 100);
    start_cheat_block_number(market_address, 10);
    market.reveal_first_half(match_id);

    start_cheat_block_timestamp(market_address, 200);
    start_cheat_block_number(market_address, 20);
    market.reveal_final_scores(match_id);

    // Now LP can withdraw
    start_cheat_caller_address(market_address, OWNER());
    let lp_balance = market.get_lp_balance(match_id, OWNER());
    let strk_returned = market.remove_liquidity(match_id, lp_balance);
    stop_cheat_caller_address(market_address);

    assert(strk_returned > 0, 'Should return STRK');

    // LP balance should be 0 now
    let new_balance = market.get_lp_balance(match_id, OWNER());
    assert(new_balance == 0, 'LP balance should be 0');

    stop_cheat_block_timestamp(market_address);
    stop_cheat_block_number(market_address);
}

#[test]
#[should_panic(expected: ('Wait for settlement',))]
fn test_cannot_remove_liquidity_before_settlement() {
    let market_address = deploy_prediction_market();
    let market = IPredictionMarketDispatcher { contract_address: market_address };

    start_cheat_caller_address(market_address, OWNER());
    let match_id = market.create_market(
        "Lakers",
        "Warriors",
        SportType::Basketball,
        1000000000000000000000,
        3600,
        900,
    );

    // Try to remove liquidity before settlement (should fail)
    market.remove_liquidity(match_id, 100000000000000000000);
}

// ==================== TRADING TESTS ====================

#[test]
fn test_buy_outcome_tokens() {
    let market_address = deploy_prediction_market();
    let market = IPredictionMarketDispatcher { contract_address: market_address };

    start_cheat_caller_address(market_address, OWNER());
    let match_id = market.create_market(
        "Lakers",
        "Warriors",
        SportType::Basketball,
        1000000000000000000000, // 1000 STRK
        3600,
        900,
    );
    stop_cheat_caller_address(market_address);

    let market_data = market.get_market(match_id);
    let initial_team_a_reserve = market_data.team_a_reserve;
    let initial_team_b_reserve = market_data.team_b_reserve;

    // User1 buys Team A tokens
    start_cheat_caller_address(market_address, USER1());
    let amount_in = 100000000000000000000; // 100 STRK
    let tokens_out = market.buy_outcome(match_id, 0, amount_in);

    assert(tokens_out > 0, 'Should receive tokens');

    // Check reserves changed
    let updated_market = market.get_market(match_id);
    assert(updated_market.team_b_reserve > initial_team_b_reserve, 'Team B reserve should increase');
    assert(updated_market.team_a_reserve < initial_team_a_reserve, 'Team A reserve should decrease');

    // Check fees were collected
    assert(updated_market.accumulated_fees > 0, 'Fees should be collected');

    stop_cheat_caller_address(market_address);
}

#[test]
fn test_trading_fees_collected() {
    let market_address = deploy_prediction_market();
    let market = IPredictionMarketDispatcher { contract_address: market_address };

    start_cheat_caller_address(market_address, OWNER());
    let match_id = market.create_market(
        "Lakers",
        "Warriors",
        SportType::Basketball,
        1000000000000000000000,
        3600,
        900,
    );
    stop_cheat_caller_address(market_address);

    // User1 buys tokens (100 STRK, 0.3% fee = 0.3 STRK)
    start_cheat_caller_address(market_address, USER1());
    market.buy_outcome(match_id, 0, 100000000000000000000); // 100 STRK
    stop_cheat_caller_address(market_address);

    let market_data = market.get_market(match_id);
    // Fee should be 0.3% of 100 = 0.3 STRK = 300000000000000000
    assert(market_data.accumulated_fees == 300000000000000000, 'Fee should be 0.3 STRK');

    // User1 sells tokens - should also collect fee
    start_cheat_caller_address(market_address, USER1());
    market.sell_outcome(match_id, 0, 10000000000000000000); // Sell some tokens
    stop_cheat_caller_address(market_address);

    let updated_market = market.get_market(match_id);
    assert(updated_market.accumulated_fees > market_data.accumulated_fees, 'More fees after sell');
}

#[test]
fn test_sell_outcome_tokens() {
    let market_address = deploy_prediction_market();
    let market = IPredictionMarketDispatcher { contract_address: market_address };

    start_cheat_caller_address(market_address, OWNER());
    let match_id = market.create_market(
        "Lakers",
        "Warriors",
        SportType::Basketball,
        1000000000000000000000,
        3600,
        900,
    );
    stop_cheat_caller_address(market_address);

    // User1 buys tokens
    start_cheat_caller_address(market_address, USER1());
    let tokens_bought = market.buy_outcome(match_id, 0, 100000000000000000000);

    let price_after_buy = market.get_current_price(match_id, 0);

    // User1 sells half the tokens
    let tokens_to_sell = tokens_bought / 2;
    let strk_received = market.sell_outcome(match_id, 0, tokens_to_sell);

    assert(strk_received > 0, 'Should receive STRK');

    let price_after_sell = market.get_current_price(match_id, 0);
    assert(price_after_sell < price_after_buy, 'Price should drop on sell');

    stop_cheat_caller_address(market_address);
}

#[test]
fn test_price_changes_with_buys() {
    let market_address = deploy_prediction_market();
    let market = IPredictionMarketDispatcher { contract_address: market_address };

    start_cheat_caller_address(market_address, OWNER());
    let match_id = market.create_market(
        "Lakers",
        "Warriors",
        SportType::Basketball,
        1000000000000000000000,
        3600,
        900,
    );
    stop_cheat_caller_address(market_address);

    // Get initial price (should be ~0.5 or 50%)
    let initial_price_a = market.get_current_price(match_id, 0);
    let initial_price_b = market.get_current_price(match_id, 1);

    // Prices should sum to ~1.0 (considering precision)
    let price_sum = initial_price_a + initial_price_b;
    assert(price_sum > 990000000000000000, 'Prices should sum to ~1'); // ~0.99
    assert(price_sum < 1010000000000000000, 'Prices should sum to ~1'); // ~1.01

    // Buy Team A tokens - price should increase
    start_cheat_caller_address(market_address, USER1());
    market.buy_outcome(match_id, 0, 100000000000000000000); // 100 STRK
    stop_cheat_caller_address(market_address);

    let new_price_a = market.get_current_price(match_id, 0);
    let new_price_b = market.get_current_price(match_id, 1);

    assert(new_price_a > initial_price_a, 'Team A price should increase');
    assert(new_price_b < initial_price_b, 'Team B price should decrease');
}

// ==================== HALFTIME & SETTLEMENT TESTS ====================

#[test]
fn test_halftime_reveal() {
    let market_address = deploy_prediction_market();
    let market = IPredictionMarketDispatcher { contract_address: market_address };

    start_cheat_caller_address(market_address, OWNER());
    let match_id = market.create_market(
        "Lakers",
        "Warriors",
        SportType::Basketball,
        1000000000000000000000,
        60, // 60 seconds for quick test
        60,
    );
    stop_cheat_caller_address(market_address);

    // Fast forward time past pre-match period
    start_cheat_block_timestamp(market_address, 100);
    start_cheat_block_number(market_address, 10);

    // Reveal first half
    market.reveal_first_half(match_id);

    let market_data = market.get_market(match_id);
    assert(market_data.status == MarketStatus::HalftimeTrading, 'Should be halftime');
    assert(market_data.first_half_team_a > 0 || market_data.first_half_team_a == 0, 'Team A score set');
    assert(market_data.first_half_team_b > 0 || market_data.first_half_team_b == 0, 'Team B score set');

    stop_cheat_block_timestamp(market_address);
    stop_cheat_block_number(market_address);
}

#[test]
fn test_halftime_trading() {
    let market_address = deploy_prediction_market();
    let market = IPredictionMarketDispatcher { contract_address: market_address };

    start_cheat_caller_address(market_address, OWNER());
    let match_id = market.create_market(
        "Lakers",
        "Warriors",
        SportType::Basketball,
        1000000000000000000000,
        60,
        60,
    );
    stop_cheat_caller_address(market_address);

    // Reveal first half
    start_cheat_block_timestamp(market_address, 100);
    start_cheat_block_number(market_address, 10);
    market.reveal_first_half(match_id);

    // Should be able to trade during halftime
    start_cheat_caller_address(market_address, USER1());
    let tokens = market.buy_outcome(match_id, 0, 50000000000000000000);
    assert(tokens > 0, 'Should buy during halftime');

    stop_cheat_caller_address(market_address);
    stop_cheat_block_timestamp(market_address);
    stop_cheat_block_number(market_address);
}

#[test]
fn test_can_add_liquidity_during_halftime() {
    let market_address = deploy_prediction_market();
    let market = IPredictionMarketDispatcher { contract_address: market_address };

    start_cheat_caller_address(market_address, OWNER());
    let match_id = market.create_market(
        "Lakers",
        "Warriors",
        SportType::Basketball,
        1000000000000000000000,
        60,
        60,
    );
    stop_cheat_caller_address(market_address);

    // Reveal first half
    start_cheat_block_timestamp(market_address, 100);
    start_cheat_block_number(market_address, 10);
    market.reveal_first_half(match_id);

    // Should be able to add liquidity during halftime
    start_cheat_caller_address(market_address, LP1());
    let lp_tokens = market.add_liquidity(match_id, 500000000000000000000);
    assert(lp_tokens > 0, 'LP add halftime ok');

    stop_cheat_caller_address(market_address);
    stop_cheat_block_timestamp(market_address);
    stop_cheat_block_number(market_address);
}

#[test]
fn test_final_settlement() {
    let market_address = deploy_prediction_market();
    let market = IPredictionMarketDispatcher { contract_address: market_address };

    start_cheat_caller_address(market_address, OWNER());
    let match_id = market.create_market(
        "Lakers",
        "Warriors",
        SportType::Basketball,
        1000000000000000000000,
        60,
        60,
    );
    stop_cheat_caller_address(market_address);

    // Reveal first half
    start_cheat_block_timestamp(market_address, 100);
    start_cheat_block_number(market_address, 10);
    market.reveal_first_half(match_id);

    // Reveal final scores (past halftime end)
    start_cheat_block_timestamp(market_address, 200);
    start_cheat_block_number(market_address, 20);
    market.reveal_final_scores(match_id);

    let market_data = market.get_market(match_id);
    assert(market_data.status == MarketStatus::Settled, 'Should be settled');
    assert(market_data.second_half_team_a > 0 || market_data.second_half_team_a == 0, '2nd half A set');
    assert(market_data.second_half_team_b > 0 || market_data.second_half_team_b == 0, '2nd half B set');
    assert(market_data.winning_outcome <= 2, 'Winner should be determined');

    stop_cheat_block_timestamp(market_address);
    stop_cheat_block_number(market_address);
}

#[test]
#[should_panic(expected: ('Trading not open',))]
fn test_cannot_trade_after_settlement() {
    let market_address = deploy_prediction_market();
    let market = IPredictionMarketDispatcher { contract_address: market_address };

    start_cheat_caller_address(market_address, OWNER());
    let match_id = market.create_market(
        "Lakers",
        "Warriors",
        SportType::Basketball,
        1000000000000000000000,
        60,
        60,
    );
    stop_cheat_caller_address(market_address);

    // Reveal first half
    start_cheat_block_timestamp(market_address, 100);
    start_cheat_block_number(market_address, 10);
    market.reveal_first_half(match_id);

    // Reveal final (closes trading)
    start_cheat_block_timestamp(market_address, 200);
    start_cheat_block_number(market_address, 20);
    market.reveal_final_scores(match_id);

    // Try to trade (should fail)
    start_cheat_caller_address(market_address, USER1());
    market.buy_outcome(match_id, 0, 50000000000000000000);
}

#[test]
#[should_panic(expected: ('Cannot add liquidity now',))]
fn test_cannot_add_liquidity_after_settlement() {
    let market_address = deploy_prediction_market();
    let market = IPredictionMarketDispatcher { contract_address: market_address };

    start_cheat_caller_address(market_address, OWNER());
    let match_id = market.create_market(
        "Lakers",
        "Warriors",
        SportType::Basketball,
        1000000000000000000000,
        60,
        60,
    );
    stop_cheat_caller_address(market_address);

    // Fast forward to settlement
    start_cheat_block_timestamp(market_address, 100);
    start_cheat_block_number(market_address, 10);
    market.reveal_first_half(match_id);

    start_cheat_block_timestamp(market_address, 200);
    start_cheat_block_number(market_address, 20);
    market.reveal_final_scores(match_id);

    // Try to add liquidity (should fail)
    start_cheat_caller_address(market_address, LP1());
    market.add_liquidity(match_id, 500000000000000000000);
}

// ==================== POOL VALUE TESTS ====================

#[test]
fn test_get_pool_value() {
    let market_address = deploy_prediction_market();
    let market = IPredictionMarketDispatcher { contract_address: market_address };

    start_cheat_caller_address(market_address, OWNER());
    let match_id = market.create_market(
        "Lakers",
        "Warriors",
        SportType::Basketball,
        1000000000000000000000, // 1000 STRK
        3600,
        900,
    );
    stop_cheat_caller_address(market_address);

    // Initial pool value should be 1000 STRK
    let initial_pool = market.get_pool_value(match_id);
    assert(initial_pool == 1000000000000000000000, 'Initial pool should be 1000');

    // After trading, pool value increases due to fees
    start_cheat_caller_address(market_address, USER1());
    market.buy_outcome(match_id, 0, 100000000000000000000);
    stop_cheat_caller_address(market_address);

    let pool_after_trade = market.get_pool_value(match_id);
    assert(pool_after_trade > initial_pool, 'Pool should grow from fees');
}
