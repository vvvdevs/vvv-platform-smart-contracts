// SPDX-License-Identifier: MIT

// This is a tax token used for degen projects. It works for swapping taxed tokens back to eth. 
// One vulnerability is that the slippage tolerance for swapping back to eth internally is 0

pragma solidity 0.8.21;

interface IERC20 {
    function totalSupply() external view returns (uint256);

    function decimals() external view returns (uint8);

    function symbol() external view returns (string memory);

    function name() external view returns (string memory);

    function getOwner() external view returns (address);

    function balanceOf(address account) external view returns (uint256);

    function transfer(
        address recipient,
        uint256 amount
    ) external returns (bool);

    function allowance(
        address _owner,
        address spender
    ) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
}

abstract contract Context {
    function _msgSender() internal view virtual returns (address payable) {
        return payable(msg.sender);
    }

    function _msgData() internal view virtual returns (bytes memory) {
        this;
        return msg.data;
    }
}

contract Ownable is Context {
    address public _owner;

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    constructor() {
        address msgSender = _msgSender();
        _owner = msgSender;
        authorizations[_owner] = true;
        emit OwnershipTransferred(address(0), msgSender);
    }

    mapping(address => bool) internal authorizations;

    function owner() public view returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(_owner == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(
            newOwner != address(0),
            "Ownable: new owner is the zero address"
        );
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

interface IUniswapV2Factory {
    function createPair(
        address tokenA,
        address tokenB
    ) external returns (address pair);
}

interface IUniswapV2Router02 {
    function factory() external pure returns (address);

    function WETH() external pure returns (address);

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);

    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    )
        external
        payable
        returns (uint amountToken, uint amountETH, uint liquidity);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable;

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
}

interface IUniswapV2Pair {
    function sync() external;
}

