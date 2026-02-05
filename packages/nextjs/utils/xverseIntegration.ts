/**
 * Xverse Wallet Integration for ZKScore
 *
 * Enables Bitcoin + Starknet dual wallet support
 *
 * Installation:
 * npm install @xverse/wallet-sdk
 *
 * References:
 * - Xverse Docs: https://docs.xverse.app
 * - Xverse Starknet Bridge: https://xverse.app/starknet
 */

import { Account, RpcProvider } from "starknet";

// Xverse Wallet Types
export interface XverseWallet {
  bitcoin: {
    address: string;
    publicKey: string;
    balance: number;
  };
  starknet: {
    address: string;
    balance: number;
  };
}

export interface XverseConfig {
  network: "mainnet" | "testnet";
}

/**
 * Xverse Wallet Integration for ZKScore
 *
 * Provides unified Bitcoin + Starknet wallet experience
 *
 * Usage:
 * const xverse = new XverseIntegration({ network: "testnet" });
 * const wallet = await xverse.connect();
 * await xverse.bridgeAndBet(0.001, matchId, outcome);
 */
export class XverseIntegration {
  private config: XverseConfig;
  private wallet: XverseWallet | null = null;

  constructor(config: XverseConfig) {
    this.config = config;
  }

  /**
   * Connect to Xverse Wallet
   * Opens wallet popup for user to connect
   *
   * @returns Connected wallet info
   */
  async connect(): Promise<XverseWallet> {
    // In production, use actual Xverse SDK:
    // import { connect } from '@xverse/wallet-sdk';
    //
    // const wallet = await connect({
    //   onFinish: (response) => {
    //     this.wallet = {
    //       bitcoin: {
    //         address: response.addresses.bitcoin.address,
    //         publicKey: response.addresses.bitcoin.publicKey,
    //         balance: response.addresses.bitcoin.balance,
    //       },
    //       starknet: {
    //         address: response.addresses.starknet.address,
    //         balance: response.addresses.starknet.balance,
    //       },
    //     };
    //   },
    //   onCancel: () => {
    //     throw new Error('User cancelled connection');
    //   },
    // });

    // Mock wallet for demonstration
    this.wallet = {
      bitcoin: {
        address: "bc1q...mock",
        publicKey: "03...mock",
        balance: 0.1, // 0.1 BTC
      },
      starknet: {
        address: "0x...mock",
        balance: 500, // 500 STRK
      },
    };

    console.log("Xverse wallet connected:", this.wallet);
    return this.wallet;
  }

  /**
   * Disconnect wallet
   */
  async disconnect(): Promise<void> {
    this.wallet = null;
    console.log("Xverse wallet disconnected");
  }

  /**
   * Get Bitcoin balance
   */
  async getBitcoinBalance(): Promise<number> {
    if (!this.wallet) {
      throw new Error("Wallet not connected");
    }

    // In production:
    // import { getBalance } from '@xverse/wallet-sdk';
    // return await getBalance(this.wallet.bitcoin.address);

    return this.wallet.bitcoin.balance;
  }

  /**
   * Get Starknet balance
   */
  async getStarknetBalance(): Promise<number> {
    if (!this.wallet) {
      throw new Error("Wallet not connected");
    }

    // In production:
    // const provider = new RpcProvider({ nodeUrl: STARKNET_RPC });
    // const balance = await provider.getBalance(this.wallet.starknet.address);
    // return parseFloat(balance.toString()) / 1e18;

    return this.wallet.starknet.balance;
  }

  /**
   * Bridge BTC to Starknet using Xverse Bridge
   * Uses Xverse's integrated bridge (powered by Garden/Orbiter)
   *
   * @param btcAmount - Amount of BTC to bridge
   * @returns Transaction hash
   */
  async bridgeBTCToStarknet(btcAmount: number): Promise<string> {
    if (!this.wallet) {
      throw new Error("Wallet not connected");
    }

    // In production:
    // import { bridge } from '@xverse/wallet-sdk';
    //
    // const tx = await bridge({
    //   from: 'bitcoin',
    //   to: 'starknet',
    //   amount: btcAmount,
    //   fromAddress: this.wallet.bitcoin.address,
    //   toAddress: this.wallet.starknet.address,
    // });
    //
    // return tx.hash;

    console.log(
      `Bridging ${btcAmount} BTC from ${this.wallet.bitcoin.address} to ${this.wallet.starknet.address}`
    );

    return "0xxverse_bridge_" + Math.random().toString(16).substring(2);
  }

