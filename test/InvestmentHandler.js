/**
 *
 * Tests Process of:
 * 1. Create new investment
 * 2. Sign address and amount for user
 * 3. Invest USDC with signature check
 * 4. Manager deposits project token
 * 5. User Claims Project token (cases for all with kyc address, and one with all different wallets)
 *
 */

const { ethers, upgrades } = require("hardhat");
const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");
const { expect } = require("chai");
require("dotenv").config();

const logging = false;

describe("InvestmentHandler", function () {
    async function setupFixture() {
        const provider = new ethers.providers.JsonRpcProvider();

        const signerPre = ethers.Wallet.createRandom();
        const spk = signerPre.privateKey;
        const signer = new ethers.Wallet(spk, provider);

        const [manager, user, user2, depositNetworkAddress, claimCallerNetworkAddress, claimRecipientNetworkAddress] = await ethers.getSigners();

        let MockERC20 = await ethers.getContractFactory("MockERC20");
        MockERC20 = await MockERC20.connect(manager);
        const mockProjectToken = await MockERC20.deploy([18]);
        await mockProjectToken.deployed();
        const mockUsdc = await MockERC20.deploy([18]);
        await mockUsdc.deployed();

        let mint_usdc_to_user = await mockUsdc.connect(user).mint(user.address, ethers.utils.parseEther("10000"));
        await mint_usdc_to_user.wait();

        let mint_usdc_to_user2 = await mockUsdc.connect(user2).mint(user2.address, ethers.utils.parseEther("10000"));
        await mint_usdc_to_user2.wait();

        let mint_usdc_to_depositNetworkAddress = await mockUsdc.connect(depositNetworkAddress).mint(depositNetworkAddress.address, ethers.utils.parseEther("10000"));
        await mint_usdc_to_depositNetworkAddress.wait();

        let mint_usdc_to_claimNetworkAddress = await mockUsdc.connect(claimCallerNetworkAddress).mint(claimCallerNetworkAddress.address, ethers.utils.parseEther("10000"));
        await mint_usdc_to_claimNetworkAddress.wait();

        let InvestmentHandler = await ethers.getContractFactory("InvestmentHandler");
        InvestmentHandler = await InvestmentHandler.connect(manager);
        const investmentHandler = await upgrades.deployProxy(InvestmentHandler, [], {
            initializer: "initialize",
        });
        await investmentHandler.deployed();

        const testInvestmentStablecoin = mockUsdc.address; //USDC
        const testProjectTokenAddress = mockProjectToken.address; //USDC

        const pledgeAmount = ethers.utils.parseEther("1000");
        const depositAmount = ethers.utils.parseEther("0.000123");
        const testInvestmentUsdAlloc = ethers.utils.parseEther("10000");
        const testInvestmentTokensAlloc = ethers.utils.parseEther("100000");
        const testClaimAmount = ethers.utils.parseEther("1000");
        const testPledgedAmount = ethers.utils.parseEther("1000");
        const approvalValue = ethers.utils.parseEther("10000");

        const userPhaseIndex = 2; //0:closed, 1:whale, 2:shark, 3:fcfs

        if (logging) {
            console.log("MockProjectToken deployed to:", mockProjectToken.address);
            console.log("MockUsdc deployed to:", mockUsdc.address);
            console.log("InvestmentHandler deployed to:", investmentHandler.address);
        }

        return {
            investmentHandler,
            mockProjectToken,
            mockUsdc,
            signer,
            manager,
            user,
            user2,
            depositNetworkAddress,
            claimCallerNetworkAddress,
            claimRecipientNetworkAddress,
            provider,
            pledgeAmount,
            depositAmount,
            testInvestmentStablecoin,
            testInvestmentUsdAlloc,
            testInvestmentTokensAlloc,
            testProjectTokenAddress,
            testClaimAmount,
            testPledgedAmount,
            approvalValue,
            userPhaseIndex,
        };
    }

    describe("Deployment", function () {
        it("Should set the right owner", async function () {
            const { investmentHandler, manager } = await loadFixture(setupFixture);
            expect(await investmentHandler.deployer()).to.equal(manager.address);
        });
    });

    describe("Add/Remove Address To/From KYC Address Network", function () {
        it("should add a new address to the KYC wallet network", async function () {
            const { investmentHandler, user, depositNetworkAddress } = await loadFixture(setupFixture);
            const add_address = await investmentHandler.connect(user).addAddressToKycAddressNetwork(depositNetworkAddress.address);
            expect(add_address).to.emit(investmentHandler, "AddressAddedToKycAddressNetwork").withArgs(user.address, depositNetworkAddress.address);
            expect(await investmentHandler.isInKycAddressNetwork(user.address, depositNetworkAddress.address)).to.equal(true);
            expect(await investmentHandler.correspondingKycAddress(depositNetworkAddress.address)).to.equal(user.address);
        });
        it("should remove an address from the KYC wallet network", async function () {
            const { investmentHandler, user, depositNetworkAddress } = await loadFixture(setupFixture);
            const add_address = await investmentHandler.connect(user).addAddressToKycAddressNetwork(depositNetworkAddress.address);
            expect(add_address).to.emit(investmentHandler, "AddressAddedToKycAddressNetwork").withArgs(user.address, depositNetworkAddress.address);
            expect(await investmentHandler.isInKycAddressNetwork(user.address, depositNetworkAddress.address)).to.equal(true);
            expect(await investmentHandler.correspondingKycAddress(depositNetworkAddress.address)).to.equal(user.address);

            const remove_address = await investmentHandler.connect(user).removeAddressFromKycAddressNetwork(depositNetworkAddress.address);
            expect(remove_address).to.emit(investmentHandler, "AddressRemovedFromKycAddressNetwork").withArgs(user.address, depositNetworkAddress.address);
            expect(await investmentHandler.isInKycAddressNetwork(user.address, depositNetworkAddress.address)).to.equal(false);
            expect(await investmentHandler.correspondingKycAddress(depositNetworkAddress.address)).to.equal(ethers.constants.AddressZero);
        });
    });

    //test for creation of new investment, then signing of address and amount for user, then investing USDC with signature check, then manager deposits project token, then user claims project token
    describe("Investment Process", function () {
        it("Should add investment, then invest, token deposit, and claim all from kyc wallet as sender", async function () {
            const {
                investmentHandler,
                signer,
                manager,
                pledgeAmount,
                depositAmount,
                user,
                testProjectTokenAddress,
                testInvestmentTokensAlloc,
                testClaimAmount,
                testInvestmentStablecoin,
                testInvestmentUsdAlloc,
                mockUsdc,
                mockProjectToken,
                approvalValue,
                userPhaseIndex,
            } = await loadFixture(setupFixture);

            const add_investment = await investmentHandler.connect(manager).addInvestment(signer.address, testInvestmentStablecoin, testInvestmentUsdAlloc);
            await add_investment.wait();

            const investmentId = await investmentHandler.latestInvestmentId();

            const set_phase_to_shark = await investmentHandler.connect(manager).setInvestmentContributionPhase(investmentId, 2);
            await set_phase_to_shark.wait();

            const signature = await signDeposit(signer, user, pledgeAmount, userPhaseIndex);

            const approve_stablecoin_spending = await mockUsdc.connect(user).approve(investmentHandler.address, approvalValue);
            await approve_stablecoin_spending.wait();

            if (logging) {
                console.log("investmenthandler usdc balance before invest: ", await mockUsdc.balanceOf(investmentHandler.address));
                console.log("deposit and pledge amounts: ", depositAmount, pledgeAmount);
            }

            const userParams = {
                investmentId: investmentId,
                maxInvestableAmount: pledgeAmount,
                thisInvestmentAmount: depositAmount,
                userPhase: userPhaseIndex,
                kycAddress: user.address,
                signature: signature,
            };

            const invest_transaction = await investmentHandler.connect(user).invest(userParams);
            await invest_transaction.wait();

            if (logging) {
                console.log("pledgeAmount: ", pledgeAmount);
                console.log("investmenthandler usdc balance after invest: ", await mockUsdc.balanceOf(investmentHandler.address));
            }

            const set_project_token = await investmentHandler.connect(manager).setInvestmentProjectTokenAddress(investmentId, testProjectTokenAddress);
            await set_project_token.wait();

            const set_project_token_allocation = await investmentHandler.connect(manager).setInvestmentProjectTokenAllocation(investmentId, testInvestmentTokensAlloc);
            await set_project_token_allocation.wait();

            const deposit_project_tokens = await mockProjectToken.connect(manager).transfer(investmentHandler.address, testInvestmentTokensAlloc);
            await deposit_project_tokens.wait();

            const user_claim_tokens = await investmentHandler.connect(user).claim(investmentId, testClaimAmount, user.address, user.address);
            await user_claim_tokens.wait();

            if (logging) {
                console.log("latest investment id: ", await investmentHandler.latestInvestmentId());
                console.log("user investment ids: ", await investmentHandler.getUserInvestmentIds(user.address));
            }

            const investment = await investmentHandler.investments(investmentHandler.latestInvestmentId());
            expect(investment.paymentToken).to.equal(testInvestmentStablecoin);
            expect(investment.totalAllocatedPaymentToken).to.equal(testInvestmentUsdAlloc);
            expect(await investmentHandler.getTotalClaimedForInvestment(user.address, investmentId)).to.equal(testClaimAmount);
        });

        it("Should add investment, then use one network wallet for investing, another for calling the claim function, and another for receiving the claimed tokens", async function () {
            const {
                investmentHandler,
                signer,
                manager,
                pledgeAmount,
                depositAmount,
                user,
                depositNetworkAddress,
                claimCallerNetworkAddress,
                claimRecipientNetworkAddress,
                testProjectTokenAddress,
                testInvestmentTokensAlloc,
                testClaimAmount,
                testInvestmentStablecoin,
                testInvestmentUsdAlloc,
                mockUsdc,
                mockProjectToken,
                approvalValue,
                userPhaseIndex,
            } = await loadFixture(setupFixture);

            const add_investment = await investmentHandler.connect(manager).addInvestment(signer.address, testInvestmentStablecoin, testInvestmentUsdAlloc);
            await add_investment.wait();

            const investmentId = await investmentHandler.latestInvestmentId();

            const set_phase_to_shark = await investmentHandler.connect(manager).setInvestmentContributionPhase(investmentId, 2);
            await set_phase_to_shark.wait();

            const signature = await signDeposit(signer, user, pledgeAmount, userPhaseIndex);

            const approve_stablecoin_spending = await mockUsdc.connect(depositNetworkAddress).approve(investmentHandler.address, approvalValue);
            await approve_stablecoin_spending.wait();

            //add deposit and claim wallets to network
            const add_depositAddress = await investmentHandler.connect(user).addAddressToKycAddressNetwork(depositNetworkAddress.address);
            await add_depositAddress.wait();
            const add_claimAddress = await investmentHandler.connect(user).addAddressToKycAddressNetwork(claimCallerNetworkAddress.address);
            await add_claimAddress.wait();
            const add_claimRecipientAddress = await investmentHandler.connect(user).addAddressToKycAddressNetwork(claimRecipientNetworkAddress.address);
            await add_claimRecipientAddress.wait();

            if (logging) {
                console.log("investmenthandler usdc balance before invest: ", await mockUsdc.balanceOf(investmentHandler.address));
                console.log("deposit and pledge amounts: ", depositAmount, pledgeAmount);
            }

            const userParams = {
                investmentId: investmentId,
                maxInvestableAmount: pledgeAmount,
                thisInvestmentAmount: depositAmount,
                userPhase: userPhaseIndex,
                kycAddress: user.address,
                signature: signature,
            };

            const invest_transaction = await investmentHandler.connect(depositNetworkAddress).invest(userParams);
            await invest_transaction.wait();

            if (logging) {
                console.log("pledgeAmount: ", pledgeAmount);
                console.log("investmenthandler usdc balance after invest: ", await mockUsdc.balanceOf(investmentHandler.address));
            }

            const set_project_token = await investmentHandler.connect(manager).setInvestmentProjectTokenAddress(investmentId, testProjectTokenAddress);
            await set_project_token.wait();

            const set_project_token_allocation = await investmentHandler.connect(manager).setInvestmentProjectTokenAllocation(investmentId, testInvestmentTokensAlloc);
            await set_project_token_allocation.wait();

            const deposit_project_tokens = await mockProjectToken.connect(manager).transfer(investmentHandler.address, testInvestmentTokensAlloc);
            await deposit_project_tokens.wait();

            const user_claim_tokens = await investmentHandler.connect(claimCallerNetworkAddress).claim(investmentId, testClaimAmount, claimRecipientNetworkAddress.address, user.address);
            await user_claim_tokens.wait();

            if (logging) {
                console.log("latest investment id: ", await investmentHandler.latestInvestmentId());
                console.log("user investment ids: ", await investmentHandler.getUserInvestmentIds(user.address));
            }

            const investment = await investmentHandler.investments(investmentHandler.latestInvestmentId());
            expect(investment.paymentToken).to.equal(testInvestmentStablecoin);
            expect(investment.totalAllocatedPaymentToken).to.equal(testInvestmentUsdAlloc);
            expect(await investmentHandler.getTotalClaimedForInvestment(user.address, investmentId)).to.equal(testClaimAmount);
        });

        it("Should Should add investment, then revert on investment because sender is trying to invest in wrong phase", async function () {
            const { investmentHandler, signer, manager, pledgeAmount, depositAmount, user, depositNetworkAddress, testInvestmentStablecoin, testInvestmentUsdAlloc, mockUsdc, approvalValue, userPhaseIndex } = await loadFixture(setupFixture);

            const add_investment = await investmentHandler.connect(manager).addInvestment(signer.address, testInvestmentStablecoin, testInvestmentUsdAlloc);
            await add_investment.wait();

            const investmentId = await investmentHandler.latestInvestmentId();

            // set to whales, user is shark
            const set_phase_to_shark = await investmentHandler.connect(manager).setInvestmentContributionPhase(investmentId, 1);
            await set_phase_to_shark.wait();

            const signature = await signDeposit(signer, user, pledgeAmount, userPhaseIndex);

            const approve_stablecoin_spending = await mockUsdc.connect(depositNetworkAddress).approve(investmentHandler.address, approvalValue);
            await approve_stablecoin_spending.wait();

            if (logging) {
                console.log("investmenthandler usdc balance before invest: ", await mockUsdc.balanceOf(investmentHandler.address));
                console.log("deposit and pledge amounts: ", depositAmount, pledgeAmount);
            }

            const userParams = {
                investmentId: investmentId,
                maxInvestableAmount: pledgeAmount,
                thisInvestmentAmount: depositAmount,
                userPhase: userPhaseIndex,
                kycAddress: user.address,
                signature: signature,
            };

            let invest_transaction;
            try {
                invest_transaction = await investmentHandler.connect(depositNetworkAddress).invest(userParams);
                await invest_transaction.wait();
            } catch (err) {
                expect(err.message).to.include("InvestmentIsNotOpen()");
                return;
            }
        });

        it("Should Should add investment, then revert on claim because sender has not been added to network", async function () {
            const {
                investmentHandler,
                signer,
                manager,
                pledgeAmount,
                depositAmount,
                user,
                depositNetworkAddress,
                claimCallerNetworkAddress,
                claimRecipientNetworkAddress,
                testProjectTokenAddress,
                testInvestmentTokensAlloc,
                testClaimAmount,
                testInvestmentStablecoin,
                testInvestmentUsdAlloc,
                mockUsdc,
                mockProjectToken,
                approvalValue,
                userPhaseIndex,
            } = await loadFixture(setupFixture);

            const add_investment = await investmentHandler.connect(manager).addInvestment(signer.address, testInvestmentStablecoin, testInvestmentUsdAlloc);
            await add_investment.wait();

            const investmentId = await investmentHandler.latestInvestmentId();

            const set_phase_to_shark = await investmentHandler.connect(manager).setInvestmentContributionPhase(investmentId, 2);
            await set_phase_to_shark.wait();

            const signature = await signDeposit(signer, user, pledgeAmount, userPhaseIndex);

            const approve_stablecoin_spending = await mockUsdc.connect(depositNetworkAddress).approve(investmentHandler.address, approvalValue);
            await approve_stablecoin_spending.wait();

            //add deposit and claim wallets to network
            const add_depositAddress = await investmentHandler.connect(user).addAddressToKycAddressNetwork(depositNetworkAddress.address);
            await add_depositAddress.wait();
            // const add_claimAddress = await investmentHandler.connect(user).addAddressToKycAddressNetwork(claimCallerNetworkAddress.address);
            // await add_claimAddress.wait();
            const add_claimRecipientAddress = await investmentHandler.connect(user).addAddressToKycAddressNetwork(claimRecipientNetworkAddress.address);
            await add_claimRecipientAddress.wait();

            if (logging) {
                console.log("investmenthandler usdc balance before invest: ", await mockUsdc.balanceOf(investmentHandler.address));
                console.log("deposit and pledge amounts: ", depositAmount, pledgeAmount);
            }

            const userParams = {
                investmentId: investmentId,
                maxInvestableAmount: pledgeAmount,
                thisInvestmentAmount: depositAmount,
                userPhase: userPhaseIndex,
                kycAddress: user.address,
                signature: signature,
            };

            const invest_transaction = await investmentHandler.connect(depositNetworkAddress).invest(userParams);
            await invest_transaction.wait();

            if (logging) {
                console.log("pledgeAmount: ", pledgeAmount);
                console.log("investmenthandler usdc balance after invest: ", await mockUsdc.balanceOf(investmentHandler.address));
            }

            const set_project_token = await investmentHandler.connect(manager).setInvestmentProjectTokenAddress(investmentId, testProjectTokenAddress);
            await set_project_token.wait();

            const set_project_token_allocation = await investmentHandler.connect(manager).setInvestmentProjectTokenAllocation(investmentId, testInvestmentTokensAlloc);
            await set_project_token_allocation.wait();

            const deposit_project_tokens = await mockProjectToken.connect(manager).transfer(investmentHandler.address, testInvestmentTokensAlloc);
            await deposit_project_tokens.wait();

            let user_claim_tokens;
            let error_on_call = false;
            try {
                user_claim_tokens = await investmentHandler.connect(claimCallerNetworkAddress).claim(investmentId, testClaimAmount, claimRecipientNetworkAddress.address, user.address);
                await user_claim_tokens.wait();
            } catch (err) {
                expect(err.message).to.include("NotInKycAddressNetwork()");
                error_on_call = true;
            }
            expect(error_on_call).to.equal(true);
        });

        it("Should Should add investment, then revert on claim because recipient has not been added to network", async function () {
            const {
                investmentHandler,
                signer,
                manager,
                pledgeAmount,
                depositAmount,
                user,
                depositNetworkAddress,
                claimCallerNetworkAddress,
                claimRecipientNetworkAddress,
                testProjectTokenAddress,
                testInvestmentTokensAlloc,
                testClaimAmount,
                testInvestmentStablecoin,
                testInvestmentUsdAlloc,
                mockUsdc,
                mockProjectToken,
                approvalValue,
                userPhaseIndex,
            } = await loadFixture(setupFixture);

            const add_investment = await investmentHandler.connect(manager).addInvestment(signer.address, testInvestmentStablecoin, testInvestmentUsdAlloc);
            await add_investment.wait();

            const investmentId = await investmentHandler.latestInvestmentId();

            const set_phase_to_shark = await investmentHandler.connect(manager).setInvestmentContributionPhase(investmentId, 2);
            await set_phase_to_shark.wait();

            const signature = await signDeposit(signer, user, pledgeAmount, userPhaseIndex);

            const approve_stablecoin_spending = await mockUsdc.connect(depositNetworkAddress).approve(investmentHandler.address, approvalValue);
            await approve_stablecoin_spending.wait();

            //add deposit and claim wallets to network
            const add_depositAddress = await investmentHandler.connect(user).addAddressToKycAddressNetwork(depositNetworkAddress.address);
            await add_depositAddress.wait();
            const add_claimAddress = await investmentHandler.connect(user).addAddressToKycAddressNetwork(claimCallerNetworkAddress.address);
            await add_claimAddress.wait();
            // const add_claimRecipientAddress = await investmentHandler.connect(user).addAddressToKycAddressNetwork(claimRecipientNetworkAddress.address);
            // await add_claimRecipientAddress.wait();

            if (logging) {
                console.log("investmenthandler usdc balance before invest: ", await mockUsdc.balanceOf(investmentHandler.address));
                console.log("deposit and pledge amounts: ", depositAmount, pledgeAmount);
            }

            const userParams = {
                investmentId: investmentId,
                maxInvestableAmount: pledgeAmount,
                thisInvestmentAmount: depositAmount,
                userPhase: userPhaseIndex,
                kycAddress: user.address,
                signature: signature,
            };

            const invest_transaction = await investmentHandler.connect(depositNetworkAddress).invest(userParams);
            await invest_transaction.wait();

            if (logging) {
                console.log("pledgeAmount: ", pledgeAmount);
                console.log("investmenthandler usdc balance after invest: ", await mockUsdc.balanceOf(investmentHandler.address));
            }

            const set_project_token = await investmentHandler.connect(manager).setInvestmentProjectTokenAddress(investmentId, testProjectTokenAddress);
            await set_project_token.wait();

            const set_project_token_allocation = await investmentHandler.connect(manager).setInvestmentProjectTokenAllocation(investmentId, testInvestmentTokensAlloc);
            await set_project_token_allocation.wait();

            const deposit_project_tokens = await mockProjectToken.connect(manager).transfer(investmentHandler.address, testInvestmentTokensAlloc);
            await deposit_project_tokens.wait();

            let user_claim_tokens;
            let error_on_call = false;
            try {
                user_claim_tokens = await investmentHandler.connect(claimCallerNetworkAddress).claim(investmentId, testClaimAmount, claimRecipientNetworkAddress.address, user.address);
                await user_claim_tokens.wait();
            } catch (err) {
                expect(err.message).to.include("NotInKycAddressNetwork()");
                error_on_call = true;
            }
            expect(error_on_call).to.equal(true);
        });
    });

    describe("Computing Allocation", function () {
        it("Should compute correct allocation for user claiming after all tokens have been deposited", async function () {
            //same as "Should add investment, then invest, token deposit, and claim all from kyc wallet as sender" test, but focuses on checking claim allocation calculations with a 2nd user
            const {
                investmentHandler,
                signer,
                manager,
                pledgeAmount,
                depositAmount,
                user,
                user2,
                testProjectTokenAddress,
                testInvestmentTokensAlloc,
                testInvestmentStablecoin,
                testInvestmentUsdAlloc,
                mockUsdc,
                mockProjectToken,
                approvalValue,
                userPhaseIndex,
            } = await loadFixture(setupFixture);

            const add_investment = await investmentHandler.connect(manager).addInvestment(signer.address, testInvestmentStablecoin, testInvestmentUsdAlloc);
            await add_investment.wait();

            const investmentId = await investmentHandler.latestInvestmentId();

            const set_phase_to_shark = await investmentHandler.connect(manager).setInvestmentContributionPhase(investmentId, 2);
            await set_phase_to_shark.wait();

            const signature1 = await signDeposit(signer, user, pledgeAmount, userPhaseIndex);
            const signature2 = await signDeposit(signer, user2, pledgeAmount, userPhaseIndex);

            const approve_stablecoin_spending = await mockUsdc.connect(user).approve(investmentHandler.address, approvalValue);
            await approve_stablecoin_spending.wait();

            const approve_stablecoin_spending2 = await mockUsdc.connect(user2).approve(investmentHandler.address, approvalValue);
            await approve_stablecoin_spending2.wait();

            if (logging) {
                console.log("investmenthandler usdc balance before invest: ", await mockUsdc.balanceOf(investmentHandler.address));
                console.log("deposit and pledge amounts: ", depositAmount, pledgeAmount);
            }

            const userParams1 = {
                investmentId: investmentId,
                maxInvestableAmount: pledgeAmount,
                thisInvestmentAmount: depositAmount,
                userPhase: userPhaseIndex,
                kycAddress: user.address,
                signature: signature1,
            };

            const invest_transaction1 = await investmentHandler.connect(user).invest(userParams1);
            await invest_transaction1.wait();

            const userParams2 = {
                investmentId: investmentId,
                maxInvestableAmount: pledgeAmount,
                thisInvestmentAmount: depositAmount,
                userPhase: userPhaseIndex,
                kycAddress: user2.address,
                signature: signature2,
            };

            const invest_transaction2 = await investmentHandler.connect(user2).invest(userParams2);
            await invest_transaction2.wait();

            if (logging) {
                console.log("pledgeAmount: ", pledgeAmount);
                console.log("investmenthandler usdc balance after invest: ", await mockUsdc.balanceOf(investmentHandler.address));
            }

            const set_project_token = await investmentHandler.connect(manager).setInvestmentProjectTokenAddress(investmentId, testProjectTokenAddress);
            await set_project_token.wait();

            const set_project_token_allocation = await investmentHandler.connect(manager).setInvestmentProjectTokenAllocation(investmentId, testInvestmentTokensAlloc);
            await set_project_token_allocation.wait();

            const deposit_project_tokens = await mockProjectToken.connect(manager).transfer(investmentHandler.address, testInvestmentTokensAlloc);
            await deposit_project_tokens.wait();

            //check claimable amount (should be 50% each)
            const user1_claimable_amount = await investmentHandler.connect(user).computeUserClaimableAllocationForInvestment(user.address, investmentId);
            const user2_claimable_amount = await investmentHandler.connect(user2).computeUserClaimableAllocationForInvestment(user2.address, investmentId);
            expect(user1_claimable_amount).to.equal(testInvestmentTokensAlloc.div(2));
            expect(user2_claimable_amount).to.equal(testInvestmentTokensAlloc.div(2));
        });

        it("Should compute correct allocation for user claiming before and after all tokens have been deposited", async function () {
            const {
                investmentHandler,
                signer,
                manager,
                pledgeAmount,
                depositAmount,
                user,
                user2,
                testProjectTokenAddress,
                testInvestmentTokensAlloc,
                testInvestmentStablecoin,
                testInvestmentUsdAlloc,
                mockUsdc,
                mockProjectToken,
                approvalValue,
                userPhaseIndex,
            } = await loadFixture(setupFixture);

            const add_investment = await investmentHandler.connect(manager).addInvestment(signer.address, testInvestmentStablecoin, testInvestmentUsdAlloc);
            await add_investment.wait();

            const investmentId = await investmentHandler.latestInvestmentId();

            const set_phase_to_shark = await investmentHandler.connect(manager).setInvestmentContributionPhase(investmentId, 2);
            await set_phase_to_shark.wait();

            const signature1 = await signDeposit(signer, user, pledgeAmount, userPhaseIndex);
            const signature2 = await signDeposit(signer, user2, pledgeAmount, userPhaseIndex);

            const approve_stablecoin_spending = await mockUsdc.connect(user).approve(investmentHandler.address, approvalValue);
            await approve_stablecoin_spending.wait();

            const approve_stablecoin_spending2 = await mockUsdc.connect(user2).approve(investmentHandler.address, approvalValue);
            await approve_stablecoin_spending2.wait();

            if (logging) {
                console.log("investmenthandler usdc balance before invest: ", await mockUsdc.balanceOf(investmentHandler.address));
                console.log("deposit and pledge amounts: ", depositAmount, pledgeAmount);
            }

            const userParams1 = {
                investmentId: investmentId,
                maxInvestableAmount: pledgeAmount,
                thisInvestmentAmount: depositAmount,
                userPhase: userPhaseIndex,
                kycAddress: user.address,
                signature: signature1,
            };

            const invest_transaction1 = await investmentHandler.connect(user).invest(userParams1);
            await invest_transaction1.wait();

            const userParams2 = {
                investmentId: investmentId,
                maxInvestableAmount: pledgeAmount,
                thisInvestmentAmount: depositAmount,
                userPhase: userPhaseIndex,
                kycAddress: user2.address,
                signature: signature2,
            };

            const invest_transaction2 = await investmentHandler.connect(user2).invest(userParams2);
            await invest_transaction2.wait();

            if (logging) {
                console.log("pledgeAmount: ", pledgeAmount);
                console.log("investmenthandler usdc balance after invest: ", await mockUsdc.balanceOf(investmentHandler.address));
            }

            const set_project_token = await investmentHandler.connect(manager).setInvestmentProjectTokenAddress(investmentId, testProjectTokenAddress);
            await set_project_token.wait();

            const set_project_token_allocation = await investmentHandler.connect(manager).setInvestmentProjectTokenAllocation(investmentId, testInvestmentTokensAlloc);
            await set_project_token_allocation.wait();

            const deposit_project_tokens = await mockProjectToken.connect(manager).transfer(investmentHandler.address, testInvestmentTokensAlloc.div(2));
            await deposit_project_tokens.wait();

            //check claimable amount (should be 50% each)
            const user1_claimable_amount = await investmentHandler.connect(user).computeUserClaimableAllocationForInvestment(user.address, investmentId);
            const user2_claimable_amount = await investmentHandler.connect(user2).computeUserClaimableAllocationForInvestment(user2.address, investmentId);
            expect(user1_claimable_amount).to.equal(testInvestmentTokensAlloc.div(4));
            expect(user2_claimable_amount).to.equal(testInvestmentTokensAlloc.div(4));

            const deposit_project_tokens2 = await mockProjectToken.connect(manager).transfer(investmentHandler.address, testInvestmentTokensAlloc.div(2));
            await deposit_project_tokens2.wait();

            //check claimable amount (should be 50% each)
            const user1_claimable_amount2 = await investmentHandler.connect(user).computeUserClaimableAllocationForInvestment(user.address, investmentId);
            const user2_claimable_amount2 = await investmentHandler.connect(user2).computeUserClaimableAllocationForInvestment(user2.address, investmentId);
            expect(user1_claimable_amount2).to.equal(testInvestmentTokensAlloc.div(2));
            expect(user2_claimable_amount2).to.equal(testInvestmentTokensAlloc.div(2));
        });

        it("Should compute correct allocation for user claiming before and after all tokens have been deposited, with others claiming between claims", async function () {
            const {
                investmentHandler,
                signer,
                manager,
                pledgeAmount,
                depositAmount,
                user,
                user2,
                testProjectTokenAddress,
                testInvestmentTokensAlloc,
                testInvestmentStablecoin,
                testInvestmentUsdAlloc,
                mockUsdc,
                mockProjectToken,
                approvalValue,
                userPhaseIndex,
            } = await loadFixture(setupFixture);

            const add_investment = await investmentHandler.connect(manager).addInvestment(signer.address, testInvestmentStablecoin, testInvestmentUsdAlloc);
            await add_investment.wait();

            const investmentId = await investmentHandler.latestInvestmentId();

            const set_phase_to_shark = await investmentHandler.connect(manager).setInvestmentContributionPhase(investmentId, 2);
            await set_phase_to_shark.wait();

            const signature1 = await signDeposit(signer, user, pledgeAmount, userPhaseIndex);
            const signature2 = await signDeposit(signer, user2, pledgeAmount, userPhaseIndex);

            const approve_stablecoin_spending = await mockUsdc.connect(user).approve(investmentHandler.address, approvalValue);
            await approve_stablecoin_spending.wait();

            const approve_stablecoin_spending2 = await mockUsdc.connect(user2).approve(investmentHandler.address, approvalValue);
            await approve_stablecoin_spending2.wait();

            if (logging) {
                console.log("investmenthandler usdc balance before invest: ", await mockUsdc.balanceOf(investmentHandler.address));
                console.log("deposit and pledge amounts: ", depositAmount, pledgeAmount);
            }

            const userParams1 = {
                investmentId: investmentId,
                maxInvestableAmount: pledgeAmount,
                thisInvestmentAmount: depositAmount,
                userPhase: userPhaseIndex,
                kycAddress: user.address,
                signature: signature1,
            };

            const invest_transaction1 = await investmentHandler.connect(user).invest(userParams1);
            await invest_transaction1.wait();

            const userParams2 = {
                investmentId: investmentId,
                maxInvestableAmount: pledgeAmount,
                thisInvestmentAmount: depositAmount,
                userPhase: userPhaseIndex,
                kycAddress: user2.address,
                signature: signature2,
            };

            const invest_transaction2 = await investmentHandler.connect(user2).invest(userParams2);
            await invest_transaction2.wait();

            if (logging) {
                console.log("pledgeAmount: ", pledgeAmount);
                console.log("investmenthandler usdc balance after invest: ", await mockUsdc.balanceOf(investmentHandler.address));
            }

            const set_project_token = await investmentHandler.connect(manager).setInvestmentProjectTokenAddress(investmentId, testProjectTokenAddress);
            await set_project_token.wait();

            const set_project_token_allocation = await investmentHandler.connect(manager).setInvestmentProjectTokenAllocation(investmentId, testInvestmentTokensAlloc);
            await set_project_token_allocation.wait();

            const deposit_project_tokens = await mockProjectToken.connect(manager).transfer(investmentHandler.address, testInvestmentTokensAlloc.div(2));
            await deposit_project_tokens.wait();

            //check claimable amount (should be 50% each)
            const user1_claimable_amount = await investmentHandler.connect(user).computeUserClaimableAllocationForInvestment(user.address, investmentId);
            const user2_claimable_amount = await investmentHandler.connect(user2).computeUserClaimableAllocationForInvestment(user2.address, investmentId);
            expect(user1_claimable_amount).to.equal(testInvestmentTokensAlloc.div(4));
            expect(user2_claimable_amount).to.equal(testInvestmentTokensAlloc.div(4));

            //claim between deposits
            const user_claim_tokens = await investmentHandler.connect(user).claim(investmentId, user1_claimable_amount, user.address, user.address);
            await user_claim_tokens.wait();

            const deposit_project_tokens2 = await mockProjectToken.connect(manager).transfer(investmentHandler.address, testInvestmentTokensAlloc.div(2));
            await deposit_project_tokens2.wait();

            const user1_claimable_amount2 = await investmentHandler.connect(user).computeUserClaimableAllocationForInvestment(user.address, investmentId);
            const user2_claimable_amount2 = await investmentHandler.connect(user2).computeUserClaimableAllocationForInvestment(user2.address, investmentId);
            const user_claim_tokens2 = await investmentHandler.connect(user).claim(investmentId, user1_claimable_amount2, user.address, user.address);
            await user_claim_tokens2.wait();

            const user1_claimable_amount3 = await investmentHandler.connect(user).computeUserClaimableAllocationForInvestment(user.address, investmentId);
            const user2_claimable_amount3 = await investmentHandler.connect(user2).computeUserClaimableAllocationForInvestment(user2.address, investmentId);

            const investment_struct = await investmentHandler.investments(investmentId);
            const total_stable_alloc = investment_struct.totalAllocatedPaymentToken;
            const total_stable_invested = investment_struct.totalInvestedPaymentToken;

            if (logging) {
                console.log("total_stable_alloc: ", total_stable_alloc.toString());
                console.log("total_stable_invested: ", total_stable_invested.toString());
                console.log("user1_claimable_amount ", user1_claimable_amount);
                console.log("user1_claimable_amount2 (excluding amount claimed in claim 1) ", user1_claimable_amount2);
                console.log("user2_claimable_amount ", user2_claimable_amount);
                console.log("user2_claimable_amount2 ", user2_claimable_amount2);
                console.log("user1_claimable_amount3 ", user1_claimable_amount3);
                console.log("user2_claimable_amount3 ", user2_claimable_amount3);
            }

            const user_claim_tokens3 = await investmentHandler.connect(user2).claim(investmentId, user2_claimable_amount2, user2.address, user2.address);
            await user_claim_tokens3.wait();

            //check claimable amount (should be 50% each)
            const user1_claimable_amount4 = await investmentHandler.connect(user).computeUserClaimableAllocationForInvestment(user.address, investmentId);
            const user2_claimable_amount4 = await investmentHandler.connect(user2).computeUserClaimableAllocationForInvestment(user2.address, investmentId);
            expect(user1_claimable_amount4).to.equal(0);
            expect(user2_claimable_amount4).to.equal(0);
        });

        it("Should show repeatability of allocation calculation, no significant/cumulative rounding errors", async function () {
            //add 100, user with 100% can claim another 100, repeatably
            const {
                investmentHandler,
                signer,
                manager,
                pledgeAmount,
                depositAmount,
                user,
                testProjectTokenAddress,
                testInvestmentTokensAlloc,
                testInvestmentStablecoin,
                testInvestmentUsdAlloc,
                mockUsdc,
                mockProjectToken,
                approvalValue,
                userPhaseIndex,
            } = await loadFixture(setupFixture);

            const add_investment = await investmentHandler.connect(manager).addInvestment(signer.address, testInvestmentStablecoin, testInvestmentUsdAlloc);
            await add_investment.wait();

            const investmentId = await investmentHandler.latestInvestmentId();

            const set_phase_to_shark = await investmentHandler.connect(manager).setInvestmentContributionPhase(investmentId, 2);
            await set_phase_to_shark.wait();

            const signature1 = await signDeposit(signer, user, pledgeAmount, userPhaseIndex);

            const approve_stablecoin_spending = await mockUsdc.connect(user).approve(investmentHandler.address, approvalValue);
            await approve_stablecoin_spending.wait();

            if (logging) {
                console.log("investmenthandler usdc balance before invest: ", await mockUsdc.balanceOf(investmentHandler.address));
                console.log("deposit and pledge amounts: ", depositAmount, pledgeAmount);
            }

            const userParams1 = {
                investmentId: investmentId,
                maxInvestableAmount: pledgeAmount,
                thisInvestmentAmount: depositAmount,
                userPhase: userPhaseIndex,
                kycAddress: user.address,
                signature: signature1,
            };

            const invest_transaction1 = await investmentHandler.connect(user).invest(userParams1);
            await invest_transaction1.wait();

            if (logging) {
                console.log("pledgeAmount: ", pledgeAmount);
                console.log("investmenthandler usdc balance after invest: ", await mockUsdc.balanceOf(investmentHandler.address));
            }

            const set_project_token = await investmentHandler.connect(manager).setInvestmentProjectTokenAddress(investmentId, testProjectTokenAddress);
            await set_project_token.wait();

            const set_project_token_allocation = await investmentHandler.connect(manager).setInvestmentProjectTokenAllocation(investmentId, testInvestmentTokensAlloc);
            await set_project_token_allocation.wait();

            const deposit_project_tokens = await mockProjectToken.connect(manager).transfer(investmentHandler.address, testInvestmentTokensAlloc.div(3));
            await deposit_project_tokens.wait();

            let totalDeposits = 1000;
            for (let i = 1; i <= totalDeposits; i++) {
                const deposit_project_tokens = await mockProjectToken.connect(manager).transfer(investmentHandler.address, testInvestmentTokensAlloc.div(totalDeposits));
                await deposit_project_tokens.wait();

                const user1_claimable_amount = await investmentHandler.connect(user).computeUserClaimableAllocationForInvestment(user.address, investmentId);
                expect(user1_claimable_amount).to.be.greaterThan(testInvestmentTokensAlloc.mul(i).div(totalDeposits).mul(99999).div(100000));
            }

            totalDeposits = 5;
            for (let i = 1; i <= totalDeposits; i++) {
                const deposit_project_tokens = await mockProjectToken.connect(manager).transfer(investmentHandler.address, testInvestmentTokensAlloc.div(totalDeposits));
                await deposit_project_tokens.wait();

                const user1_claimable_amount = await investmentHandler.connect(user).computeUserClaimableAllocationForInvestment(user.address, investmentId);
                expect(user1_claimable_amount).to.be.greaterThan(testInvestmentTokensAlloc.mul(i).div(totalDeposits).mul(99999).div(100000));
            }
        });
    });

    describe("SignatureCheck", function () {
        it("Should return true when the signature is valid", async function () {
            const { investmentHandler, pledgeAmount, user, signer, userPhaseIndex } = await loadFixture(setupFixture);
            const signature = await signDeposit(signer, user, pledgeAmount, userPhaseIndex);
            const isValid = await investmentHandler.checkSignature(signer.address, user.address, pledgeAmount, userPhaseIndex, signature);
            expect(isValid).to.equal(true);
        });
        it("should return false when the signature is invalid", async function () {
            const { investmentHandler, pledgeAmount, user, signer, userPhaseIndex } = await loadFixture(setupFixture);
            const signature = await signDeposit(signer, user, pledgeAmount, userPhaseIndex);
            const isValid = await investmentHandler.checkSignature(
                signer.address,
                signer.address, //here is the change - wrong address, should be user.address
                pledgeAmount,
                userPhaseIndex,
                signature
            );
            expect(isValid).to.equal(false);
        });
    });
});

//============================================================
// HELPERS
//============================================================

async function signDeposit(signerAddress, user, pledgeAmount, phaseIndex) {
    const hash = ethers.utils.solidityKeccak256(["address", "uint", "uint"], [user.address, pledgeAmount, phaseIndex]);
    const signature = await signerAddress.signMessage(ethers.utils.arrayify(hash));
    if (logging) console.log("Signature from js: ", signature);
    return signature;
}