contract ERC20_FeeOnBuySell is Ownable, IERC20 {
    IUniswapV2Router02 public router;

    address public pair;
    address WETH;
    address constant DEAD = 0x000000000000000000000000000000000000dEaD;
    address constant ZERO = 0x0000000000000000000000000000000000000000;
    address private outputAddress;

    bool liquidityAdded;
    bool inSwap;

    string public tokenName;
    string public tokenSymbol;

    uint256 private constant DENOMINATOR = 10000;
    uint256 public totalTokenSupply = 10_000_000 * 1e18;
    uint256 public maxTxAmount = (totalTokenSupply * 50) / DENOMINATOR;
    uint256 public maxWalletTokens = (totalTokenSupply * 50) / DENOMINATOR;
    uint256 public sellTax = 3000;
    uint256 public buyTax = 3000;
    uint256 public swapThreshold = (totalTokenSupply * 50) / DENOMINATOR;
    uint256 public lpAddSlippageTolerance = 1000; // 10% slippage tolerance
    uint256 public swapSlippageTolerance = 1000;

    mapping(address => uint256) _balances;
    mapping(address => mapping(address => uint256)) _allowances;
    mapping(address => bool) _isExemptFromFees;
    mapping(address => bool) _isExemptFromMaxTx;

    event ClearTokenAndEth(address tokenAddress, uint256 tokenAmount, uint256 ethAmount);
    event MaxWalletTokensSet(uint256 maxWalletTokens);

    error InsufficientBalance();
    error TransactionLimitExceeded();
    error TransferFailed();
    error WalletLimitExceeded();
    
    constructor(
        string memory _tokentokenName,
        string memory _tokenSymbol,
        address _outputAddress,
        address[] memory _teamAddresses,
        uint256[] memory _teamAmounts,
        address _router
    ) payable {
        router = IUniswapV2Router02(_router);
        WETH = router.WETH();
        pair = IUniswapV2Factory(router.factory()).createPair(
            WETH,
            address(this)
        );

        outputAddress = _outputAddress;
        tokenName = _tokentokenName;
        tokenSymbol = _tokenSymbol;

        _allowances[address(this)][address(router)] = type(uint256).max;

        _isExemptFromFees[msg.sender] = true;
        _isExemptFromFees[address(this)] = true;
        _isExemptFromMaxTx[msg.sender] = true;
        _isExemptFromMaxTx[pair] = true;
        _isExemptFromMaxTx[outputAddress] = true;
        _isExemptFromMaxTx[address(this)] = true;

        _balances[address(this)] = (totalTokenSupply * 9000) / DENOMINATOR;

        emit Transfer(
            address(0),
            address(this),
            (totalTokenSupply * 9000) / DENOMINATOR
        );

        for (uint256 i = 0; i < _teamAddresses.length; i++) {
            _balances[_teamAddresses[i]] = _teamAmounts[i];
            emit Transfer(address(0), _teamAddresses[i], _teamAmounts[i]);
        }
    }

    modifier preventRecursiveSwap() {
        inSwap = true;
        _;
        inSwap = false;
    }

    function addLiquidity() public onlyOwner {
        //add liquidity
        _allowances[address(this)][address(router)] = type(uint256).max;
        emit Approval(address(this), address(router), type(uint256).max);

        uint256 minTokens = (totalTokenSupply * (DENOMINATOR - lpAddSlippageTolerance)) / DENOMINATOR;
        uint256 minETH = address(this).balance;

        router.addLiquidityETH{value: address(this).balance}(
            address(this),
            balanceOf(address(this)),
            minTokens, 
            minETH,
            msg.sender,
            block.timestamp
        );

        liquidityAdded = true;
    }

    receive() external payable {}

    function totalSupply() external view override returns (uint256) {
        return totalTokenSupply;
    }

    function decimals() external pure override returns (uint8) {
        return uint8(18);
    }

    function symbol() external view override returns (string memory) {
        return tokenSymbol;
    }

    function name() external view override returns (string memory) {
        return tokenName;
    }

    function getOwner() external view override returns (address) {
        return owner();
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    function nonBurnedSupply() public view returns (uint256) {
        return totalTokenSupply - balanceOf(DEAD) - balanceOf(ZERO);
    }

    function allowance(
        address holder,
        address spender
    ) external view override returns (uint256) {
        return _allowances[holder][spender];
    }

    function approve(
        address spender,
        uint256 amount
    ) public override returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function approveMax(address spender) external returns (bool) {
        return approve(spender, type(uint256).max);
    }

    function transfer(
        address recipient,
        uint256 amount
    ) external override returns (bool) {
        return _transferFrom(msg.sender, recipient, amount);
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external override returns (bool) {
        if (_allowances[sender][msg.sender] != type(uint256).max && _allowances[sender][msg.sender] >= amount) {
            _allowances[sender][msg.sender] -= amount;
        }
        return _transferFrom(sender, recipient, amount);
    }

    function setMaxWalletTokens(uint256 maxWalletTokens_) external onlyOwner {
        require(maxWalletTokens_ >= 1);
        maxWalletTokens = maxWalletTokens_;
        emit MaxWalletTokensSet(maxWalletTokens);
    }

    function removeLimits() external onlyOwner {
        maxTxAmount = totalTokenSupply;
        maxWalletTokens = totalTokenSupply;
    }

    function _transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) internal returns (bool) {
        if (inSwap) {
            return _basicTransfer(sender, recipient, amount);
        }

        if (
            liquidityAdded &&
            !authorizations[sender] &&
            recipient != address(this) &&
            recipient != address(DEAD) &&
            recipient != pair &&
            recipient != outputAddress &&
            !_isExemptFromMaxTx[recipient]
        ) {
            uint256 heldTokens = balanceOf(recipient);

            if((heldTokens + amount) > maxWalletTokens){
                revert WalletLimitExceeded();
            }
        }

        if (amount > maxTxAmount && !_isExemptFromMaxTx[sender]) {
            revert TransactionLimitExceeded();
        }

        if (shouldSwapBack()) {
            swapBack();
        }

        if (_balances[sender] < amount) {
            revert InsufficientBalance();
        }
        _balances[sender] -= amount;

        uint256 amountReceived = (_isExemptFromFees[sender] ||
            _isExemptFromFees[recipient])
            ? amount
            : takeFee(sender, amount, recipient);
        _balances[recipient] += amountReceived;

        emit Transfer(sender, recipient, amountReceived);
        return true;
    }

    function _basicTransfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal returns (bool) {
        if(_balances[sender] < amount) {
            revert InsufficientBalance();
        }
        _balances[sender] -= amount;
        _balances[recipient] += amount;
        emit Transfer(sender, recipient, amount);
        return true;
    }

    function takeFee(
        address sender,
        uint256 amount,
        address recipient
    ) internal returns (uint256) {
        uint256 thisTax = 0;
        if (recipient == pair) {
            thisTax = sellTax;
        } else if (sender == pair) {
            thisTax = buyTax;
        }

        uint256 feeAmount = (amount * thisTax) / DENOMINATOR;

        _balances[address(this)] += feeAmount;
        emit Transfer(sender, address(this), feeAmount);

        return amount - feeAmount;
    }

    function shouldSwapBack() internal view returns (bool) {
        return
            msg.sender != pair &&
            liquidityAdded &&
            !inSwap &&
            _balances[address(this)] >= swapThreshold;
    }

    function setFees(
        uint256 _buyTax,
        uint256 _sellTax
    ) public onlyOwner {
        buyTax = _buyTax;
        sellTax = _sellTax;
    }

    function swapBack() internal preventRecursiveSwap {
        uint256 amountToSwap = balanceOf(address(this));

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = WETH;

        uint256 amountOutmMin = (amountToSwap * (DENOMINATOR - swapSlippageTolerance)) / DENOMINATOR;

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            amountToSwap,
            amountOutmMin,
            path,
            outputAddress,
            block.timestamp
        );
    }

    function setOutputAddress(address _outputAddress) external onlyOwner {
        outputAddress = _outputAddress;
    }

    function setSwapBackSettings(uint256 _amount) external onlyOwner {
        swapThreshold = _amount;
    }

    function setLpAddSlippage(uint256 _slippage) external onlyOwner {
        lpAddSlippageTolerance = _slippage;
    }

    function setSwapBackSlippage(uint256 _slippage) external onlyOwner {
        swapSlippageTolerance = _slippage;
    }

    function clearTokenAndEth(
        address _tokenAddress
    ) external returns (bool success) {
        uint256 contractEthBalance = address(this).balance;
        uint256 contractTokenBalance = IERC20(_tokenAddress).balanceOf(
            address(this)
        );

        bool tokenTransferSuccess = IERC20(_tokenAddress).transfer(
            outputAddress,
            contractTokenBalance
        );

        (bool ethTransferSuccess, ) = payable(outputAddress).call{
            value: contractEthBalance
        }("");

        if(!tokenTransferSuccess || !ethTransferSuccess){
            revert TransferFailed();
        }

        emit ClearTokenAndEth(_tokenAddress, contractTokenBalance, contractEthBalance);
        return true;
    }
}