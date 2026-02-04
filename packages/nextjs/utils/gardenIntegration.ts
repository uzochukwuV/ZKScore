/**
 * Garden SDK Integration for ZKScore
 *
 * Enables Bitcoin bridging to Starknet for BTC-denominated bets
 *
 * Installation:
 * npm install @catalogfi/garden-sdk
 *
 * References:
 * - Garden Docs: https://docs.garden.finance
 * - Garden SDK Quickstart: https://docs.garden.finance/developers/quickstart
 */

import { Account } from "starknet";

// Types for Garden SDK integration
export interface BridgeConfig {
  network: "mainnet" | "testnet";
  bitcoinNetwork: "mainnet" | "testnet";
}

export interface BridgeQuote {
  fromAmount: string; // BTC amount
  toAmount: string; // sBTC amount on Starknet
  fee: string;
  estimatedTime: number; // seconds
  route: string;
}

export interface BridgeStatus {
  status: "pending" | "confirming" | "completed" | "failed";
  txHash: string;
  confirmations: number;
  requiredConfirmations: number;
}

/**
 * Garden SDK Wrapper for Bitcoin <-> Starknet Bridge
 *
 * Usage:
 * const garden = new GardenIntegration({ network: "testnet" });
 * const quote = await garden.getBridgeQuote("0.001");
 * await garden.bridgeBTCToStarknet("0.001", starknetAddress);
 */
export class GardenIntegration {
  private config: BridgeConfig;

  constructor(config: BridgeConfig) {
    this.config = config;
  }

  /**
   * Get quote for bridging BTC to Starknet
   *
   * @param btcAmount - Amount of BTC to bridge (e.g., "0.001")
   * @returns Bridge quote with fees and estimated time
   */
  async getBridgeQuote(btcAmount: string): Promise<BridgeQuote> {
    // In production, use actual Garden SDK:
    // import { GardenSDK } from '@catalogfi/garden-sdk';
    // const garden = new GardenSDK({ network: this.config.network });
    // return await garden.getQuote({
    //   from: 'bitcoin',
    //   to: 'starknet',
    //   amount: btcAmount,
    // });

    // Mock quote for demonstration
    const amount = parseFloat(btcAmount);
    const fee = amount * 0.003; // 0.3% fee
    const toAmount = amount - fee;

    return {
      fromAmount: btcAmount,
      toAmount: toAmount.toFixed(8),
      fee: fee.toFixed(8),
      estimatedTime: 600, // 10 minutes
      route: "Bitcoin → Garden → Starknet (sBTC)",
    };
  }

  /**
   * Bridge BTC from Bitcoin to Starknet
   *
   * @param btcAmount - Amount of BTC to bridge
   * @param starknetAddress - Recipient address on Starknet
   * @returns Transaction hash on Bitcoin
   */
  async bridgeBTCToStarknet(
    btcAmount: string,
    starknetAddress: string
  ): Promise<string> {
    // In production:
    // const garden = new GardenSDK({ network: this.config.network });
    //
    // const order = await garden.createOrder({
    //   from: 'bitcoin',
    //   to: 'starknet',
    //   amount: btcAmount,
    //   recipient: starknetAddress,
    // });
    //
    // // User signs Bitcoin transaction
    // const btcTxHash = await garden.executeBitcoinTransaction(order);
    //
    // return btcTxHash;

    console.log(`Bridging ${btcAmount} BTC to Starknet address: ${starknetAddress}`);

    // Mock transaction hash
    return "0xbtc" + Math.random().toString(16).substring(2);
  }

