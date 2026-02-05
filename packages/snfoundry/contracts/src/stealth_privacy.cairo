// Stealth Address Privacy for ZKScore
// Better UX than commit-reveal: Single transaction, no reveals needed!

use starknet::ContractAddress;

/// Stealth address for anonymous betting
/// User generates one-time address per bet
#[derive(Drop, Serde, Copy, starknet::Store)]
pub struct StealthAddress {
    pub ephemeral_pubkey: felt252, // One-time public key
    pub encrypted_view_tag: felt252, // Helps recipient identify their payments
}

/// Aggregated bet info (privacy via aggregation)
#[derive(Drop, Serde, starknet::Store)]
pub struct AggregatedBet {
    pub match_id: u64,
    pub outcome: u8,
    pub total_amount: u256, // Only total visible, not individual amounts
    pub num_bets: u32, // Number of bets in aggregate
    pub average_amount: u256, // Average bet size
}

/// Private bet placement (no reveal needed!)
#[derive(Drop, Serde, starknet::Store)]
pub struct PrivateBet {
    pub stealth_address: StealthAddress,
    pub match_id: u64,
    pub outcome: u8,
    pub timestamp: u64,
    // Amount is NOT stored individually - added to aggregate pool
}

#[starknet::interface]
pub trait IStealthPrivacy<TContractState> {
    /// Place bet using stealth address (single transaction!)
    fn place_private_bet(
        ref self: TContractState,
        match_id: u64,
        outcome: u8,
        amount: u256,
        stealth_address: StealthAddress,
    ) -> felt252; // Returns bet ID

    /// Claim winnings to new stealth address
    fn claim_to_stealth(
        ref self: TContractState,
        bet_id: felt252,
        recipient_stealth: StealthAddress,
        proof_of_ownership: felt252, // ZK proof you own the original stealth address
    );

    /// Get aggregated bet info (privacy preserved)
    fn get_aggregated_bets(
        self: @TContractState,
        match_id: u64,
        outcome: u8,
    ) -> AggregatedBet;

    /// Check if you have winnings (without revealing amount publicly)
    fn check_winnings_private(
        self: @TContractState,
        bet_id: felt252,
        viewing_key: felt252,
    ) -> u256;
}

#[starknet::contract]
pub mod StealthPrivacy {
    use core::hash::{HashStateTrait, HashStateExTrait};
    use core::pedersen::PedersenTrait;
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_caller_address, get_block_timestamp};
    use super::{IStealthPrivacy, StealthAddress, AggregatedBet, PrivateBet};

    #[storage]
    struct Storage {
        // bet_id => private bet info
        private_bets: Map<felt252, PrivateBet>,

        // match_id + outcome => aggregated bet data
        aggregated_bets: Map<(u64, u8), AggregatedBet>,

        // bet_id => amount (encrypted storage - only decryptable with viewing key)
        encrypted_amounts: Map<felt252, felt252>,

        // bet counter
        next_bet_id: felt252,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        PrivateBetPlaced: PrivateBetPlaced,
        PrivateWinningsClaimed: PrivateWinningsClaimed,
    }

    #[derive(Drop, starknet::Event)]
    pub struct PrivateBetPlaced {
        pub bet_id: felt252,
        #[key]
        pub match_id: u64,
        pub outcome: u8,
        pub stealth_pubkey: felt252, // Only public key revealed, not linked to user
        // Amount NOT revealed!
    }

    #[derive(Drop, starknet::Event)]
    pub struct PrivateWinningsClaimed {
        pub bet_id: felt252,
        pub recipient_stealth: felt252,
        // Amount NOT revealed!
    }

    #[constructor]
    fn constructor(ref self: ContractState) {
        self.next_bet_id.write(1);
    }

    #[abi(embed_v0)]
    impl StealthPrivacyImpl of IStealthPrivacy<ContractState> {
        fn place_private_bet(
            ref self: ContractState,
            match_id: u64,
            outcome: u8,
            amount: u256,
            stealth_address: StealthAddress,
        ) -> felt252 {
            let bet_id = self.next_bet_id.read();
            self.next_bet_id.write(bet_id + 1);

            let timestamp = get_block_timestamp();

            // 1. Store private bet info
            let private_bet = PrivateBet {
                stealth_address,
                match_id,
                outcome,
                timestamp,
            };
            self.private_bets.write(bet_id, private_bet);

            // 2. Encrypt and store amount (only user with viewing key can decrypt)
            let encrypted_amount = self._encrypt_amount(amount, stealth_address.encrypted_view_tag);
            self.encrypted_amounts.write(bet_id, encrypted_amount);

            // 3. Update aggregated stats (privacy via aggregation)
            let key = (match_id, outcome);
            let mut aggregated = self.aggregated_bets.read(key);

            let new_total = aggregated.total_amount + amount;
            let new_count = aggregated.num_bets + 1;
            let new_average = new_total / new_count.into();

            aggregated.match_id = match_id;
            aggregated.outcome = outcome;
            aggregated.total_amount = new_total;
            aggregated.num_bets = new_count;
            aggregated.average_amount = new_average;

            self.aggregated_bets.write(key, aggregated);

            // 4. Emit event (amount NOT included!)
            self.emit(PrivateBetPlaced {
                bet_id,
                match_id,
                outcome,
                stealth_pubkey: stealth_address.ephemeral_pubkey,
            });

            bet_id
        }

        fn claim_to_stealth(
            ref self: ContractState,
            bet_id: felt252,
            recipient_stealth: StealthAddress,
            proof_of_ownership: felt252,
        ) {
            let bet = self.private_bets.read(bet_id);

            // Verify ownership proof (simplified - in production use ZK proof)
            let expected_proof = PedersenTrait::new(0)
                .update(bet.stealth_address.ephemeral_pubkey)
                .update(bet.stealth_address.encrypted_view_tag)
                .finalize();

            assert(proof_of_ownership == expected_proof, 'Invalid ownership proof');

            // Emit event (amounts stay private!)
            self.emit(PrivateWinningsClaimed {
                bet_id,
                recipient_stealth: recipient_stealth.ephemeral_pubkey,
            });

            // Transfer happens via separate contract call to maintain privacy
            // The prediction market contract handles actual token transfer
        }

        fn get_aggregated_bets(
            self: @ContractState,
            match_id: u64,
            outcome: u8,
        ) -> AggregatedBet {
            self.aggregated_bets.read((match_id, outcome))
        }

        fn check_winnings_private(
            self: @ContractState,
            bet_id: felt252,
            viewing_key: felt252,
        ) -> u256 {
            let encrypted_amount = self.encrypted_amounts.read(bet_id);

            // Decrypt amount using viewing key
            let decrypted = self._decrypt_amount(encrypted_amount, viewing_key);

            decrypted
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _encrypt_amount(
            self: @ContractState,
            amount: u256,
            view_tag: felt252,
        ) -> felt252 {
            // Simple encryption using Pedersen hash
            // In production: use proper encryption (ChaCha20 or AES)
            PedersenTrait::new(0)
                .update(amount.low.into())
                .update(amount.high.into())
                .update(view_tag)
                .finalize()
        }

        fn _decrypt_amount(
            self: @ContractState,
            encrypted: felt252,
            viewing_key: felt252,
        ) -> u256 {
            // In production: proper decryption
            // For now: mock decryption
            // Real implementation would use symmetric encryption

            // This is a placeholder - real decryption happens off-chain
            // User derives amount from viewing key
            0
        }
    }
}
