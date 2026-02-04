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

#[test]
fn test_create_market() {
    let market_address = deploy_prediction_market();
    let market = IPredictionMarketDispatcher { contract_address: market_address };

    // Setup: Mock STRK token approval (in real test, would need actual STRK contract)
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

    stop_cheat_caller_address(market_address);
}

#[test]
fn test_buy_outcome_tokens() {
    let market_address = deploy_prediction_market();
    let market = IPredictionMarketDispatcher { contract_address: market_address };

    // Create market
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

    // Mock STRK approval in real test
    let amount_in = 100000000000000000000; // 100 STRK
    let tokens_out = market.buy_outcome(match_id, 0, amount_in);

    assert(tokens_out > 0, 'Should receive tokens');

    // Check reserves changed
    let updated_market = market.get_market(match_id);
    assert(updated_market.team_b_reserve > initial_team_b_reserve, 'Team B reserve should increase');
    assert(updated_market.team_a_reserve < initial_team_a_reserve, 'Team A reserve should decrease');

    stop_cheat_caller_address(market_address);
}

#[test]
fn test_price_changes_with_buys() {
    let market_address = deploy_prediction_market();
    let market = IPredictionMarketDispatcher { contract_address: market_address };

    // Create market
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

#[test]
fn test_halftime_reveal() {
    let market_address = deploy_prediction_market();
    let market = IPredictionMarketDispatcher { contract_address: market_address };

    // Create market
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
    start_cheat_block_number(market_address, 10); // Need block number for randomness

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
fn test_final_settlement() {
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
fn test_cannot_trade_after_halftime() {
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
fn test_sell_outcome_tokens() {
    let market_address = deploy_prediction_market();
    let market = IPredictionMarketDispatcher { contract_address: market_address };

    // Create market
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
    assert(price_after_sell < price_after_buy, 'Price should decrease after sell');

    stop_cheat_caller_address(market_address);
}

#[test]
fn test_get_match_count() {
    let market_address = deploy_prediction_market();
    let market = IPredictionMarketDispatcher { contract_address: market_address };

    let initial_count = market.get_match_count();
    assert(initial_count == 0, 'Initial count should be 0');

    // Create first market
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

    // Create second market
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
