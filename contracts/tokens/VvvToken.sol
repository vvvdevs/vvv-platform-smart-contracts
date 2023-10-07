//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

/**
 * @title VvvToken
 * @author @vvvfund (@curi0n-s + @c0dejax)
 * @notice *removed mention of VVV while in development to avoid giving anything away on testnet*
 */

/**
Feature List:
1. ERC20Capped
2. Mintable by the owner or the vesting contract
3. Burnable by the owner
4. [?] add wallet/transaction limits?
 */

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ERC20Capped } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";

import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { INonfungiblePositionManager } from "../interfaces/INonfungiblePositionManagerSelected.sol";
import { IWETH9 } from "../interfaces/IWETH9.sol";

contract ERC20_UniV3 is ERC20Capped, Ownable {
    //==========================================================================================
    // STORAGE
    //==========================================================================================
    IUniswapV3Factory private constant UNIV3_FACTORY =
        IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    INonfungiblePositionManager private constant UNIV3_POSITION_MANAGER =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
    
    //GOERLI
    IWETH9 private constant WETH = IWETH9(0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6);
    //MAINNET
    // IWETH9 private constant WETH = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    address private positionRecipient;
    address public poolAddress;
    address public vestingContractAddress;
    bool public liquidityAddedToPool;
    uint24 public constant POOL_FEE_RATE = 3000; // 0.3% to LPs - recommended for most pools
    uint256 public immutable initialLiquiditySupply;

    event InitialLiquidityAdded(
        uint256 indexed _amount0,
        uint256 indexed _amount1,
        uint256 indexed _timestamp
    );

    error CallerIsNotOwnerOrVestingContract();
    error LiquidityAlreadyAdded();

    //==========================================================================================
    // SETUP - MINTING, POOL CREATION, LIQUIDITY ADDITION
    //==========================================================================================
    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _cap, 
        uint256 _initialDeployerSupply,
        uint256 _initialLiquiditySupply,
        address _positionRecipient
    ) ERC20(_name, _symbol) ERC20Capped(_cap) {
        //mint initial supply to deployer and to this contract
        _mint(msg.sender, _initialDeployerSupply);
        initialLiquiditySupply = _initialLiquiditySupply;
        _mint(address(this), initialLiquiditySupply);

        // Create Uniswap V3 Pool
        poolAddress = UNIV3_FACTORY.createPool(address(WETH), address(this), POOL_FEE_RATE);

        // Set position recipient for LP NFT
        positionRecipient = _positionRecipient;
    }

    modifier onlyOwnerOrVestingContract() {
        if (msg.sender != owner() && msg.sender != vestingContractAddress) {
            revert CallerIsNotOwnerOrVestingContract();
        }
        _;
    }

    ///@notice follows calls contained within the multicall that wouldbe carried out by uniswap v3 frontend when initializing a pool
    ///@notice requires input of sqrtPriceX96 for both token0 or token1 as the base token, depending on which is larger
    function addLiquidity(
        uint160 _sqrtPriceX96_01,
        uint160 _sqrtPriceX96_10
    ) external payable onlyOwner {
        if (liquidityAddedToPool) {
            revert LiquidityAlreadyAdded();
        }

        uint256 ethInput = msg.value;
        address token0 = address(WETH);
        address token1 = address(this);
        uint160 _sqrtPriceX96 = _sqrtPriceX96_01;
        if(token0 > token1){
            (token0, token1) = (token1, token0);
            _sqrtPriceX96 = _sqrtPriceX96_10;
        }

        // Approve WETH to spend this contract's ETH (TESTING)
        WETH.approve(address(UNIV3_POSITION_MANAGER), type(uint256).max);
        WETH.deposit{value: ethInput}();
 
        // Approve Uniswap V3 Position Manager to spend this contract's tokens / senders tokens (TESTING)
        _approve(address(this), address(UNIV3_POSITION_MANAGER), type(uint256).max);

        UNIV3_POSITION_MANAGER.createAndInitializePoolIfNecessary(
            token0,
            token1,
            POOL_FEE_RATE,
            _sqrtPriceX96
        );
        
        UNIV3_POSITION_MANAGER.mint(
            INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
                fee: POOL_FEE_RATE,
                tickLower: int24(-887220),
                tickUpper: int24(887220),
                amount0Desired: initialLiquiditySupply,
                amount1Desired: ethInput,
                amount0Min: 0,
                amount1Min: 0,
                recipient: positionRecipient,
                deadline: block.timestamp + 2 minutes
            })
        );

        UNIV3_POSITION_MANAGER.refundETH();

        liquidityAddedToPool = true;

        emit InitialLiquidityAdded(initialLiquiditySupply, ethInput, block.timestamp);
    }

    //==========================================================================================
    // INTERACTIONS BY OWNER OR VESTING CONTRACT
    //==========================================================================================

    function mint(address _to, uint256 _amount) public onlyOwnerOrVestingContract {
        _mint(_to, _amount);
    }

    function burn(uint256 _amount) public onlyOwner {
        _burn(msg.sender, _amount);
    }

    function setVestingContractAddress(address _vestingContractAddress)
        external
        onlyOwner
    {
        vestingContractAddress = _vestingContractAddress;
    }

    //?????????????????????????????????????????????????????????????????????????????????????????????????????????????????????
    //IF DESIRED, Idea for wallet/transaction limits - adds complexity, maybe can avoid depending on pool creation strategy
    //?????????????????????????????????????????????????????????????????????????????????????????????????????????????????????

    // address public constant DEAD = 0x000000000000000000000000000000000000dEaD;
    // uint256 public maxWalletBalance;
    // uint256 public maxTransactionAmount;
    // error MaxWalletOrTransactionAmountExceeded();

    // function _beforeTokenTransfer(
    //     address _from,
    //     address _to,
    //     uint256 _amount
    // ) internal override(ERC20) {
    //     if (
    //         liquidityAddedToPool &&
    //         _to != poolAddress &&
    //         _to != address(this) &&
    //         _to != address(DEAD) &&
    //         _amount + balanceOf(_to) > maxWalletBalance &&
    //         _amount + balanceOf(_to) > maxTransactionAmount
    //     ) {
    //         revert MaxWalletOrTransactionAmountExceeded();
    //     }

    //     super._beforeTokenTransfer(_from, _to, _amount);
    // }
}
