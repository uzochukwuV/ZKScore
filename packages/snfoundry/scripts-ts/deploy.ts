import {
  deployContract,
  executeDeployCalls,
  exportDeployments,
  deployer,
  assertDeployerDefined,
  assertRpcNetworkActive,
  assertDeployerSignable,
} from "./deploy-contract";
import { green, red, yellow } from "./helpers/colorize-log";

/**
 * Deploy ZKScore contracts:
 * 1. OutcomeToken - ERC20 token for bet positions (declare only, deployed per market)
 * 2. PredictionMarket - Main market contract with CPMM
 * 3. StealthPrivacy - Privacy layer for stealth betting
 */
const deployScript = async (): Promise<void> => {
  console.log(yellow("\n📦 Deploying ZKScore Contracts...\n"));

  // Step 1: Deploy OutcomeToken to get its class hash
  // Note: This deploys a "dummy" instance just to declare the class
  // The actual tokens are deployed by PredictionMarket per market
  console.log(yellow("Step 1: Declaring OutcomeToken class..."));
  const outcomeToken = await deployContract({
    contract: "OutcomeToken",
    contractName: "OutcomeToken",
    constructorArgs: {
      match_id: 0,
      outcome: 0,
      name: "Placeholder Token",
      symbol: "PLH",
      market_contract: deployer.address, // Placeholder, real one set per market
    },
  });

  console.log(green(`✓ OutcomeToken class hash: ${outcomeToken.classHash}`));

  // Step 2: Deploy PredictionMarket with OutcomeToken class hash
  console.log(yellow("\nStep 2: Deploying PredictionMarket..."));
  const predictionMarket = await deployContract({
    contract: "PredictionMarket",
    contractName: "PredictionMarket",
    constructorArgs: {
      owner: deployer.address,
      outcome_token_class_hash: outcomeToken.classHash,
    },
  });

  console.log(green(`✓ PredictionMarket deployed at: ${predictionMarket.address}`));

  // Step 3: Deploy StealthPrivacy
  console.log(yellow("\nStep 3: Deploying StealthPrivacy..."));
  const stealthPrivacy = await deployContract({
    contract: "StealthPrivacy",
    contractName: "StealthPrivacy",
    constructorArgs: {},
  });

  console.log(green(`✓ StealthPrivacy deployed at: ${stealthPrivacy.address}`));

  // Summary
  console.log(yellow("\n═══════════════════════════════════════════════════"));
  console.log(green("🎉 ZKScore Deployment Summary:"));
  console.log(yellow("═══════════════════════════════════════════════════"));
  console.log(`OutcomeToken Class Hash: ${outcomeToken.classHash}`);
  console.log(`PredictionMarket:        ${predictionMarket.address}`);
  console.log(`StealthPrivacy:          ${stealthPrivacy.address}`);
  console.log(yellow("═══════════════════════════════════════════════════\n"));
};

const main = async (): Promise<void> => {
  try {
    assertDeployerDefined();

    await Promise.all([assertRpcNetworkActive(), assertDeployerSignable()]);

    await deployScript();
    await executeDeployCalls();
    exportDeployments();

    console.log(green("All Setup Done!"));
  } catch (err) {
    if (err instanceof Error) {
      console.error(red(err.message));
    } else {
      console.error(err);
    }
    process.exit(1); //exit with error so that non subsequent scripts are run
  }
};

main();
