require("@nomicfoundation/hardhat-toolbox");
require("@nomicfoundation/hardhat-foundry");
require("@openzeppelin/hardhat-upgrades");
require("dotenv").config();

// Potentially not needed...
// require("@nomiclabs/hardhat-ethers");
// require("@nomiclabs/hardhat-waffle");
// require("@nomiclabs/hardhat-etherscan");
// require('hardhat-deploy');

const dev_wallet_key = process.env.PRIVATE_KEY;
const etherscan_api_key = process.env.ETHERSCAN_API_KEY;

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async (taskArgs, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

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
