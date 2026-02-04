# ZKScore - Compilation Guide

## Network Issue Workaround

This environment is experiencing network proxy issues that block access to:
- npm/yarn registries
- Scarb registry (scarbs.xyz)

## ✅ What's Been Completed

### Smart Contracts (Ready to Compile)

All smart contracts have been written and are ready for compilation:

1. **packages/snfoundry/contracts/src/outcome_token.cairo** - ERC20 outcome tokens
2. **packages/snfoundry/contracts/src/prediction_market.cairo** - Core AMM with halftime trading
3. **packages/snfoundry/contracts/tests/test_prediction_market.cairo** - Comprehensive test suite

### Scarb Installed

Scarb v2.12.2 has been successfully installed:
```bash
$ scarb --version
scarb 2.12.2 (dc0dbfd50 2025-09-15)
cairo: 2.12.2
sierra: 1.7.0
```

## 🔧 Compilation Options

### Option 1: Compile in a Different Environment (Recommended)

**Local Machine Setup:**

```bash
# 1. Clone the repository
git clone https://github.com/uzochukwuV/ZKScore
cd ZKScore
git checkout claude/bitcoin-privacy-starknet-s2swp

# 2. Install Scarb (if not installed)
curl --proto '=https' --tlsv1.2 -sSf https://docs.swmansion.com/scarb/install.sh | sh

# 3. Install dependencies
cd packages/snfoundry/contracts
scarb build

# Expected output:
#    Compiling contracts v0.2.0 (/path/to/ZKScore/packages/snfoundry/contracts/Scarb.toml)
#    Finished release target(s) in X seconds
```

**Using GitHub Codespaces:**

```bash
# 1. Open repository in GitHub Codespaces
# 2. Install Scarb
curl --proto '=https' --tlsv1.2 -sSf https://docs.swmansion.com/scarb/install.sh | sh
source ~/.bashrc

# 3. Compile
cd packages/snfoundry/contracts
scarb build
```

### Option 2: Use DevContainer

The project includes a devcontainer configuration:

```bash
# In VS Code with Remote-Containers extension:
1. Open repository in VS Code
2. Press F1 → "Remote-Containers: Reopen in Container"
3. Wait for container to build (uses starknetfoundation/starknet-dev:2.12.2)
4. Run: cd packages/snfoundry/contracts && scarb build
```

### Option 3: Manual Dependency Setup (Advanced)

If you have network restrictions, you can manually download dependencies:

**1. Download OpenZeppelin Cairo Contracts:**

```bash
# Create vendor directory
mkdir -p vendor

# Clone OpenZeppelin contracts
git clone --depth 1 --branch v2.0.0 \
  https://github.com/OpenZeppelin/cairo-contracts.git \
  vendor/openzeppelin-cairo

# Update Scarb.toml to use local path
# Change:
#   openzeppelin_access = ">=2.0.0"
# To:
#   openzeppelin_access = { path = "../../vendor/openzeppelin-cairo/packages/access" }
```

**2. Modify Scarb.toml:**

```toml
[dependencies]
starknet = ">=2.12.2"
# Use local paths instead of registry
openzeppelin_access = { path = "../../../vendor/openzeppelin-cairo/packages/access" }
openzeppelin_token = { path = "../../../vendor/openzeppelin-cairo/packages/token" }
```

**3. Compile:**

```bash
cd packages/snfoundry/contracts
scarb build
```

## 📦 Expected Compilation Output

After successful compilation, you should see:

```
packages/snfoundry/contracts/target/dev/
├── contracts.starknet_artifacts.json
├── contracts_OutcomeToken.contract_class.json           # Outcome token ABI
├── contracts_OutcomeToken.compiled_contract_class.json  # Compiled class
├── contracts_PredictionMarket.contract_class.json       # Prediction market ABI
├── contracts_PredictionMarket.compiled_contract_class.json
└── ... (other generated files)
```