  /**
   * Sign Bitcoin transaction
   * Used for custom Bitcoin transactions (e.g., OP_CAT apps)
   *
   * @param psbt - Partially Signed Bitcoin Transaction
   * @returns Signed transaction
   */
  async signBitcoinTransaction(psbt: string): Promise<string> {
    if (!this.wallet) {
      throw new Error("Wallet not connected");
    }

    // In production:
    // import { signTransaction } from '@xverse/wallet-sdk';
    // return await signTransaction(psbt);

    console.log("Signing Bitcoin transaction...");
    return "signed_" + psbt;
  }

  /**
   * Sign Starknet transaction
   * Used for prediction market bets
   *
   * @param calls - Starknet function calls
   * @returns Transaction hash
   */
  async signStarknetTransaction(calls: any[]): Promise<string> {
    if (!this.wallet) {
      throw new Error("Wallet not connected");
    }

    // In production:
    // import { signStarknetTransaction } from '@xverse/wallet-sdk';
    // return await signStarknetTransaction(calls);

    console.log("Signing Starknet transaction...");
    return "0xstarknet_" + Math.random().toString(16).substring(2);
  }

  /**
   * Complete betting flow using Xverse
   * 1. Bridge BTC to Starknet
   * 2. Wait for confirmation
   * 3. Place bet on prediction market
   *
   * @param btcAmount - Amount of BTC to bet
   * @param matchId - Match ID
   * @param outcome - Outcome to bet on
   * @param predictionMarketAddress - Contract address
   */
  async bridgeAndBet(
    btcAmount: number,
    matchId: number,
    outcome: 0 | 1,
    predictionMarketAddress: string
  ): Promise<{ bridgeTx: string; betTx: string }> {
    if (!this.wallet) {
      throw new Error("Wallet not connected");
    }

    console.log("=== Xverse Bridge & Bet Flow ===");

    // Step 1: Bridge BTC to Starknet
    console.log(`\n1. Bridging ${btcAmount} BTC to Starknet...`);
    const bridgeTx = await this.bridgeBTCToStarknet(btcAmount);
    console.log(`   Bridge TX: ${bridgeTx}`);

    // Step 2: Wait for bridge confirmation
    console.log(`\n2. Waiting for bridge confirmation...`);
    await this.waitForBridgeConfirmation(bridgeTx);
    console.log(`   Bridge confirmed! sBTC received.`);

    // Step 3: Place bet
    console.log(`\n3. Placing bet on match ${matchId}...`);
    const betAmount = btcAmount * 0.997 * 1e18; // Minus 0.3% fee, convert to wei

    const betTx = await this.signStarknetTransaction([
      {
        contractAddress: predictionMarketAddress,
        entrypoint: "buy_outcome",
        calldata: [matchId, outcome, betAmount.toString()],
      },
    ]);

    console.log(`   Bet TX: ${betTx}`);
    console.log(`\n✅ Bet placed successfully!`);

    return { bridgeTx, betTx };
  }

  /**
   * Redeem winnings and bridge back to Bitcoin
   *
   * @param matchId - Match ID
   * @param amount - Amount of tokens to redeem
   * @param predictionMarketAddress - Contract address
   */
  async redeemAndBridge(
    matchId: number,
    amount: bigint,
    predictionMarketAddress: string
  ): Promise<{ redeemTx: string; bridgeTx: string }> {
    if (!this.wallet) {
      throw new Error("Wallet not connected");
    }

    console.log("=== Xverse Redeem & Bridge Back ===");

    // Step 1: Redeem winning tokens
    console.log(`\n1. Redeeming ${amount} winning tokens...`);
    const redeemTx = await this.signStarknetTransaction([
      {
        contractAddress: predictionMarketAddress,
        entrypoint: "redeem_winning_tokens",
        calldata: [matchId, amount.toString()],
      },
    ]);
    console.log(`   Redeem TX: ${redeemTx}`);

    // Step 2: Bridge sBTC back to Bitcoin
    console.log(`\n2. Bridging sBTC back to Bitcoin...`);
    const sBTCAmount = Number(amount) / 1e18;

    // In production:
    // import { bridge } from '@xverse/wallet-sdk';
    // const bridgeTx = await bridge({
    //   from: 'starknet',
    //   to: 'bitcoin',
    //   amount: sBTCAmount,
    //   fromAddress: this.wallet.starknet.address,
    //   toAddress: this.wallet.bitcoin.address,
    // });

    const bridgeTx = "0xbridge_back_" + Math.random().toString(16).substring(2);
    console.log(`   Bridge TX: ${bridgeTx}`);

    console.log(`\n✅ Winnings bridged back to Bitcoin!`);

    return { redeemTx, bridgeTx };
  }

  // ============ PRIVATE METHODS ============

  private async waitForBridgeConfirmation(txHash: string): Promise<void> {
    // In production: poll bridge status
    // For demo: simulate 30 second wait
    await new Promise((resolve) => setTimeout(resolve, 3000));
  }
}

