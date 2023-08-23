# Requirements

### Users Can:
1. invest a pre-approved amount of paymentToken (i.e. $USDC) in an investment of investmentId pending signature validation, which validates that the caller is a KYC'd address, and attempting to invest within the bounds set for that user.
2. claim their share of project tokens according to the amount of paymentToken they invested (i.e. invest 100 USDC in a pool of 1000 USDC, 1000 project tokens are deposited, user can immediately claim 100).
3. add/remove addresses from the network of addresses connected to their KYC'd address.


### Admins with * Role Can:
1. PAUSER_ROLE: pause/unpause functions.
2. ADD_CONTRIBUTION_ROLE: manually add investment contributions (i.e. funds transferred to admins). This includes importing previous investment data.
3. INVESTMENT_MANAGER_ROLE: add investments and set their parameters, such as signer address for invest-permission signatures, phase, payment/project token addresses, and payment/project token allocation.
4. PAYMENT_TOKEN_TRANSFER_ROLE: transfer paymentToken (i.e. usdc used to invest in the deal) to the destination address
5. REFUNDER_ROLE: refund users who invested in error or have extenuating circumstances requiring a refund. Must be done before any project tokens are deposited to avoid wrecking the distribution %s.
