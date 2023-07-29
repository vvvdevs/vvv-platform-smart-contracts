# Report


## Gas Optimizations


| |Issue|Instances|
|-|:-|:-:|
| [GAS-1](#GAS-1) | Using bools for storage incurs overhead | 1 |
| [GAS-2](#GAS-2) | For Operations that will not overflow, you could use unchecked | 60 |
| [GAS-3](#GAS-3) | Functions guaranteed to revert when called by normal users can be marked `payable` | 8 |
| [GAS-4](#GAS-4) | `++i` costs less gas than `i++`, especially when it's used in `for`-loops (`--i`/`i--` too) | 1 |
### <a name="GAS-1"></a>[GAS-1] Using bools for storage incurs overhead
Use uint256(1) and uint256(2) for true/false to avoid a Gwarmaccess (100 gas), and to avoid Gsset (20000 gas) when changing from ‘false’ to ‘true’, after having been ‘true’ in the past. See [source](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/58f635312aa21f947cae5f8578638a85aa2519f5/contracts/security/ReentrancyGuard.sol#L23-L27).

*Instances (1)*:
```solidity
File: InvestmentHandler.sol

99:     mapping(address => mapping(address => bool)) public isInKycAddressNetwork;

```

### <a name="GAS-2"></a>[GAS-2] For Operations that will not overflow, you could use unchecked

*Instances (60)*:
```solidity
File: InvestmentHandler.sol

11: import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";

11: import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";

11: import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";

12: import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

12: import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

12: import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

13: import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

13: import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

13: import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

14: import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

14: import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

14: import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

14: import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

15: import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";

15: import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";

15: import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";

15: import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";

16: import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

16: import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

16: import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

16: import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

17: import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

17: import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

17: import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

17: import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

18: import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

18: import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

18: import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

18: import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

18: import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

19: import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

19: import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

19: import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

19: import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

221:         userInvestment.totalTokensClaimed += _claimAmount;

222:         investment.totalTokensClaimed += _claimAmount;

241:         userInvestment.totalInvestedPaymentToken += _params.thisInvestmentAmount;

242:         investment.totalInvestedPaymentToken += _params.thisInvestmentAmount;

247:         userInvestment.pledgeDebt = _params.maxInvestableAmount - userInvestment.totalInvestedPaymentToken;

326:         this will be a bit spicy - this will calculate claimable tokens, 

333:         [confirm] contract balance of token + total tokens claimed is used to preserve user's claimable balance regardless of order

335:         no checks for math yet, but this assumes that (totalTokensAllocated*userTotalInvestedPaymentToken)/totalInvestedPaymentToken

335:         no checks for math yet, but this assumes that (totalTokensAllocated*userTotalInvestedPaymentToken)/totalInvestedPaymentToken

339:         i.e. consider that we get 1 Investment Token for 1000 Payment Tokens (both 18 decimals), will rounding/truncation errors get significant?

348:         uint userBaseClaimableTokens = Math.mulDiv(contractTokenBalance+totalTokensClaimed, userTotalInvestedPaymentToken, totalInvestedPaymentToken);

350:         return userBaseClaimableTokens - userTokensClaimed;

396:         return _params.thisInvestmentAmount + userInvestments[_params.kycAddress][_params.investmentId].totalInvestedPaymentToken <= _params.maxInvestableAmount;

415:         investments[++latestInvestmentId] = Investment({

415:         investments[++latestInvestmentId] = Investment({

485:         userInvestments[_kycAddress][_investmentId].totalInvestedPaymentToken += _paymentTokenAmount;

486:         investments[_investmentId].totalInvestedPaymentToken += _paymentTokenAmount;

500:         userInvestments[_kycAddress][_investmentId].totalInvestedPaymentToken -= _paymentTokenAmount;

501:         investments[_investmentId].totalInvestedPaymentToken -= _paymentTokenAmount;

```

```solidity
File: mock/MockERC20.sol

4: import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

4: import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

4: import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

4: import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

10:         uint initialSupply = 1000000000 * 10 ** decimals;

10:         uint initialSupply = 1000000000 * 10 ** decimals;

10:         uint initialSupply = 1000000000 * 10 ** decimals;

```

### <a name="GAS-3"></a>[GAS-3] Functions guaranteed to revert when called by normal users can be marked `payable`
If a function modifier such as `onlyOwner` is used, the function will revert if a normal user tries to pay the function. Marking the function as `payable` will lower the gas cost for legitimate callers because the compiler will not include checks for whether a payment was provided.

*Instances (8)*:
```solidity
File: InvestmentHandler.sol

432:     function setInvestmentContributionPhase(uint _investmentId, uint _investmentPhase) public onlyRole(MANAGER_ROLE) {

441:     function setInvestmentPaymentTokenAddress(uint _investmentId, address _paymentTokenAddress) public onlyRole(MANAGER_ROLE) {

453:     function setInvestmentProjectTokenAddress(uint _investmentId, address projectTokenAddress) public onlyRole(MANAGER_ROLE) {

461:     function setInvestmentProjectTokenAllocation(uint _investmentId, uint totalTokensAllocated) public onlyRole(MANAGER_ROLE) {

470:     function pause() external onlyRole(MANAGER_ROLE) {

474:     function unPause() external onlyRole(MANAGER_ROLE) {

484:     function manualAddContribution(address _kycAddress, uint _investmentId, uint _paymentTokenAmount) public nonReentrant onlyRole(MANAGER_ROLE) {

496:     function refundUser(address _kycAddress, uint _investmentId, uint _paymentTokenAmount) public nonReentrant onlyRole(MANAGER_ROLE) {

```

### <a name="GAS-4"></a>[GAS-4] `++i` costs less gas than `i++`, especially when it's used in `for`-loops (`--i`/`i--` too)
*Saves 5 gas per loop*

*Instances (1)*:
```solidity
File: InvestmentHandler.sol

415:         investments[++latestInvestmentId] = Investment({

```


## Non Critical Issues


| |Issue|Instances|
|-|:-|:-:|
| [NC-1](#NC-1) | Functions not used internally could be marked external | 1 |
### <a name="NC-1"></a>[NC-1] Functions not used internally could be marked external

*Instances (1)*:
```solidity
File: mock/MockERC20.sol

14:     function mint(address to, uint256 amount) public {

```


## Low Issues


| |Issue|Instances|
|-|:-|:-:|
| [L-1](#L-1) |  `abi.encodePacked()` should not be used with dynamic types when passing the result to a hash function such as `keccak256()` | 2 |
| [L-2](#L-2) | Do not use deprecated library functions | 2 |
### <a name="L-1"></a>[L-1]  `abi.encodePacked()` should not be used with dynamic types when passing the result to a hash function such as `keccak256()`
Use `abi.encode()` instead which will pad items to 32 bytes, which will [prevent hash collisions](https://docs.soliditylang.org/en/v0.8.13/abi-spec.html#non-standard-packed-mode) (e.g. `abi.encodePacked(0x123,0x456)` => `0x123456` => `abi.encodePacked(0x1,0x23456)`, but `abi.encode(0x123,0x456)` => `0x0...1230...456`). "Unless there is a compelling reason, `abi.encode` should be preferred". If there is only one argument to `abi.encodePacked()` it can often be cast to `bytes()` or `bytes32()` [instead](https://ethereum.stackexchange.com/questions/30912/how-to-compare-strings-in-solidity#answer-82739).
If all arguments are strings and or bytes, `bytes.concat()` should be used instead

*Instances (2)*:
```solidity
File: InvestmentHandler.sol

373:                 ECDSA.toEthSignedMessageHash(keccak256(abi.encodePacked(_params.kycAddress, _params.maxInvestableAmount, _params.userPhase))),

513:                 ECDSA.toEthSignedMessageHash(keccak256(abi.encodePacked(_user, _maxInvestableAmount, _userPhase))),

```

### <a name="L-2"></a>[L-2] Do not use deprecated library functions

*Instances (2)*:
```solidity
File: InvestmentHandler.sol

139:         _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);

140:         _setupRole(MANAGER_ROLE, msg.sender);

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

22:     AccessControl,

414:     ) public nonReentrant onlyRole(MANAGER_ROLE) {

432:     function setInvestmentContributionPhase(uint _investmentId, uint _investmentPhase) public onlyRole(MANAGER_ROLE) {

441:     function setInvestmentPaymentTokenAddress(uint _investmentId, address _paymentTokenAddress) public onlyRole(MANAGER_ROLE) {

453:     function setInvestmentProjectTokenAddress(uint _investmentId, address projectTokenAddress) public onlyRole(MANAGER_ROLE) {

461:     function setInvestmentProjectTokenAllocation(uint _investmentId, uint totalTokensAllocated) public onlyRole(MANAGER_ROLE) {

470:     function pause() external onlyRole(MANAGER_ROLE) {

474:     function unPause() external onlyRole(MANAGER_ROLE) {

484:     function manualAddContribution(address _kycAddress, uint _investmentId, uint _paymentTokenAmount) public nonReentrant onlyRole(MANAGER_ROLE) {

496:     function refundUser(address _kycAddress, uint _investmentId, uint _paymentTokenAmount) public nonReentrant onlyRole(MANAGER_ROLE) {

```

