# Report


## Gas Optimizations


| |Issue|Instances|
|-|:-|:-:|
| [GAS-1](#GAS-1) | Using bools for storage incurs overhead | 1 |
| [GAS-2](#GAS-2) | For Operations that will not overflow, you could use unchecked | 48 |
| [GAS-3](#GAS-3) | `++i` costs less gas than `i++`, especially when it's used in `for`-loops (`--i`/`i--` too) | 1 |
### <a name="GAS-1"></a>[GAS-1] Using bools for storage incurs overhead
Use uint256(1) and uint256(2) for true/false to avoid a Gwarmaccess (100 gas), and to avoid Gsset (20000 gas) when changing from ‘false’ to ‘true’, after having been ‘true’ in the past. See [source](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/58f635312aa21f947cae5f8578638a85aa2519f5/contracts/security/ReentrancyGuard.sol#L23-L27).

*Instances (1)*:
```solidity
File: InvestmentHandler.sol

101:     mapping(address => mapping(address => bool)) public isInKycAddressNetwork;

```

### <a name="GAS-2"></a>[GAS-2] For Operations that will not overflow, you could use unchecked

*Instances (48)*:
```solidity
File: InvestmentHandler.sol

12: import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";

12: import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";

12: import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";

13: import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

13: import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

13: import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

14: import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

14: import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

14: import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

15: import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

15: import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

15: import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

15: import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

16: import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";

16: import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";

16: import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";

16: import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";

17: import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

17: import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

17: import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

17: import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

18: import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

18: import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

18: import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

18: import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

19: import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

19: import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

19: import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

19: import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

19: import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

20: import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

20: import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

20: import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

20: import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

228:             userInvestment.totalTokensClaimed += _claimAmount;

229:             investment.totalTokensClaimed += _claimAmount;            

250:             userInvestment.totalInvestedPaymentToken += uint136(_params.thisInvestmentAmount);

251:             investment.totalInvestedPaymentToken += _params.thisInvestmentAmount;

253:             userInvestment.pledgeDebt = uint120(_params.maxInvestableAmount - userInvestment.totalInvestedPaymentToken);

339:             uint userBaseClaimableTokens = Math.mulDiv(contractTokenBalance+totalTokensClaimed, userTotalInvestedPaymentToken, totalInvestedPaymentToken);

340:             claimableTokens = uint128(userBaseClaimableTokens - userTokensClaimed);

393:            proposedTotalContribution = _params.thisInvestmentAmount + userInvestments[_params.kycAddress][_params.investmentId].totalInvestedPaymentToken;

414:         investments[++latestInvestmentId] = Investment({

414:         investments[++latestInvestmentId] = Investment({

485:             userInvestments[_kycAddress][_investmentId].totalInvestedPaymentToken += uint136(_paymentTokenAmount);

486:             investments[_investmentId].totalInvestedPaymentToken += _paymentTokenAmount;            

503:             userInvestments[_kycAddress][_investmentId].totalInvestedPaymentToken -= uint136(_paymentTokenAmount);

504:             investments[_investmentId].totalInvestedPaymentToken -= _paymentTokenAmount;            

```

### <a name="GAS-3"></a>[GAS-3] `++i` costs less gas than `i++`, especially when it's used in `for`-loops (`--i`/`i--` too)
*Saves 5 gas per loop*

*Instances (1)*:
```solidity
File: InvestmentHandler.sol

414:         investments[++latestInvestmentId] = Investment({

```


## Low Issues


| |Issue|Instances|
|-|:-|:-:|
| [L-1](#L-1) |  `abi.encodePacked()` should not be used with dynamic types when passing the result to a hash function such as `keccak256()` | 2 |
### <a name="L-1"></a>[L-1]  `abi.encodePacked()` should not be used with dynamic types when passing the result to a hash function such as `keccak256()`
Use `abi.encode()` instead which will pad items to 32 bytes, which will [prevent hash collisions](https://docs.soliditylang.org/en/v0.8.13/abi-spec.html#non-standard-packed-mode) (e.g. `abi.encodePacked(0x123,0x456)` => `0x123456` => `abi.encodePacked(0x1,0x23456)`, but `abi.encode(0x123,0x456)` => `0x0...1230...456`). "Unless there is a compelling reason, `abi.encode` should be preferred". If there is only one argument to `abi.encodePacked()` it can often be cast to `bytes()` or `bytes32()` [instead](https://ethereum.stackexchange.com/questions/30912/how-to-compare-strings-in-solidity#answer-82739).
If all arguments are strings and or bytes, `bytes.concat()` should be used instead

*Instances (2)*:
```solidity
File: InvestmentHandler.sol

368:                 ECDSA.toEthSignedMessageHash(keccak256(abi.encodePacked(_params.kycAddress, _params.maxInvestableAmount, _params.userPhase))),

518:                 ECDSA.toEthSignedMessageHash(keccak256(abi.encodePacked(_user, _maxInvestableAmount, _userPhase))),

```


## Medium Issues


| |Issue|Instances|
|-|:-|:-:|
| [M-1](#M-1) | Centralization Risk for trusted owners | 10 |
### <a name="M-1"></a>[M-1] Centralization Risk for trusted owners

#### Impact:
Contracts have owners with privileged rights to perform admin tasks and need to be trusted to not perform malicious updates or drain funds.

*Instances (10)*:
```solidity
File: InvestmentHandler.sol

23:     AccessControl,

413:     ) public nonReentrant onlyRole(INVESTMENT_MANAGER_ROLE) {

431:     function setInvestmentContributionPhase(uint _investmentId, uint8 _investmentPhase) public payable onlyRole(INVESTMENT_MANAGER_ROLE) {

440:     function setInvestmentPaymentTokenAddress(uint _investmentId, address _paymentTokenAddress) public payable onlyRole(INVESTMENT_MANAGER_ROLE) {

452:     function setInvestmentProjectTokenAddress(uint _investmentId, address projectTokenAddress) public payable onlyRole(INVESTMENT_MANAGER_ROLE) {

460:     function setInvestmentProjectTokenAllocation(uint _investmentId, uint128 totalTokensAllocated) public payable onlyRole(INVESTMENT_MANAGER_ROLE) {

469:     function pause() external payable onlyRole(INVESTMENT_MANAGER_ROLE) {

473:     function unPause() external payable onlyRole(INVESTMENT_MANAGER_ROLE) {

483:     function manualAddContribution(address _kycAddress, uint _investmentId, uint120 _paymentTokenAmount) public payable nonReentrant onlyRole(ADD_CONTRIBUTION_AND_REFUND_ROLE) {

498:     function refundUser(address _kycAddress, uint _investmentId, uint120 _paymentTokenAmount) public payable nonReentrant onlyRole(ADD_CONTRIBUTION_AND_REFUND_ROLE) {

```

