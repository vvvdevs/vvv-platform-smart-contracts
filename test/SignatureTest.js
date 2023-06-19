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

    const userAddress = await wallet.getAddress();
    const depositAmount = ethers.utils.parseEther("1234");

    // Call the signDeposit function
    const signature = await signDeposit(userAddress, depositAmount, yourContract.address);

    // Call the checkSignature function
    const isValid = await checkSignature(yourContract.address, signature, userAddress, depositAmount);

    expect(isValid).to.equal(true);
  });
});

//============================================================
// FUNCTIONS
//============================================================

async function signDeposit(userAddress, depositAmount, contractAddress) {
  // Format the depositAmount as an ethers.js BigNumber
  depositAmount = ethers.utils.parseEther(depositAmount.toString());

  // Prepare the data to sign
  const data = ethers.utils.solidityPack(["address", "uint256"], [userAddress, depositAmount]);

  // Hash the data
  const hash = ethers.utils.keccak256(data);
  const messageHash = ethers.utils.hashMessage(ethers.utils.arrayify(hash));

  // Sign the hash
  const signature = await wallet.signMessage(ethers.utils.arrayify(messageHash));
  console.log("Signature from js: ", signature);

  const contractArtifact = await ethers.getContractFactory("InvestmentHandler");
  const contract = await contractArtifact.attach(contractAddress);

  const solSignedMessageHash = await contract.getEthSignedMessageHash(userAddress, depositAmount);
  console.log("Signature from solidity: ", solSignedMessageHash.toString());

  return signature;
}

async function checkSignature(contractAddress, signature, userAddress, depositAmount) {
  // Create an instance of the contract
  const contractArtifact = await ethers.getContractFactory("InvestmentHandler");
  const contract = await contractArtifact.attach(contractAddress);

  // Call the isValidSignatureNow function
  const isValid = await contract.checkSignature(userAddress, depositAmount, signature);

  return isValid;
}
