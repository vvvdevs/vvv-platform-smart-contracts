# Notes for Admins Re: Operating the Contract

### Manual Actions
1. Adding investments
2. Setting investment parameters (signer, token addresses, allocation size, etc.)
3. Pausing/unpausing functions
4. Manually adding users' investment contributions made outside of the contract
5. Refunding Users
6. Transferring invested paymentToken(i.e. USDC) from the contract

### Automatic Actions
1. Calculation of each user's claimable amount at time of claim, based on their invested amount and already claimed amount

### Wallet Separation

Each role should be delegated to a separate hardware/multisig wallet that will handle one aspect of the contract's secure operation

1. PAUSER_ROLE: pause/unpause functions.
2. ADD_CONTRIBUTION_ROLE: manually add investment contributions (i.e. funds transferred to admins).
3. INVESTMENT_MANAGER_ROLE: add investments and set their parameters, such as signer address for invest-permission signatures, phase, payment/project token addresses, and payment/project token allocation.
4. PAYMENT_TOKEN_TRANSFER_ROLE: transfer paymentToken (i.e. usdc used to invest in the deal) to the destination address
5. REFUNDER_ROLE: refund users who invested in error or have extenuating circumstances requiring a refund. Must be done before any project tokens are deposited to avoid wrecking the distribution %s.
6. **DEFAULT_ADMIN_ROLE: add/remove addresses from roles. Critical to secure this. Should ideally be controlled by a secure multisig.**
