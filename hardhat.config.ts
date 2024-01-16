require("@nomicfoundation/hardhat-toolbox");
require("@nomicfoundation/hardhat-foundry");
require("@openzeppelin/hardhat-upgrades");
require("dotenv").config();
require("hardhat-gas-reporter");
require("hardhat-abi-exporter");
require("hardhat-contract-sizer");

require("./tasks/deploy/deploy-legacy-trade-in");

const dev_wallet_key = process.env.PRIVATE_KEY;
const mainnet_wallet_key = process.env.MAINNET_PRIVATE_KEY;
const etherscan_api_key = process.env.ETHERSCAN_API_KEY;

module.exports = {
  solidity: {
    version: "0.8.23",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
    allowUnlimitedContractSize: false,
  },
  defaultNetwork: "hardhat",
  networks: {
    goerli: {
      chainId: 5,
      url: "https://goerli.infura.io/v3/" + process.env.INFURA_API_KEY,
      accounts:
        process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
    },
    sepolia: {
      chainId: 11155111,
      url: "https://sepolia.infura.io/v3/" + process.env.INFURA_API_KEY,
      accounts:
        process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
    },
    mainnet: {
      chainId: 1,
      url: "https://mainnet.infura.io/v3/" + process.env.INFURA_API_KEY,
      accounts:
        process.env.MAINNET_PRIVATE_KEY !== undefined
          ? [process.env.PRIVATE_KEY]
          : [],
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
    enabled: false,
    currency: "USD",
    gasPrice: 30,
    url: "localhost:8545",
  },
  abiExporter: {
    path: "./abi/hardhat_abi_export",
    format: "json",
  },
  contractSizer: {
    alphaSort: true,
    runOnCompile: true,
    disambiguatePaths: false,
  },
};
