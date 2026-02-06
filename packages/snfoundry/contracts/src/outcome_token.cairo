use starknet::ContractAddress;

#[starknet::interface]
pub trait IOutcomeToken<TContractState> {
    fn mint(ref self: TContractState, to: ContractAddress, amount: u256);
    fn burn(ref self: TContractState, from: ContractAddress, amount: u256);
    fn match_id(self: @TContractState) -> u64;
    fn outcome(self: @TContractState) -> u8;
}

#[starknet::contract]
pub mod OutcomeToken {
    use openzeppelin_token::erc20::{ERC20Component, ERC20HooksEmptyImpl};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{ContractAddress, get_caller_address};
    use super::IOutcomeToken;

    component!(path: ERC20Component, storage: erc20, event: ERC20Event);

    // ERC20 Mixin
    #[abi(embed_v0)]
    impl ERC20MixinImpl = ERC20Component::ERC20MixinImpl<ContractState>;
    impl ERC20InternalImpl = ERC20Component::InternalImpl<ContractState>;

    // Required: configure ERC20 immutable settings
    impl ERC20ImmutableConfig of ERC20Component::ImmutableConfig {
        const DECIMALS: u8 = 18;
    }

    #[storage]
    struct Storage {
        match_id: u64,
        outcome: u8, // 0 = Team A, 1 = Team B
        market_contract: ContractAddress,
        #[substorage(v0)]
        erc20: ERC20Component::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ERC20Event: ERC20Component::Event,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        match_id: u64,
        outcome: u8,
        name: ByteArray,
        symbol: ByteArray,
        market_contract: ContractAddress,
    ) {
        self.match_id.write(match_id);
        self.outcome.write(outcome);
        self.market_contract.write(market_contract);
        self.erc20.initializer(name, symbol);
    }

    #[abi(embed_v0)]
    impl OutcomeTokenImpl of IOutcomeToken<ContractState> {
        fn mint(ref self: ContractState, to: ContractAddress, amount: u256) {
            // Only market contract can mint
            assert(get_caller_address() == self.market_contract.read(), 'Only market can mint');
            self.erc20.mint(to, amount);
        }

        fn burn(ref self: ContractState, from: ContractAddress, amount: u256) {
            // Only market contract can burn
            assert(get_caller_address() == self.market_contract.read(), 'Only market can burn');
            self.erc20.burn(from, amount);
        }

        fn match_id(self: @ContractState) -> u64 {
            self.match_id.read()
        }

        fn outcome(self: @ContractState) -> u8 {
            self.outcome.read()
        }
    }
}
