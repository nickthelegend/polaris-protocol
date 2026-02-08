const hre = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
    const [deployer] = await hre.ethers.getSigners();
    console.log("Deploying contracts with the account:", deployer.address);

    const network = hre.network.name;
    const addressesPath = path.join(__dirname, "../addresses.json");
    let addresses = {};
    if (fs.existsSync(addressesPath)) {
        addresses = JSON.parse(fs.readFileSync(addressesPath, "utf8"));
    }

    const isSpokeChain = network === "sepolia" || network === "baseSepolia" || network === "ganache";

    if (isSpokeChain) {
        console.log(`--- Deploying to Spoke Chain: ${network} ---`);

        // 1. Deploy Tokens (for testing/demo)
        const Token = await hre.ethers.getContractFactory("MockERC20");
        const usdc = await Token.deploy("USD Coin", "USDC", 18);
        await usdc.waitForDeployment();
        const usdt = await Token.deploy("Tether", "USDT", 18);
        await usdt.waitForDeployment();
        const ctc = await Token.deploy("Creditcoin", "CTC", 18);
        await ctc.waitForDeployment();

        console.log("USDC:", await usdc.getAddress());
        console.log("USDT:", await usdt.getAddress());
        console.log("CTC:", await ctc.getAddress());

        // 2. Deploy LiquidityVault (Validator = Deployer for now)
        const LiquidityVault = await hre.ethers.getContractFactory("LiquidityVault");
        const vault = await LiquidityVault.deploy(deployer.address);
        await vault.waitForDeployment();
        const vaultAddress = await vault.getAddress();
        console.log("LiquidityVault deployed to:", vaultAddress);

        // 3. Whitelist tokens
        await vault.setTokenWhitelist(await usdc.getAddress(), true);
        await vault.setTokenWhitelist(await usdt.getAddress(), true);
        await vault.setTokenWhitelist(await ctc.getAddress(), true);
        console.log("Tokens whitelisted in Vault");

        if (!addresses[network]) addresses[network] = {};
        addresses[network].usdc = await usdc.getAddress();
        addresses[network].usdt = await usdt.getAddress();
        addresses[network].ctc = await ctc.getAddress();
        addresses[network].liquidityVault = vaultAddress;

    } else if (network === "uscTestnet") {
        console.log("--- Deploying to USC Testnet ---");

        const PROVER_ADDRESS = "0xc43402c66e88f38a5aa6e35113b310e1c19571d4"; // Official USC Prover

        // 1. Deploy PoolManager
        const PoolManager = await hre.ethers.getContractFactory("PoolManager");
        const poolManager = await PoolManager.deploy(PROVER_ADDRESS);
        await poolManager.waitForDeployment();
        const poolManagerAddress = await poolManager.getAddress();
        console.log("PoolManager deployed to:", poolManagerAddress);

        // --- Whitelist standard tokens for Aggregated Collateral ---
        // These addresses are the ones from Sepolia (Source Tokens)
        const SEPOLIA_USDC = addresses.sepolia ? addresses.sepolia.usdc : "0x02969F85a3B1f72c3317B494c41593d8F4B58907";
        const SEPOLIA_USDT = addresses.sepolia ? addresses.sepolia.usdt : "0x546Bbb8B960EaF059B0771cC4808Da13829e1c42";

        console.log("Whitelisting tokens for aggregation...");
        await poolManager.setWhitelistedToken(SEPOLIA_USDC, true);
        await poolManager.setWhitelistedToken(SEPOLIA_USDT, true);

        // 2. Deploy ScoreManager
        const ScoreManager = await hre.ethers.getContractFactory("ScoreManager");
        const scoreManager = await ScoreManager.deploy(poolManagerAddress);
        await scoreManager.waitForDeployment();
        const scoreManagerAddress = await scoreManager.getAddress();
        console.log("ScoreManager deployed to:", scoreManagerAddress);

        // 3. Deploy LoanEngine
        const LoanEngine = await hre.ethers.getContractFactory("LoanEngine");
        const loanEngine = await LoanEngine.deploy(scoreManagerAddress, poolManagerAddress);
        await loanEngine.waitForDeployment();
        const loanEngineAddress = await loanEngine.getAddress();
        console.log("LoanEngine deployed to:", loanEngineAddress);

        // 4. Deploy MerchantRouter
        const MerchantRouter = await hre.ethers.getContractFactory("MerchantRouter");
        const merchantRouter = await MerchantRouter.deploy(poolManagerAddress, loanEngineAddress);
        await merchantRouter.waitForDeployment();
        const merchantRouterAddress = await merchantRouter.getAddress();
        console.log("MerchantRouter deployed to:", merchantRouterAddress);

        // 5. Wire up: PoolManager Needs LoanEngine address
        console.log("Wiring up PoolManager...");
        await poolManager.setLoanEngine(loanEngineAddress);

        // 6. Transfer Ownership of ScoreManager to LoanEngine 
        // (So LoanEngine can update scores)
        console.log("Wiring up ScoreManager...");
        await scoreManager.transferOwnership(loanEngineAddress);

        addresses.poolManager = poolManagerAddress;
        addresses.scoreManager = scoreManagerAddress;
        addresses.loanEngine = loanEngineAddress;
        addresses.merchantRouter = merchantRouterAddress;
    }

    fs.writeFileSync(addressesPath, JSON.stringify(addresses, null, 2));
    console.log("Addresses updated in addresses.json");
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
