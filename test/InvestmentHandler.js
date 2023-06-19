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

describe("InvestmentHandler", function () {
  async function setupFixture() {
    const provider = new ethers.providers.JsonRpcProvider();

    // const manager = new ethers.Wallet(process.env.PRIVATE_KEY, provider);
    // const manager.address = await manager.getAddress();

    // const user = new ethers.Wallet(process.env.PRIVATE_KEY_2, provider);
    // const user.address = await user.getAddress();

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

    console.log("MockProjectToken deployed to:", mockProjectToken.address);
    console.log("MockUsdc deployed to:", mockUsdc.address);

    let mint_usdc_to_user = await mockUsdc.connect(user).mint(user.address, ethers.utils.parseEther("10000"));
    await mint_usdc_to_user.wait();

    let InvestmentHandler = await ethers.getContractFactory("InvestmentHandler");
    InvestmentHandler = await InvestmentHandler.connect(manager);
    const investmentHandler = await upgrades.deployProxy(InvestmentHandler, [mockUsdc.address, mockUsdc.address], {
      initializer: "initialize",
    });

    await investmentHandler.deployed();

    const testInvestmentStablecoin = mockUsdc.address; //USDC
    const testProjectTokenAddress = mockProjectToken.address; //USDC

    const pledgeAmount = ethers.utils.parseEther("1000");
    const depositAmount = ethers.utils.parseEther("0.00012746");
    const testInvestmentUsdAlloc = ethers.utils.parseEther("1000");
    const testInvestmentTokensAlloc = ethers.utils.parseEther("1000");
    const testClaimAmount = ethers.utils.parseEther("1000");
    const testPledgedAmount = ethers.utils.parseEther("1000");
    const approvalValue = ethers.utils.parseEther("10000");

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
    };
  }

  describe("Deployment", function () {
    it("Should set the right owner", async function () {
      const { investmentHandler, manager } = await loadFixture(setupFixture);
      expect(await investmentHandler.deployer()).to.equal(manager.address);
    });
  });

  //test for creation of new investment, then signing of address and amount for user, then investing USDC with signature check, then manager deposits project token, then user claims project token
  describe("Investment Process", function () {
    it("Should carry out add, invest, token deposit, claim", async function () {
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
        testPledgedAmount,
        testInvestmentStablecoin,
        testInvestmentUsdAlloc,
        mockUsdc,
        mockProjectToken,
        approvalValue,
      } = await loadFixture(setupFixture);

      const add_investment = await investmentHandler
        .connect(manager)
        .addInvestment(signer.address, testInvestmentStablecoin, testInvestmentUsdAlloc);
      await add_investment.wait();

      const investmentId = await investmentHandler.investmentId();

      const signature = await signDeposit(signer, user, pledgeAmount);

      const approve_stablecoin_spending = await mockUsdc
        .connect(user)
        .approve(investmentHandler.address, approvalValue);
      await approve_stablecoin_spending.wait();

      console.log(
        "investmenthandler usdc balance before invest: ",
        await mockUsdc.balanceOf(investmentHandler.address)
      );

      const invest_transaction = await investmentHandler
        .connect(user)
        .invest(investmentId, testPledgedAmount, ethers.utils.parseEther("0.0123"), signature);
      await invest_transaction.wait();

      /**
       * how is this??
       * 1000000000000000000000
       * 4000000000000000000000
       */

      console.log("pledgeAmount: ", pledgeAmount);
      console.log("investmenthandler usdc balance after invest: ", await mockUsdc.balanceOf(investmentHandler.address));
      console.log("contractTotalInvestedUsd after invest: ", await investmentHandler.contractTotalInvestedUsd());

      const set_project_token = await investmentHandler
        .connect(manager)
        .setInvestmentProjectTokenAddress(investmentId, testProjectTokenAddress);
      await set_project_token.wait();

      const set_project_token_allocation = await investmentHandler
        .connect(manager)
        .setInvestmentProjectTokenAllocation(investmentId, testInvestmentTokensAlloc);
      await set_project_token_allocation.wait();

      const deposit_project_tokens = await mockProjectToken
        .connect(manager)
        .transfer(investmentHandler.address, testInvestmentTokensAlloc);
      await deposit_project_tokens.wait();

      // const claimable_tokens = await investmentHandler.connect(user).computeUserClaimableAllocationForInvestment(investmentId);

      const user_claim_tokens = await investmentHandler.connect(user).claim(investmentId, testClaimAmount);
      await user_claim_tokens.wait();

      // expect(await mockUsdc.balanceOf(investmentHandler.address)).to.equal(pledgeAmount);

      const investment = await investmentHandler.investments(investmentHandler.investmentId());
      expect(investment.stablecoin).to.equal(testInvestmentStablecoin);
      expect(investment.totalAllocatedUsd).to.equal(testInvestmentUsdAlloc);
    });
  });

  describe("SignatureCheck", function () {
    it("Should return true when the signature is valid", async function () {
      const { investmentHandler, pledgeAmount, user, signer } = await loadFixture(setupFixture);
      const signature = await signDeposit(signer, user, pledgeAmount);
      const isValid = await investmentHandler.checkSignature(signer.address, user.address, pledgeAmount, signature);
      expect(isValid).to.equal(true);
    });
  });
});

//============================================================
// HELPERS
//============================================================

async function signDeposit(signerWallet, user, pledgeAmount) {
  const hash = ethers.utils.solidityKeccak256(["address", "uint256"], [user.address, pledgeAmount]);
  const signature = await signerWallet.signMessage(ethers.utils.arrayify(hash));
  console.log("Signature from js: ", signature);
  return signature;
}
