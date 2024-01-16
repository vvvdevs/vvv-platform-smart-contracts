import { task } from "hardhat/config";

task("deploy-legacy-trade-in", "Deploy LegacyTradeIn contract")
  .addParam("legacycontract", "Address of the legacy contract")
  .addParam("starttime", "Start time of the trade in")
  .addParam("endtime", "End time of the trade in")
  .setAction(async (taskArgs, hre) => {
    const tradeInFactory = await hre.ethers.getContractFactory("LegacyTradeIn");
    const deployed_legacy = await tradeInFactory.deploy(
      taskArgs.legacycontract,
      taskArgs.starttime,
      taskArgs.endtime,
    );
    await deployed_legacy.deployed();

    console.log(`deployed to ${deployed_legacy.address}`);
  });
