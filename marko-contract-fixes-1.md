2. `_signatureCheck` function - shouldn't `_params.signer` be checked here to make sure it corresponds to a trusted address? Otherwise anyone can forge signatures using any address as signer.
3. can investment attached to a specific KYC wallet come from any wallet, regardless of whether it is in the KYC wallet's network or not? e.g. KYC (wallet A) has wallets B and C in its network. Can wallet D invest on behalf of the KYC Wallet (A) even if it's not in its network?
4. For example, wallet A adds wallet B to its network
   then correspondingKycAddress[B] == A, but if wallet C invokes the method with the same parameter
   then correspondingKycAddress[B] == C
   I see the correspondingKycAddress is currently not used anywhere but if it will be used in the future it will be a problem. Can a wallet belong to multiple networks? - `addWalletToKycWalletNetwork` - this method can be exploited because you can override the `correspondingKycAddress` entry for any wallet address.
5. `ContributionPhase` struct - as asked in Miro, do we need this struct at all? If the contribution phase is going to be updated manually via the `setInvestmentContributionPhase` then the startTime and endTime fields are unnecessary rendering the entire ContributionPhase struct also unnecessary.
6. `UserInvestment` struct - are tokenWithdrawAmounts and tokenWithdrawTimestamps needed, considering this info will be available from the blockchain transaction log? If they are needed for some reason then why not also keep track of investmentAmounts and investmentTimestamps?
7. `_paymentTokenAllowanceCheck` - it checks for kycAddress's allowance instead of `msg.sender`
8. `refundUser` - should there be a check in regards with how much user claimed already, i.e. not allow refunds for the % of the investment that's already been claimed. E.g. if user invested in total X amount which granted him right to claim 10% of project tokens and he claimed 5% then he can be refunded max. 50% of the X (total investment). Is this check going to be performed off-chain?
9. `claim` function - `UserInvestment storage userInvestment = userInvestments[_tokenRecipient][_investmentId];` - userInvestment is fetched based on `_tokenRecipient` instead of `_kycAddress`
10. maybe also add `setInvestmentPaymentTokenAddress` method?
