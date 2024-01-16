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

    console.log("waiting for 15 seconds for the contract to be indexed on etherscan");
    await new Promise(resolve => setTimeout(resolve, 15000));

    console.log("verifying the contract on etherscan");
    await hre.run("verify:verify", {
      address: deployed_legacy.address,
      constructorArguments: [
        taskArgs.legacycontract,
        taskArgs.starttime,
        taskArgs.endtime,
      ],
    });

    console.log(`deployed to ${deployed_legacy.address}`);
  });
