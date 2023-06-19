const { ethers } = require("hardhat");
const { expect } = require("chai");
require("dotenv").config();

describe("YourContract", function () {
  it("Should return true when the signature is valid", async function () {
    const YourContract = await ethers.getContractFactory("YourContract");
    const yourContract = await YourContract.deploy();
    await yourContract.deployed();

    const signer = ethers.provider.getSigner();
    const userAddress = await signer.getAddress();
    const depositAmount = ethers.utils.parseEther("1234");

    // Call the signDeposit function
    const signature = await signDeposit(userAddress, depositAmount, signer.privateKey);

    // Call the checkSignature function
    const isValid = await checkSignature(yourContract.address, signature, userAddress, depositAmount, signer);

    expect(isValid).to.equal(true);
  });
});

//============================================================
// FUNCTIONS
//============================================================

async function signDeposit(userAddress, depositAmount, privateKey) {
  // Create a ethers provider
  const provider = new ethers.providers.JsonRpcProvider();

  // Create a wallet from the private key
  const wallet = new ethers.Wallet(privateKey, provider);

  // Format the depositAmount as an ethers.js BigNumber
  depositAmount = ethers.utils.parseUnits(depositAmount.toString(), "ether");

  // Prepare the data to sign
  const data = ethers.utils.solidityPack(["address", "uint256"], [userAddress, depositAmount]);

  // Hash the data
  const hash = ethers.utils.keccak256(data);

  // Sign the hash
  const signature = await wallet.signMessage(ethers.utils.arrayify(hash));

  return signature;
}

async function checkSignature(contractAddress, signature, userAddress, depositAmount, signer) {
  // Format the depositAmount as an ethers.js BigNumber
  depositAmount = ethers.utils.parseUnits(depositAmount.toString(), "ether");

  // Prepare the data that was signed
  const data = ethers.utils.solidityPack(["address", "uint256"], [userAddress, depositAmount]);

  // Hash the data
  const hash = ethers.utils.keccak256(data);

  // Hash the signed message according to EIP-191
  const messageHash = ethers.utils.hashMessage(ethers.utils.arrayify(hash));
  const prefixedMessageHash = ethers.utils.solidityKeccak256(
    ["string", "bytes32"],
    ["\x19Ethereum Signed Message:\n32", messageHash]
  );

  // Create an instance of the contract
  const contract = new ethers.Contract(contractAddress, contractABI, signer);

  // Call the isValidSignatureNow function
  const isValid = await contract.isValidSignatureNow(prefixedMessageHash, signature);

  return isValid;
}
