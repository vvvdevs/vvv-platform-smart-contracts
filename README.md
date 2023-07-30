## VVV Allocation Contracts

Branch for [VVV-21](https://linear.app/vvvfund/issue/VVV-21/remove-upgradability-form-the-contract): Remove upgradeability from the contract

### Patched Exploits

1. Exploit 1: \_params.signer in InvestParams could be used to exploit signature validation. Instead, used the investment's signer directly in the signature check, rather than having the user issue a signer address.
2. Exploit 2: correspondingKycAddress could be overridden as there were no checks to make sure the mapping value was not another address. added check to confirm that correspondingKycAddress[address] == address(0) before allowing a wallet to be added to network.

### Optimization Decisions as of July 29 2023

1. uint128 for investment-level paymentToken, uint120 for user-level paymentToken amounts
2. uint256 for user- and investment-level projectToken values - avoids any concern about rounding errors for weird amounts, or unusually large token supplies. This adds about 10k gas to the `claim()` calls, which with 4000usd ether, 100gwei gas would be like 4 usd, no biggie for the type of transactions we'll be facilitating
3. No use of unchecked logic, avoids any worry about InvestParams exploits in exchange for minimal gas savings - contributionLimitCheck could have been bypassed with a number which, when combined with existing invested balance could overflow uint256. This only forgoes about 700 gas per call to `invest()` or `claim()`

