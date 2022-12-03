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

    // NFTid => purchaser Address
    mapping(uint16 => address) public purchasedNFTs;

    // Keeps track of what NFTs are still existing
    uint16[] survivingNFTs;

    // !!! not sure if we need uint256 vs smaller
    // Epoch => (tokenid => vote)
    mapping(uint16 => mapping(uint16 => uint16)) voteTally;

    // Epoch => address => bool whether address has voted for this epoch or not
    mapping(uint16 => mapping(address => bool)) voteBool;

    // The total ETH collected from NFT purchases
    uint256 public totalEth;

    // The timestamp of the last vote
    uint256 public lastVote;

    // The minimum amount of ETH required to purchase an NFT
    uint256 public minEth;

    // The duration of a vote, in seconds (1 day) max value 32 years
    uint32 public voteDuration;

    // The constructor, which sets the owner of the contract
    constructor(uint16 _totalNFTs, uint32 _voteDuration, uint256 _minEth) {
        lastVote = block.timestamp;
        totalNFTs = _totalNFTs;
        minEth = _minEth;
        voteDuration = _voteDuration;
    }

    error purchaseNFT__MintPriceNotMet();
    error claimEth__GameNotOver();
    error vote__IneligibleToVote();
    error vote__NFTAlreadyVotedOut();
    error vote__InsufficientMints();

    event NFTVotedOut(uint16 indexed _NFTid);

    // Allows a user to purchase an NFT
    function purchaseNft() public payable {
        // Check if the user has sent the minimum amount of ETH
        if (msg.value < minEth) {
            revert purchaseNFT__MintPriceNotMet();
        }

        uint16 uNFTid = uint16(NFTid.current());

        purchasedNFTs[uNFTid] = msg.sender;
        survivingNFTs.push(uNFTid);

        NFTid.increment();

        totalEth += msg.value;
    }

    // Allows a user to vote on which NFT to burn
    function vote(uint16 nftId, uint16 yournftId) public {
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

        uint16 currentEpoch = uint16(epoch.current());

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

            uint16 mostVoted;
            uint16 mostVotes = 1;

            for (uint16 i = 0; i < survivingNFTs.length; i++) {
                uint16 element = survivingNFTs[i];

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
            delete survivingNFTs[mostVoted];
            totalNFTs = totalNFTs - 1;
            emit NFTVotedOut(mostVoted);
        }

        voteBool[currentEpoch][msg.sender] = true;

        // have to check if the nftid they are voting for is valid
        voteTally[currentEpoch][nftId] = voteTally[currentEpoch][nftId] + 1;
    }

    function claimEth() public {
        if (totalNFTs != 1) {
            revert claimEth__GameNotOver();
        }

        uint16 winningNFT;

        for (uint16 i = 0; i < survivingNFTs.length; i++) {
            if (survivingNFTs[i] != 0) {
                winningNFT = survivingNFTs[i];
            }
        }

        address payable winner = payable(purchasedNFTs[winningNFT]);

        winner.transfer(totalEth);
    }

    /* ======================== Getters ======================== */

    function getNFTid() public view returns (uint256 nftId) {
        return NFTid.current();
    }

    // !!!
    function getEpoch() public view returns (uint256 epoch) {
        return epoch.current();
    }

    function getTotalEth() public view returns (uint256 totalEth) {
        return totalEth;
    }

    function getSurviving(uint16 _NFTid) public view returns (bool surviving) {
        return survivingNFTs[_NFTid];
    }
}