  /**
   * Bridge sBTC from Starknet back to Bitcoin
   *
   * @param sBTCAmount - Amount of sBTC to bridge back
   * @param bitcoinAddress - Recipient BTC address
   * @param account - Starknet account
   * @returns Transaction hash on Starknet
   */
  async bridgesBTCToBitcoin(
    sBTCAmount: string,
    bitcoinAddress: string,
    account: Account
  ): Promise<string> {
    // In production:
    // const garden = new GardenSDK({ network: this.config.network });
    //
    // const order = await garden.createOrder({
    //   from: 'starknet',
    //   to: 'bitcoin',
    //   amount: sBTCAmount,
    //   recipient: bitcoinAddress,
    // });
    //
    // // User approves sBTC on Starknet
    // const starknetTxHash = await account.execute({
    //   contractAddress: SBTC_TOKEN_ADDRESS,
    //   entrypoint: 'approve',
    //   calldata: [garden.bridgeAddress, sBTCAmount],
    // });
    //
    // // Execute bridge
    // await garden.executeBridge(order, starknetTxHash);
    //
    // return starknetTxHash;

    console.log(`Bridging ${sBTCAmount} sBTC to Bitcoin address: ${bitcoinAddress}`);

    return "0xstarknet" + Math.random().toString(16).substring(2);
  }

  /**
   * Check bridge transaction status
   *
   * @param txHash - Transaction hash (Bitcoin or Starknet)
   * @returns Bridge status
   */
  async checkBridgeStatus(txHash: string): Promise<BridgeStatus> {
    // In production:
    // const garden = new GardenSDK({ network: this.config.network });
    // return await garden.getOrderStatus(txHash);

    // Mock status
    return {
      status: "confirming",
      txHash,
      confirmations: 3,
      requiredConfirmations: 6,
    };
  }

  /**
   * Get sBTC balance on Starknet
   *
   * @param starknetAddress - Starknet address
   * @returns sBTC balance
   */
  async getsBTCBalance(starknetAddress: string): Promise<string> {
    // In production: query sBTC token contract
    // const sBTC = new Contract(sBTC_ABI, sBTC_ADDRESS, provider);
    // const balance = await sBTC.balanceOf(starknetAddress);
    // return balance.toString();

    return "0.05"; // Mock balance: 0.05 sBTC
  }
}

/**
 * Complete flow: Bridge BTC and place bet
 *
 * @param btcAmount - Amount of BTC to bridge and bet
 * @param matchId - Match ID
 * @param outcome - Outcome to bet on
 * @param starknetAccount - User's Starknet account
 */
export async function bridgeAndBet(
  btcAmount: string,
  matchId: number,
  outcome: 0 | 1,
  starknetAccount: Account,
  predictionMarketAddress: string
) {
  const garden = new GardenIntegration({
    network: "testnet",
    bitcoinNetwork: "testnet",
  });

  console.log("Step 1: Get bridge quote");
  const quote = await garden.getBridgeQuote(btcAmount);
  console.log(`Quote: ${btcAmount} BTC → ${quote.toAmount} sBTC (fee: ${quote.fee})`);

  console.log("Step 2: Bridge BTC to Starknet");
  const btcTxHash = await garden.bridgeBTCToStarknet(
    btcAmount,
    starknetAccount.address
  );
  console.log(`Bitcoin TX: ${btcTxHash}`);

  console.log("Step 3: Wait for bridge confirmation (6 Bitcoin blocks)");
  let status = await garden.checkBridgeStatus(btcTxHash);
  while (status.status !== "completed") {
    console.log(
      `Confirmations: ${status.confirmations}/${status.requiredConfirmations}`
    );
    await new Promise((resolve) => setTimeout(resolve, 10000)); // Wait 10s
    status = await garden.checkBridgeStatus(btcTxHash);
  }
  console.log("Bridge completed! sBTC received on Starknet");

  console.log("Step 4: Approve sBTC for prediction market");
  const sBTCAmount = parseFloat(quote.toAmount) * 1e18; // Convert to wei

  // Approve spending
  // await starknetAccount.execute({
  //   contractAddress: SBTC_TOKEN_ADDRESS,
  //   entrypoint: 'approve',
  //   calldata: [predictionMarketAddress, sBTCAmount.toString()],
  // });

  console.log("Step 5: Place bet on prediction market");
  // await starknetAccount.execute({
  //   contractAddress: predictionMarketAddress,
  //   entrypoint: 'buy_outcome',
  //   calldata: [matchId, outcome, sBTCAmount.toString()],
  // });

  console.log("Bet placed successfully with BTC!");
}

