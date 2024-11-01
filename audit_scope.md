## VVV Venture Capital Audit Scope

1. **Scope** 
	1. Venture Capital Investment and Claims (`contracts/vc/`)
		1.  `VVVVCInvestmentLedger.sol`
			1. Facilitates user investments in vVv's venture capital projects
		2.  `VVVVCTokenDistributor.sol`
			1. Facilitates users' token claims for vested tokens, based on prior investment
	3. nSLOC
		1. in `contract_metrics_for_audit.md`
2. **Smart Contract Requirements**
	1. Venture Capital Investment and Claims (`contracts/vc/`)
		1. `VVVVCInvestmentLedger.sol`
			1. Role-Restricted
				1. Can pause all investing via this contract
				2. Can manually add a record of investment contribution to an investment round
			2. User
				1. Can invest in an active investment round **only** when `investmentIsPaused` is `false`, within the contribution limits set in the signature supplied to the `invest` call, within the start and end times of the investment round, and when the input signature is valid, including the condition that it is not expired
				2. A fee (signature parameter defined off-chain) is only taken from the user-invested amount if the fee value is positive, and when a fee is taken, the correct amount is taken. Fees are set by an admin off-chain at the time of round creation in an out-of-scope centralized system, then validated as a signature parameter when a user calls `invest`.
				3. A user without the required role cannot access any functions gated via the `onlyAuthorized` modifier.
		3.  `VVVVCTokenDistributor.sol`
			1. Role-Restricted
				1. Can manually add claimable tokens for a specific user for a specific investment round
			2. User
				1. Can claim tokens vested by a project in the amount corresponding to their share of the currently vested tokens, given a valid signature is provided. At any point throughout the vesting, a user's claimable tokens will always be their share of the amount currently vested, such that no user will ever be unable to claim their share because another claimed before them.
				2. Can claim tokens for multiple rounds at once, corresponding to all investment rounds in which a user invested
				3. Can view the tokens claimed by any user for any investment round, as well as the total tokens claimed for any round
	2. Applies to All
		1. No aspect of any contract functionality is altered based on chain of deployment, whether Ethereum Mainnet, Avalanche C-Chain, Avalanche Evergreen Subnet, Base, or otherwise.
		2. All role-restricted functions are gated via the `onlyAuthorized` modifier from `contracts/auth/VVVAuthorizationRegistryChecker.sol`, such that the calling address must possess the specified role for that particular function. Hence, no unauthorized user can call any function meant for role-restricted users.
