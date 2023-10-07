//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {ERC20_UniV3} from "contracts/tokens/VvvToken.sol";
import "forge-std/Script.sol";

contract DeployUtilityToken is Script {

    ERC20_UniV3 public utilityToken;
    
    // Admin Role Addresses: Testing is msg.sender, Production is a multisig or hardware wallet for each role
    address public deployer = vm.addr(vm.envUint("PRIVATE_KEY"));
    address public positionRecipient = deployer;

    address public UNIV3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address public UNIV3_POSITION_MANAGER = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    
    //0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6=Goerli, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2=Mainnet
    address public WETH = 0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6;

    //TOKEN PARAMS
    uint256 public SUPPLY_CAP = 10_000_000 * 1e18;
    uint256 public INITIAL_DEPLOYER_SUPPLY = 2_000_000 * 1e18;
    
    // 1000:1 Price Ratio Implied here...
    uint256 public INITIAL_LIQUIDITY_SUPPLY = 100 * 1e18;
    uint256 public ETH_FOR_POOL = 0.1 ether;

    function run() public {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        utilityToken = new ERC20_UniV3(
            "Utility Token",
            "UTL",
            SUPPLY_CAP,
            INITIAL_DEPLOYER_SUPPLY,
            INITIAL_LIQUIDITY_SUPPLY,
            positionRecipient,
            UNIV3_FACTORY,
            UNIV3_POSITION_MANAGER,
            WETH
        );

        console.log("Utility Token deployed at address: %s", address(utilityToken));
        
        //add liquidity
        /**
        Calculating the sqrtPriceX96 for a given price ratio
        1. Calculate the price ratio: priceRatio = 1000 (1000 Tokens/ETH)
        2. Take the square root of the price ratio: sqrtPriceRatio = sqrt(1000) = 31.6227766017
        3. Multiply by 2^96 to get sqrtPriceX96: sqrtPriceX96 = 31.6227766017 * 2^96 = 2505413655765166104103837312489
        4. Depending on address order, the sqrtPriceX96 will be either be sqrt(1000) or sqrt(1/1000) * 2^96
         */
        //-887220/887220 is the tick values from frontend for ticks, hardcoded into contract for now at least, don't see why these would change

        uint160 SQRTX96_PRICE_01 = 2505413655765166104103837312489;
        uint160 SQRTX96_PRICE_10 = 2505414483750479155158843392;
        utilityToken.addLiquidity{value: ETH_FOR_POOL}(
            SQRTX96_PRICE_01,
            SQRTX96_PRICE_10 
        );

        console.log("Liquidity added to pool at address: %s", address(utilityToken.poolAddress()));

        vm.stopBroadcast();
    }
}

/**
    forge script script/DeployUtilityToken.s.sol:DeployUtilityToken --fork-url $ETH_GOERLI_URL --private-key $PRIVATE_KEY --etherscan-api-key $ETHERSCAN_API_KEY 
    
    (optionally) --broadcast --verify
 */