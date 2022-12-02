// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// This contract allows people to purchase NFTs for 0.05 ETH, and then to
// participate in a weekly vote to determine which NFT to burn. The final
// NFT left standing gets to claim all the ETH.

contract MyContract {
    // Address of the contract owner
    address public owner;

    // The NFTs that have been purchased
    mapping(address => uint256) public nfts;

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
    constructor() public {
        owner = msg.sender;
    }

    // Allows a user to purchase an NFT
    function purchaseNft() public payable {
        // Check if the user has sent the minimum amount of ETH
        require(
            msg.value >= minEth,
            "You must send at least 0.05 ETH to purchase an NFT"
        );

        // Store the NFT ID and the address of the user who purchased it
        nfts[msg.sender] = nftBurned;

        // Update the total ETH collected
        totalEth += msg.value;
    }

    // Allows a user to vote on which NFT to burn
    function vote(uint256 nftId) public {
        // Check if a vote is currently in progress
        require(
            now - lastVote >= voteDuration,
            "A vote is already in progress"
        );

        // Check if the user has the NFT they are voting to burn
        require(
            nfts[msg.sender] == nftId,
            "You do not have the NFT you are trying to burn"
        );

        // Store the NFT ID and the address of the user who voted
        lastNft = nftId;
        lastVote = now;
    }

    // Burns the NFT that received the most votes
    function burnNft() public {
        // Check if the current vote has expired
        require(
            now - lastVote < voteDuration,
            "The current vote has not expired"
        );

        // Burn the NFT that received the most votes
        nftBurned++;
        delete nfts[lastNft];

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
