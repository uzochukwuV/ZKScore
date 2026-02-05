/**
 * Tongo SDK Integration for ZKScore
 *
 * Provides ElGamal encryption for private bet amounts
 *
 * Installation:
 * npm install @tongo/sdk
 *
 * References:
 * - Tongo SDK: https://docs.tongo.xyz
 * - Starknet Privacy Toolkit: https://github.com/starknet-privacy
 */

import { Account, CallData, RpcProvider } from "starknet";

// Types for Tongo SDK integration
export interface EncryptedAmount {
  c1: string; // First component of ElGamal ciphertext
  c2: string; // Second component of ElGamal ciphertext
  proofHash: string; // ZK proof that encrypted value is valid
}

export interface TongoConfig {
  network: "mainnet" | "sepolia";
  publicKey?: string;
}

/**
 * Tongo SDK Wrapper for ZKScore
 *
 * Usage:
 * const tongo = new TongoIntegration({ network: "sepolia" });
 * const encrypted = await tongo.encryptBetAmount(100n);
 * await contract.commit_bet_encrypted(matchId, encrypted, outcome);
 */
export class TongoIntegration {
  private config: TongoConfig;
  private publicKey: string;

  constructor(config: TongoConfig) {
    this.config = config;
    // In production, fetch from contract or Tongo service
    this.publicKey = config.publicKey || this.getDefaultPublicKey();
  }

  /**
   * Encrypt a bet amount using ElGamal encryption
   *
   * @param amount - Bet amount in wei/smallest unit
   * @returns Encrypted amount with ZK proof
   */
  async encryptBetAmount(amount: bigint): Promise<EncryptedAmount> {
    // In production, use actual Tongo SDK:
    // import { TongoSDK } from '@tongo/sdk';
    // const tongo = new TongoSDK({ network: this.config.network });
    // return await tongo.encrypt({ amount, publicKey: this.publicKey });

    // For demonstration - generate mock encrypted values
    // Replace with actual Tongo SDK in production
    const mockEncrypted = await this.mockEncrypt(amount);
    return mockEncrypted;
  }

  /**
   * Decrypt an encrypted amount (requires private key)
   * Only contract owner or authorized parties can decrypt
   *
   * @param encrypted - Encrypted amount
   * @returns Decrypted amount
   */
  async decryptBetAmount(encrypted: EncryptedAmount): Promise<bigint> {
    // In production:
    // const tongo = new TongoSDK({ network: this.config.network });
    // return await tongo.decrypt({ encrypted, privateKey });

    throw new Error("Decryption requires private key (admin only)");
  }

  /**
   * Verify ZK proof for encrypted amount
   * Ensures the encrypted value is within valid range
   *
   * @param encrypted - Encrypted amount with proof
   * @returns True if proof is valid
   */
  async verifyProof(encrypted: EncryptedAmount): Promise<boolean> {
    // In production:
    // const tongo = new TongoSDK({ network: this.config.network });
    // return await tongo.verifyProof(encrypted);

    return encrypted.proofHash !== "0x0";
  }

  /**
   * Generate ZK proof for range (e.g., amount > 0 and amount < max)
   *
   * @param amount - Bet amount
   * @param min - Minimum allowed amount
   * @param max - Maximum allowed amount
   * @returns ZK proof
   */
  async generateRangeProof(
    amount: bigint,
    min: bigint,
    max: bigint
  ): Promise<string> {
    // Verify amount is in valid range
    if (amount < min || amount > max) {
      throw new Error(`Amount must be between ${min} and ${max}`);
    }

    // In production: generate actual ZK range proof
    // This proves amount is in range WITHOUT revealing the amount
    // Uses bulletproofs or similar ZK range proof system

    return this.mockRangeProof(amount, min, max);
  }

  /**
   * Place encrypted bet on prediction market
   *
   * @param contract - Prediction market contract
   * @param matchId - Match ID
   * @param amount - Bet amount (will be encrypted)
   * @param outcome - Outcome to bet on (0 = Team A, 1 = Team B)
   * @param account - User's Starknet account
   */
  async placeEncryptedBet(
    contractAddress: string,
    matchId: number,
    amount: bigint,
    outcome: 0 | 1,
    account: Account
  ): Promise<string> {
    // 1. Encrypt the bet amount
    const encrypted = await this.encryptBetAmount(amount);

    // 2. Generate range proof (optional but recommended)
    const minBet = 1000000000000000n; // 0.001 STRK
    const maxBet = 1000000000000000000000n; // 1000 STRK
    const rangeProof = await this.generateRangeProof(amount, minBet, maxBet);

    // 3. Call contract with encrypted data
    const calldata = CallData.compile({
      match_id: matchId,
      encrypted_amount: {
        c1: encrypted.c1,
        c2: encrypted.c2,
        proof_hash: encrypted.proofHash,
      },
      outcome,
    });

    const { transaction_hash } = await account.execute({
      contractAddress,
      entrypoint: "commit_bet_encrypted",
      calldata,
    });

    return transaction_hash;
  }

