const { ethers } = require("hardhat");
const { expect } = require("chai");
require("dotenv").config();

// Create a ethers provider and wallet
const provider = new ethers.providers.JsonRpcProvider();
const wallet = new ethers.Wallet(process.env.PRIVATE_KEY, provider);

describe("InvestmentHandlerSignatureCheck", function () {
  it("Should return true when the signature is valid", async function () {
    const YourContract = await ethers.getContractFactory("InvestmentHandler");
    const yourContract = await YourContract.deploy();
    await yourContract.deployed();

    const userAddress = "0x3bA45EFf20bF493b5d226EFadd2D7734d48Ad8a5"; //
    const signerAddress = await wallet.getAddress();
    const depositAmount = ethers.utils.parseEther("1234");

    // Call the signDeposit function
    const signature = await signDeposit(userAddress, depositAmount, yourContract.address);

    // Call the checkSignature function
    const isValid = await checkSignature(yourContract.address, signature, signerAddress, userAddress, depositAmount);

    expect(isValid).to.equal(true);
  });
});

//============================================================
// FUNCTIONS
//============================================================

async function signDeposit(userAddress, depositAmount, contractAddress) {
  // Prepare the hash to sign
  const hash = ethers.utils.solidityKeccak256(["address", "uint256"], [userAddress, depositAmount]);

  // Sign the hash
  const signature = await wallet.signMessage(ethers.utils.arrayify(hash));
  console.log("Signature from js: ", signature);

  return signature;
}

async function checkSignature(contractAddress, signature, signerAddress, userAddress, depositAmount) {
  // Create an instance of the contract
  const contractArtifact = await ethers.getContractFactory("InvestmentHandler");
  const contract = await contractArtifact.attach(contractAddress);

  // Call the isValidSignatureNow function
  const isValid = await contract.checkSignature(signerAddress, userAddress, depositAmount, signature);

  return isValid;
}
