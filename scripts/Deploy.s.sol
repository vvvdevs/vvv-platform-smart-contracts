pragma solidity 0.8.19;

/**
forge script scripts/Deploy.s.sol:DeployLockScript --private-key $PRIVATE_KEY --fork-url $ETH_GOERLI_TESTNET_URL
 */


import {Lock} from "contracts/demo/Lock.sol";
import "lib/forge-std/src/Script.sol";

contract DeployLockScript is Script {

    Lock public lock;

    function run() public {

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

            lock = new Lock(block.timestamp + 1 days);

        vm.stopBroadcast();

        console.log("Deployed Lock contract to address: ", address(lock));

    }

}