/**
 * React Hook for Xverse Integration
 */
export function useXverse(config?: XverseConfig) {
  const xverse = new XverseIntegration(config || { network: "testnet" });

  const connect = async () => {
    return await xverse.connect();
  };

  const disconnect = async () => {
    return await xverse.disconnect();
  };

  const getBTCBalance = async () => {
    return await xverse.getBitcoinBalance();
  };

  const getSTRKBalance = async () => {
    return await xverse.getStarknetBalance();
  };

  return {
    connect,
    disconnect,
    getBTCBalance,
    getSTRKBalance,
    bridgeAndBet: xverse.bridgeAndBet.bind(xverse),
    redeemAndBridge: xverse.redeemAndBridge.bind(xverse),
  };
}

/**
 * Example: Complete betting flow with Xverse
 */
export async function exampleXverseBetting() {
  console.log("=== Xverse Unified Betting Experience ===\n");

  const xverse = new XverseIntegration({ network: "testnet" });

  // 1. Connect wallet
  console.log("1. Connecting Xverse wallet...");
  const wallet = await xverse.connect();
  console.log(`   Bitcoin: ${wallet.bitcoin.address}`);
  console.log(`   Starknet: ${wallet.starknet.address}`);
  console.log(`   BTC Balance: ${wallet.bitcoin.balance}`);
  console.log(`   STRK Balance: ${wallet.starknet.balance}`);

  // 2. User wants to bet 0.01 BTC on Lakers
  console.log("\n2. User wants to bet 0.01 BTC on Lakers vs Warriors");

  const matchId = 1;
  const outcome = 0; // Team A (Lakers)
  const btcAmount = 0.01;

  // 3. Bridge and bet (single flow!)
  console.log("\n3. Executing bridge & bet...");
  const { bridgeTx, betTx } = await xverse.bridgeAndBet(
    btcAmount,
    matchId,
    outcome,
    "0xPREDICTION_MARKET_ADDRESS"
  );

  console.log(`\n✅ Complete!`);
  console.log(`   Bridge TX: ${bridgeTx}`);
  console.log(`   Bet TX: ${betTx}`);

  // 4. After match settles, redeem and bridge back
  console.log("\n4. Match settled - Lakers won!");
  const winnings = BigInt(0.015 * 1e18); // 0.015 BTC in wei

  const { redeemTx, bridgeTx: returnBridgeTx } = await xverse.redeemAndBridge(
    matchId,
    winnings,
    "0xPREDICTION_MARKET_ADDRESS"
  );

  console.log(`\n✅ Winnings redeemed and bridged back to Bitcoin!`);
  console.log(`   Redeem TX: ${redeemTx}`);
  console.log(`   Bridge TX: ${returnBridgeTx}`);

  console.log(`\n🎉 Total profit: 0.005 BTC (~$300)`);
}

/**
 * React Component Example
 */
export const XverseWalletButton = () => {
  // Example React component (pseudo-code)
  /*
  import { useState } from 'react';
  import { useXverse } from './xverseIntegration';

  export function XverseWalletButton() {
    const [wallet, setWallet] = useState(null);
    const { connect, disconnect } = useXverse();

    const handleConnect = async () => {
      const w = await connect();
      setWallet(w);
    };

    return (
      <div>
        {!wallet ? (
          <button onClick={handleConnect}>
            Connect Xverse (BTC + Starknet)
          </button>
        ) : (
          <div>
            <p>Bitcoin: {wallet.bitcoin.address}</p>
            <p>Starknet: {wallet.starknet.address}</p>
            <p>BTC Balance: {wallet.bitcoin.balance}</p>
            <button onClick={disconnect}>Disconnect</button>
          </div>
        )}
      </div>
    );
  }
  */
};

/**
 * Production Xverse SDK Integration Example
 *
 * Uncomment when Xverse SDK is installed:
 *
 * import { connect, bridge, signTransaction } from '@xverse/wallet-sdk';
 *
 * export async function realXverseConnection() {
 *   const wallet = await connect({
 *     appDetails: {
 *       name: 'ZKScore',
 *       icon: 'https://zkscore.xyz/icon.png',
 *     },
 *     onFinish: (response) => {
 *       console.log('Connected:', response);
 *     },
 *     onCancel: () => {
 *       console.log('Cancelled');
 *     },
 *   });
 *
 *   return wallet;
 * }
 *
 * export async function realXverseBridge(btcAmount: number, starknetAddress: string) {
 *   const tx = await bridge({
 *     from: 'bitcoin',
 *     to: 'starknet',
 *     amount: btcAmount.toString(),
 *     recipient: starknetAddress,
 *   });
 *
 *   return tx.txid;
 * }
 */
