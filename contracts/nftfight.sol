// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// This contract allows people to purchase NFTs for 0.05 ETH, and then to
// participate in a weekly vote to determine which NFT to burn. The final
// NFT left standing gets to claim all the ETH.

import "@openzeppelin/contracts/utils/Counters.sol";

contract MyContract {
    using Counters for Counters.Counter;

    // NFT Id (should not go above 1000)
    Counters.Counter private NFTid;

    // epoch Counter
    Counters.Counter private epoch;

    // Total Number of NFTs currently available
    uint16 public totalNFTs;

    // Keeps track of which "NFT" belongs to who
    mapping(uint256 => address) public purchasedNFTs;

    // Keeps track of what NFTs are still existing
    uint256[] survivingNFTs;

    // !!! not sure if we need uint256 vs smaller
    // Epoch: (tokenid: vote)
    mapping(uint256 => mapping(uint256 => uint8)) voteTally;

    // per epoch whether you voted already or not
    mapping(uint256 => mapping(address => bool)) voteBool;

    // The total ETH collected from NFT purchases
    uint256 public totalEth;

    // The timestamp of the last vote
    uint256 public lastVote;

    // The minimum amount of ETH required to purchase an NFT
    uint256 public minEth = 0.05 ether;

    // The duration of a vote, in seconds (1 day)
    uint256 public voteDuration = 86400;

    // The constructor, which sets the owner of the contract
    constructor() {
        lastVote = block.timestamp;
        totalNFTs = 100;
    }

    error purchaseNFT__MintPriceNotMet();
    error claimEth__GameNotOver();
    error vote__IneligibleToVote();
    error vote__NFTAlreadyVotedOut();
    error vote__InsufficientMints();

    // Allows a user to purchase an NFT
    function purchaseNft() public payable {
        // Check if the user has sent the minimum amount of ETH
        if (msg.value < minEth) {
            revert purchaseNFT__MintPriceNotMet();
        }

        uint256 uNFTid = NFTid.current();

        purchasedNFTs[uNFTid] = msg.sender;
        survivingNFTs.push(uNFTid);

        NFTid.increment();

        totalEth += msg.value;
    }

    // Allows a user to vote on which NFT to burn
    function vote(uint256 nftId, uint256 yournftId) public {
        // if you do not have an NFT, have already been voted out then you cannot vote
        if (purchasedNFTs[yournftId] != msg.sender) {
            revert vote__IneligibleToVote();
        }

        if (survivingNFTs[nftId] == 0) {
            revert vote__NFTAlreadyVotedOut();
        }

        // if less than half the total NFTs have not been minted yet cannot start the game
        if (2 * NFTid.current() < totalNFTs) {
            revert vote__InsufficientMints();
        }

        uint256 currentEpoch = epoch.current();

        // if you already have voted then you cannot vote
        if (voteBool[currentEpoch][msg.sender] == true) {
            revert vote__IneligibleToVote();
        }

        // count votes and kick one nft out if its been longer than vote duration
        if (block.timestamp - lastVote >= voteDuration) {
            epoch.increment();
            lastVote = block.timestamp;

            // burn NFT that received the most votes - consider max heap if possible
            // !!! factor out into a "changing state function"

            uint256 mostVoted;
            uint16 mostVotes = 1;

            for (uint256 i = 0; i < survivingNFTs.length; i++) {
                uint256 element = survivingNFTs[i];

                if (element == 0) {
                    break;
                }

                uint16 voteCount = voteTally[currentEpoch][element];

                if (voteCount > mostVotes) {
                    mostVoted = element;
                    mostVotes = voteCount;
                }
            }

            // Delete from surviving NFTs and Purchased NFTs the most voted NFT
            purchasedNFTs[mostVoted] = address(0);

            // sets to 0
            delete survivingNFTs[mostVoted];
            totalNFTs = totalNFTs - 1;
        }

        voteBool[currentEpoch][msg.sender] = true;

        // have to check if the nftid they are voting for is valid
        voteTally[currentEpoch][nftId] = voteTally[currentEpoch][nftId] + 1;
    }

    function claimEth() public {
        if (totalNFTs != 1) {
            revert claimEth__GameNotOver();
        }

        uint256 winningNFT;

        for (uint256 i = 0; i < survivingNFTs.length; i++) {
            if (survivingNFTs[i] != 0) {
                winningNFT = survivingNFTs[i];
            }
        }

        address payable winner = payable(purchasedNFTs[winningNFT]);

        winner.transfer(totalEth);
    }

    /* ======================== Getters ======================== */
}
