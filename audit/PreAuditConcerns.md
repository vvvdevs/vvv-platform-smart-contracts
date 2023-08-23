#Pre-Audit Notes

### Assumptions
1. There will be no rounding-error-related problems when it comes to dividing up a user's claimable tokens / if there is rounding, it won't break any logic, and the amount will be negligible
2. Project tokens deposited to this contract should not be rebasing tokens/balances must remain static to ensure fair distribution of tokens to users regardless of time and frequency of token claims. Admins will ensure token is not rebasing.
3. Project tokens deposited to this contract should not be ERC777 tokens ideally, which could introduce more concerns about what the hook functions could do
4. User investment amounts will not exceed `type(uint120).max` and total investment amounts will not exceed `type(uint128).max`. InvestmendId will not exceed `type(uint16).max`, contributionPhase will not exceed `type(uint8).max`, project token claim amount will not exceed `type(uint240).max`.

### Potential Risks
1. Rounding errors - lots of tokens are deposited, many users claim small pieces expecting exact amounts, large token supply, some rounding occurrs, breaks logic somewhere and renders user unable to claim tokens
2. If a project token is ERC777, hooks could maybe pose risks. Haven't broken down how yet, just thinking out loud.

### Could Use Help/Maybe Would be Helpful
1. Places where implementing [FREI-PI](https://www.nascent.xyz/idea/youre-writing-require-statements-wrong) could be more secure, or at least any post-interactions checks to ensure even calls with malicious intent can only change state within the predetermined bounds. It seems this more-so applies to protocols which interact with external things like oracles but would like to see what may apply here.
2. Gas savings
3. Dividing admin role-based control and maximizing security for admin functions / splitting wallets for different roles, etc.
4. Validation about the approach used to validate signatures - is this by the book / any possibility of exploit?
5. There is old investment data from investments carried out manually - i.e. funds sent to wallet. As of now the data has to be stored with `batchManualAddContribution()` which will be expensive. This is OK, but if there is a simple way to do this more gas-efficiently, that would be welcome too.
6. Tips on secure operation / operating within the defined role separation. This will be handling a lot of $/tokens so want to be as secure as possible.