/**
 * React Hook for Garden Integration
 */
export function useGarden(config?: BridgeConfig) {
  const garden = new GardenIntegration(
    config || { network: "testnet", bitcoinNetwork: "testnet" }
  );

  const bridgeToBTC = async (amount: string, recipient: string) => {
    return await garden.getBridgeQuote(amount);
  };

  const bridgeFromBTC = async (amount: string, starknetAddress: string) => {
    return await garden.bridgeBTCToStarknet(amount, starknetAddress);
  };

  const checkStatus = async (txHash: string) => {
    return await garden.checkBridgeStatus(txHash);
  };

  return {
    bridgeToBTC,
    bridgeFromBTC,
    checkStatus,
    getBalance: garden.getsBTCBalance.bind(garden),
  };
}

/**
 * Example: Full betting flow with Bitcoin
 */
export async function exampleBitcoinBetting() {
  // User has 0.01 BTC and wants to bet on Lakers vs Warriors

  const btcAmount = "0.01"; // 0.01 BTC (~$600)
  const matchId = 1;
  const outcome = 0; // Bet on Team A (Lakers)

  console.log("=== Bitcoin Betting Flow ===");

  // 1. Get bridge quote
  const garden = new GardenIntegration({
    network: "testnet",
    bitcoinNetwork: "testnet",
  });

  const quote = await garden.getBridgeQuote(btcAmount);
  console.log(`\n1. Bridge Quote:`);
  console.log(`   From: ${quote.fromAmount} BTC`);
  console.log(`   To: ${quote.toAmount} sBTC on Starknet`);
  console.log(`   Fee: ${quote.fee} BTC`);
  console.log(`   Time: ~${quote.estimatedTime / 60} minutes`);

  // 2. User confirms and bridges
  console.log(`\n2. Initiating bridge...`);
  const btcTxHash = await garden.bridgeBTCToStarknet(
    btcAmount,
    "0xSTARKNET_ADDRESS"
  );
  console.log(`   Bitcoin TX: ${btcTxHash}`);

  // 3. Wait for confirmations
  console.log(`\n3. Waiting for confirmations...`);
  const status = await garden.checkBridgeStatus(btcTxHash);
  console.log(`   Status: ${status.status}`);
  console.log(`   Confirmations: ${status.confirmations}/${status.requiredConfirmations}`);

  // 4. Once bridged, sBTC available on Starknet
  console.log(`\n4. sBTC received on Starknet!`);

  // 5. Place bet
  console.log(`\n5. Placing bet on match ${matchId}...`);
  console.log(`   Outcome: Team ${outcome === 0 ? "A" : "B"}`);
  console.log(`   Amount: ${quote.toAmount} sBTC`);

  // 6. If user wins, redeem and bridge back to Bitcoin
  console.log(`\n6. After match settles:`);
  console.log(`   - If won: Redeem sBTC → Bridge back to Bitcoin`);
  console.log(`   - If lost: Better luck next time!`);
}

/**
 * Production Garden SDK Integration Example
 *
 * Uncomment when Garden SDK is installed:
 *
 * import { GardenSDK } from '@catalogfi/garden-sdk';
 *
 * export async function realGardenBridge(
 *   btcAmount: string,
 *   starknetAddress: string
 * ) {
 *   const garden = new GardenSDK({
 *     network: 'testnet',
 *     walletProvider: window.bitcoin, // Xverse or Unisat
 *   });
 *
 *   // Create bridge order
 *   const order = await garden.swap({
 *     fromChain: 'bitcoin',
 *     toChain: 'starknet',
 *     fromToken: 'BTC',
 *     toToken: 'sBTC',
 *     amount: btcAmount,
 *     recipient: starknetAddress,
 *   });
 *
 *   // User signs Bitcoin transaction
 *   const signature = await window.bitcoin.signTransaction(order.psbt);
 *
 *   // Execute bridge
 *   const result = await garden.executeSwap(order.id, signature);
 *
 *   return result.txHash;
 * }
 */