**Key Files:**
- `*.contract_class.json` - Contains ABI for frontend integration
- `*.compiled_contract_class.json` - Contains Sierra bytecode for deployment

## 🧪 Running Tests

Once compiled, run the test suite:

```bash
cd packages/snfoundry/contracts
snforge test

# Expected output:
# [PASS] contracts::test_prediction_market::test_create_market
# [PASS] contracts::test_prediction_market::test_buy_outcome_tokens
# [PASS] contracts::test_prediction_market::test_halftime_reveal
# [PASS] contracts::test_prediction_market::test_final_settlement
# ... (10+ tests)
```

## 🚀 Next Steps After Compilation

### 1. Deploy to Sepolia Testnet

See `NEXT_STEPS.md` section 3 for detailed deployment instructions.

### 2. Frontend Integration

Copy ABIs to frontend:

```bash
# After successful compilation
cp packages/snfoundry/contracts/target/dev/*.contract_class.json \
   packages/nextjs/contracts/
```

### 3. Demo Video

Use compiled contracts + deployed testnet instance for demo recording.

## 🐛 Troubleshooting

### Issue: "failed to lookup for openzeppelin_access"

**Cause:** Cannot reach scarbs.xyz registry due to network restrictions.

**Solutions:**
1. Use Option 1 (compile on local machine/Codespaces)
2. Use Option 3 (manual dependencies with local paths)
3. Configure proxy (if available):
   ```bash
   export HTTP_PROXY=http://your-proxy:port
   export HTTPS_PROXY=http://your-proxy:port
   scarb build
   ```

### Issue: "command 'scarb' not found"

**Solution:** Install Scarb:
```bash
curl --proto '=https' --tlsv1.2 -sSf https://docs.swmansion.com/scarb/install.sh | sh
source ~/.bashrc
```

### Issue: "failed to fetch registry config"

**Cause:** Network connectivity to scarbs.xyz blocked.

**Solution:** Use local dependencies (Option 3) or compile in unrestricted environment.

## 📝 Contract Summary

### PredictionMarket.cairo (Main Contract)

**Lines of Code:** ~650
**Dependencies:**
- openzeppelin_access (Ownable component)
- openzeppelin_token (ERC20 interface)
- starknet (syscalls, storage)

**Key Functions:**
- `create_market()` - Create new match
- `buy_outcome()` / `sell_outcome()` - CPMM trading
- `reveal_first_half()` - Generate first half scores
- `reveal_final_scores()` - Settle market
- `redeem_winning_tokens()` - Claim winnings

### OutcomeToken.cairo (ERC20 Tokens)

**Lines of Code:** ~80
**Dependencies:**
- openzeppelin_token (ERC20Component)
- starknet (ContractAddress)

**Key Functions:**
- `mint()` / `burn()` - Token management (market-only)
- Standard ERC20 functions (transfer, balanceOf, etc.)

## ✅ Verification Checklist

Before deployment, verify:

- [ ] Contracts compile without errors
- [ ] All tests pass (10+ tests)
- [ ] ABIs generated in target/dev/
- [ ] Class hashes are deterministic
- [ ] No security vulnerabilities (check with `scarb cairo-test`)

## 🔗 Resources

- **Scarb Documentation:** https://docs.swmansion.com/scarb/
- **Cairo Book:** https://book.cairo-lang.org/
- **OpenZeppelin Cairo:** https://docs.openzeppelin.com/contracts-cairo/
- **Starknet Foundry:** https://foundry-rs.github.io/starknet-foundry/

## 📞 Support

If compilation issues persist:

1. **GitHub Issues:** Open issue in repository with error logs
2. **Scaffold-Stark Discord:** https://discord.gg/scaffold-stark
3. **Starknet Discord:** https://discord.gg/starknet (channel: #dev-support)

---

## Current Status

✅ Scarb installed successfully (v2.12.2)
❌ Compilation blocked by network proxy
💡 Use alternative compilation environment (local/Codespaces)

**Next Action:** Compile on local machine or GitHub Codespaces, then proceed with deployment.
