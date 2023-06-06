require("@nomicfoundation/hardhat-toolbox");
require("@nomicfoundation/hardhat-foundry");
require("@openzeppelin/hardhat-upgrades");
require("dotenv").config();

const dev_wallet_key = process.env.PRIVATE_KEY;
const etherscan_api_key = process.env.ETHERSCAN_API_KEY;

/**
 * @type import('hardhat/config').HardhatUserConfig
 */

module.exports = {
  solidity: "0.8.19",
  defaultNetwork: "hardhat",
  networks: {
    goerli: {
      chainId: 5,
      url: process.env.ETH_GOERLI_TESTNET_URL || "",
      accounts: process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
    },
    // for mainnet
    optimism: {
      url: "https://mainnet.optimism.io",
      accounts: [dev_wallet_key],
    },
    // for testnet
    "optimism-kovan": {
      url: "https://kovan.optimism.io",
      accounts: [dev_wallet_key],
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
};
