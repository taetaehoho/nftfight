const { assert, expect } = require("chai");
const { network, deployments, ethers } = require("hardhat");

// Helper function to advance time by the specified duration
const advanceTime = (duration) => {
  const id = Date.now();

  return new Promise((resolve) => {
    web3.currentProvider.sendAsync(
      {
        jsonrpc: "2.0",
        method: "evm_increaseTime",
        params: [duration],
        id: id,
      },
      (err) => {
        if (err) {
          return reject(err);
        }

        return resolve();
      }
    );
  });
};

describe("NFTfight Unit Tests", () => {
  let nftfight, ;

  beforeEach(async () => {
    // Get the owner's wallet and the contract instance
    [owner] = await getWallets();
    contract = await deployContract(owner, MyContract, []);
  });

  it("should start with 100 NFTs available", async () => {
    const totalNFTs = await contract.totalNFTs();
    expect(totalNFTs).to.equal(100);
  });

  it("should allow a user to purchase an NFT", async () => {
    const value = ethers.utils.parseEther("0.05");
    await contract.purchaseNft({ value });

    const totalEth = await contract.totalEth();
    expect(totalEth).to.equal(value);

    const uNFTid = await contract.NFTid();
    const purchasedNFT = await contract.purchasedNFTs(uNFTid);
    expect(purchasedNFT).to.equal(owner.address);

    const survivingNFTs = await contract.survivingNFTs(0);
    expect(survivingNFTs).to.equal(uNFTid);
  });

  it("should not allow a user to purchase an NFT without the minimum ETH", async () => {
    await expect(contract.purchaseNft()).to.be.revertedWith(
      "purchaseNFT__MintPriceNotMet"
    );
  });

  it("should allow a user to vote on which NFT to burn", async () => {
    const value = ethers.utils.parseEther("0.05");
    await contract.purchaseNft({ value });
    const uNFTid = await contract.NFTid();

    // Advance time by the vote duration
    await advanceTime(86400);

    await contract.vote(0, uNFTid);

    const currentEpoch = await contract.epoch();
    const voteBool = await contract.voteBool(currentEpoch, owner.address);
    expect(voteBool).to.be.true;

    const voteTally = await contract.voteTally(currentEpoch, uNFTid);
    expect(voteTally).to.equal(1);
  });

  it("should not allow a user to vote without an NFT or if they have already voted", async () => {
    // Try to vote without an NFT
    await expect(contract.vote(0, 0)).to.be.revertedWith(
      "vote__IneligibleToVote"
    );

    const value = ethers.utils.parseEther("0.05");
    await contract.purchaseNft({ value });
    const uNFTid = await contract.NFTid();

    // Advance time by the vote duration
    await advanceTime(86400);

    await contract.vote(0, uNFTid);

    // Try to vote again
    await expect(contract.vote(0, uNFTid)).to.be.revertedWith(
      "vote__IneligibleToVote"
    );
  });

  it("should not allow a user to vote on an NFT that has already been voted out", async () => {
    // Purchase two NFTs and vote one out
    const value = ethers.utils.parseEther("0.05");
    await contract.purchaseNft({ value });
    const uNFTid1 = await contract.NFTid();
    await contract.purchaseNft({ value });
    const uNFTid2 = await contract.NFTid();

    // Advance time by the vote duration
    await advanceTime(86400);

    await contract.vote(0, uNFTid1);

    // Try to vote with the NFT that has already been voted out
    await expect(contract.vote(0, uNFTid2)).to.be.revertedWith(
      "vote__NFTAlreadyVotedOut"
    );
  });

  it("should allow the owner of the last surviving NFT to claim the ETH", async () => {
    // Purchase two NFTs and vote one out
    const value = ethers.utils.parseEther("0.05");
    await contract.purchaseNft({ value });
    const uNFTid1 = await contract.NFTid();
    await contract.purchaseNft({ value });
    const uNFTid2 = await contract.NFTid();

    // Advance time by the vote duration
    await advanceTime(86400);

    await contract.vote(0, uNFTid1);

    // Advance time by the vote duration again and vote out the remaining NFT
    await advanceTime(86400);
    await contract.vote(0, uNFTid2);

    // The game is now over, so the owner of the surviving NFT can claim the ETH
    const balanceBefore = await owner.getBalance();
    await contract.claimEth();
    const balanceAfter = await owner.getBalance();

    expect(balanceAfter.sub(balanceBefore)).to.equal(value.mul(2));
  });

  it("should not allow a user to claim the ETH if the game is not over", async () => {
    // Purchase an NFT and try to claim the ETH
    const value = ethers.utils.parseEther("0.05");
    await contract.purchaseNft({ value });
    await expect(contract.claimEth()).to.be.revertedWith(
      "claimEth__GameNotOver"
    );
  });
});
