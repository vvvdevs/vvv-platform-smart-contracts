## VVV Allocation Contracts

1. Setup Hardhat + Foundry Framework, including OZ upgradeable library
2. Add files, and placeholders for functions...started 6/5/23

## Questions so far

1. Is having a SAFT wallet for each project more secure or legally preferred than just depositing all ERC20 tokens to the InvestmentHandler contract directly? Why?
   --> Assuming it doesn't offer an advantage to start, keeping all in one contract (InvestmentHandlerSingleFile.sol)

## Seemingly Best Practices

1. Implement safeTransfer, safeERC20, etc. where possible.
2. Always use upgradeable versions of OZ contracts in an upgradeable contract!
   --> one question there: when to use IERC20 or IERC20Upgradeable when interacting with non-upgradeable contracts?
