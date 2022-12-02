// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// This contract allows people to purchase NFTs for 0.05 ETH, and then to
// participate in a weekly vote to determine which NFT to burn. The final
// NFT left standing gets to claim all the ETH.

import "@openzeppelin/contracts/utils/Counters.sol";

contract MyContract {
    using Counters for Counters.Counter;

    // NFT Id (should not go above 1000)
    Counters.Counter public NFTid;

    // Total Number of NFTs to Start
    uint16 public totalNFTs = 1000;

    // Keeps track of which "NFT" belongs to who
    mapping(address => Counters.Counter) public purchasedNFTs;

    // The total ETH collected from NFT purchases
    uint256 public totalEth;

    // The number of NFTs that have been burned
    uint256 public nftBurned;

    // The timestamp of the last vote
    uint256 public lastVote;

    // The address of the last NFT that was burned
    address public lastNft;

    // The minimum amount of ETH required to purchase an NFT
    uint256 public minEth = 0.05 ether;

    // The duration of a vote, in seconds
    uint256 public voteDuration = 86400;

    // The constructor, which sets the owner of the contract
    constructor() public {}

    error purchaseNFT__MintPriceNotMet();

    // Allows a user to purchase an NFT
    function purchaseNft() public payable {
        // Check if the user has sent the minimum amount of ETH
        if (msg.value < minEth) {
            revert purchaseNFT__MintPriceNotMet();
        }

        purchasedNFTs[msg.sender] = NFTid;

        NFTid.increment();

        totalEth += msg.value;
    }

    // Allows a user to vote on which NFT to burn
    function vote(uint256 nftId) public {
        // Check if a vote is currently in progress
        require(
            block.timestamp - lastVote >= voteDuration,
            "A vote is already in progress"
        );

        // Store the NFT ID and the address of the user who voted
        lastNft = NFTid;
        lastVote = block.timestamp;
    }

    // Burns the NFT that received the most votes
    function burnNft() public {
        // Check if the current vote has expired
        require(
            block.timestamp - lastVote < voteDuration,
            "The current vote has not expired"
        );

        // Burn the NFT that received the most votes
        nftBurned++;
        delete purchasedNFTs[lastNft];

        // Send all the collected ETH to the owner of the last NFT
        lastNft.transfer(totalEth);
    }

    function claimEth() public {
        // Check if the caller is the owner of the last remaining NFT
        require(
            msg.sender == lastNft,
            "Only the owner of the last remaining NFT can claim the collected ETH"
        );

        // Send all the collected ETH to the caller
        msg.sender.transfer(totalEth);
    }
}
