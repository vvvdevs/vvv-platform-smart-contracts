## VVV Allocation Contracts

Branch for adding fixes by Marko

### Notes for current fixes.

1. Exploit 1: _params.signer in InvestParams could be used to exploit signature validation. Instead, used the investment's signer directly in the signature check, rather than having the user issue a signer address. 
2. Exploit 2: correspondingKycAddress could be overridden as there were no checks to make sure the mapping value was not another address. added check to confirm that correspondingKycAddress[address] == address(0) before allowing a wallet to be added to network.