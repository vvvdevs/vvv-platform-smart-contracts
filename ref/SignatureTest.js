/**
 *
 * Tests Process of:
 * 1. Create new investment
 * 2. Sign address and amount for user
 * 3. Invest USDC with signature check
 * 4. Manager deposits project token
 * 5. User Claims Project token
 *
 */

const { ethers, upgrades } = require("hardhat");
const { time, loadFixture } = require("@nomicfoundation/hardhat-network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");
require("dotenv").config();

const logging = true;

describe("InvestmentHandler", function () {
    async function setupFixture() {
        const provider = new ethers.providers.JsonRpcProvider();


        const signerPre = ethers.Wallet.createRandom();
        const spk = signerPre.privateKey;
        const signer = new ethers.Wallet(spk, provider);

        const [manager, user] = await ethers.getSigners();

        let MockERC20 = await ethers.getContractFactory("MockERC20");
        MockERC20 = await MockERC20.connect(manager);
        const mockProjectToken = await MockERC20.deploy([18]);
        await mockProjectToken.deployed();
        const mockUsdc = await MockERC20.deploy([18]);
        await mockUsdc.deployed();

        let mint_usdc_to_user = await mockUsdc.connect(user).mint(user.address, ethers.utils.parseEther("10000"));
        await mint_usdc_to_user.wait();

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
        const testInvestmentUsdAlloc = ethers.utils.parseEther("1000");
        const testInvestmentTokensAlloc = ethers.utils.parseEther("1000");
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

async function signDeposit(signerWallet, user, pledgeAmount, phaseIndex) {
    const hash = ethers.utils.solidityKeccak256(["address", "uint256", "uint8"], [user.address, pledgeAmount, phaseIndex]);
    const signature = await signerWallet.signMessage(ethers.utils.arrayify(hash));
    console.log("Signature from js: ", signature);
    return signature;
}
