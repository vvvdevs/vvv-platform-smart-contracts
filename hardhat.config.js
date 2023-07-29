require("@nomicfoundation/hardhat-toolbox");
require("@nomicfoundation/hardhat-foundry");
require("@openzeppelin/hardhat-upgrades");
require("dotenv").config();
require("hardhat-gas-reporter");

const dev_wallet_key = process.env.PRIVATE_KEY;
const etherscan_api_key = process.env.ETHERSCAN_API_KEY;

/**
 * @type import('hardhat/config').HardhatUserConfig
 */

module.exports = {
    solidity: "0.8.20",
    compilerOptions: {
        optimize: true,
        runs: 200,
    },
    defaultNetwork: "hardhat",
    networks: {
        goerli: {
            chainId: 5,
            url: process.env.ETH_GOERLI_TESTNET_URL || "",
            accounts: process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
        },
        sepolia: {
            chainId: 11155111,
            url: process.env.ETH_SEPOLIA_TESTNET_URL || "",
            accounts: process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
        },
        mainnet: {
            chainId: 1,
            url: process.env.ETH_MAINNET_TESTNET_URL || "",
            accounts: process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
        },
        // for the local dev environment
        localhost: {
            url: "http://localhost:8545",
            accounts: [dev_wallet_key],
        },
    },
    etherscan: {
        apiKey: etherscan_api_key,
    },
    gasReporter: {
        enabled: true,
        currency: "USD",
        gasPrice: 30,
    },
};