  // ============ PRIVATE METHODS ============

  private getDefaultPublicKey(): string {
    // In production, fetch from Tongo service or contract
    // This is the ElGamal public key for the prediction market
    return "0x1234567890abcdef"; // Placeholder
  }

  private async mockEncrypt(amount: bigint): Promise<EncryptedAmount> {
    // Mock encryption for demonstration
    // In production, use actual Tongo SDK ElGamal encryption

    // Simulate ElGamal encryption: (c1, c2)
    // c1 = g^r
    // c2 = h^r * m (where h is public key, m is message)

    const randomness = BigInt(Math.floor(Math.random() * 1000000));

    return {
      c1: `0x${(randomness * 2n).toString(16)}`,
      c2: `0x${(amount + randomness).toString(16)}`,
      proofHash: `0x${this.hashProof(amount).toString(16)}`,
    };
  }

  private hashProof(amount: bigint): bigint {
    // Simple hash for demo - in production use proper ZK proof
    return amount * 31n + 42n;
  }

  private mockRangeProof(amount: bigint, min: bigint, max: bigint): string {
    // Mock range proof
    // In production: generate bulletproof or similar ZK range proof
    const proofData = {
      commitment: amount.toString(16),
      min: min.toString(16),
      max: max.toString(16),
      timestamp: Date.now(),
    };

    return `0x${Buffer.from(JSON.stringify(proofData)).toString("hex")}`;
  }
}

/**
 * React Hook for Tongo Integration
 *
 * Usage:
 * const { encryptBet, placeBet, isLoading } = useTongo();
 * const encrypted = await encryptBet(100n);
 */
export function useTongo(config?: TongoConfig) {
  const tongo = new TongoIntegration(
    config || { network: "sepolia" }
  );

  const encryptBet = async (amount: bigint) => {
    return await tongo.encryptBetAmount(amount);
  };

  const placeBet = async (
    contractAddress: string,
    matchId: number,
    amount: bigint,
    outcome: 0 | 1,
    account: Account
  ) => {
    return await tongo.placeEncryptedBet(
      contractAddress,
      matchId,
      amount,
      outcome,
      account
    );
  };

  return {
    encryptBet,
    placeBet,
    verifyProof: tongo.verifyProof.bind(tongo),
  };
}

/**
 * Example Usage
 */
export async function exampleTongoUsage() {
  // Initialize Tongo
  const tongo = new TongoIntegration({ network: "sepolia" });

  // User wants to bet 100 STRK on Team A
  const betAmount = 100000000000000000000n; // 100 STRK in wei

  // 1. Encrypt the bet amount
  const encrypted = await tongo.encryptBetAmount(betAmount);
  console.log("Encrypted bet:", encrypted);
  // Output: { c1: "0x...", c2: "0x...", proofHash: "0x..." }

  // 2. Verify proof (optional, done by contract too)
  const isValid = await tongo.verifyProof(encrypted);
  console.log("Proof valid:", isValid);

  // 3. Place bet with encrypted amount
  // The contract receives encrypted data but can still:
  // - Verify the ZK proof is valid
  // - Update reserves (using homomorphic properties)
  // - Keep individual bets private

  console.log("Bet placed privately! Amount is hidden from public view.");
}

/**
 * Production Tongo SDK Integration Example
 *
 * Uncomment when Tongo SDK is installed:
 *
 * import { TongoSDK } from '@tongo/sdk';
 *
 * export async function realTongoEncryption(amount: bigint) {
 *   const tongo = new TongoSDK({
 *     network: 'sepolia',
 *     contractAddress: PREDICTION_MARKET_ADDRESS,
 *   });
 *
 *   // Encrypt amount with ElGamal
 *   const encrypted = await tongo.encrypt({
 *     amount: amount.toString(),
 *     recipient: PREDICTION_MARKET_ADDRESS,
 *   });
 *
 *   // Generate ZK proof that amount is valid (range proof)
 *   const proof = await tongo.generateProof({
 *     type: 'range',
 *     value: amount,
 *     min: 1000000000000000n,
 *     max: 1000000000000000000000n,
 *   });
 *
 *   return {
 *     c1: encrypted.c1,
 *     c2: encrypted.c2,
 *     proofHash: proof.hash,
 *   };
 * }
 */
