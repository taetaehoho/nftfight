// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

// This contract allows people to purchase NFTs for 0.05 ETH, and then to
// participate in a weekly vote to determine which NFT to burn. The final
// NFT left standing gets to claim all the ETH.

import "chainlink/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "chainlink/v0.8/VRFConsumerBaseV2.sol";

error purchaseNFT__MintPriceNotMet();
error purchaseNFT__SoldOut();
error claimEth__GameNotOver();
error vote__IneligibleToVote();
error vote__NFTAlreadyVotedOut();
error vote__InsufficientMints();

contract NFTfight is VRFConsumerBaseV2 {
    // Chainlink VRF Variables
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    uint64 private immutable i_subscriptionId;
    bytes32 private immutable i_gasLane;
    uint32 private immutable i_callbackGasLimit;
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;

    // NFT Id
    uint256 public NFTid = 0;

    // epoch Counter
    uint256 public epoch;

    // Total Number of NFTs currently available
    uint256 public totalNFTs;

    // NFTid => purchaser Address
    mapping(uint256 => address) public purchasedNFTs;

    // Keeps track of what NFTs are still existing
    uint256[] survivingNFTs;

    // !!! not sure if we need uint256 vs smaller
    // Epoch => (tokenid => vote)
    mapping(uint256 => mapping(uint256 => uint256)) voteTally;

    // Epoch => address => bool whether address has voted for this epoch or not
    mapping(uint256 => mapping(address => bool)) voteBool;

    // The timestamp of the last vote
    uint256 public lastVote;

    // The minimum amount of ETH required to purchase an NFT
    uint256 public minEth;

    // The duration of a vote, in seconds (1 day) max value 32 years
    uint256 public voteDuration;

    // The constructor, which sets the owner of the contract
    constructor(
        uint256 _totalNFTs,
        uint256 _voteDuration,
        uint256 _minEth,
        address vrfCoordinatorV2,
        uint64 subscriptionId,
        bytes32 gasLane, // keyHash
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2(vrfCoordinatorV2) {
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinatorV2);
        i_gasLane = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;
        lastVote = block.timestamp;
        totalNFTs = _totalNFTs;
        minEth = _minEth;
        voteDuration = _voteDuration;
    }

    event NFTVotedOut(uint256 indexed _NFTid);
    event RandomRequested(uint256 indexed requestId);

    // Allows a user to purchase an NFT
    function purchaseNft() public payable {
        // Check if the user has sent the minimum amount of ETH
        if (msg.value < minEth) {
            revert purchaseNFT__MintPriceNotMet();
        }

        if (NFTid >= totalNFTs) {
            revert purchaseNFT__SoldOut();
        }

        purchasedNFTs[NFTid] = msg.sender;
        survivingNFTs.push(NFTid);

        NFTid = NFTid + 1;
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

        // game cannot start until all NFTs have been minted
        // !!! revisit design decision
        if (NFTid < totalNFTs) {
            revert vote__InsufficientMints();
        }

        // if you already have voted then you cannot vote
        if (voteBool[epoch][msg.sender] == true) {
            revert vote__IneligibleToVote();
        }

        // count votes and kick one nft out if its been longer than vote duration
        if (block.timestamp - lastVote >= voteDuration) {
            epoch = epoch + 1;
            lastVote = block.timestamp;

            // burn NFT that received the most votes - consider max heap if possible
            // !!! factor out into a "changing state function"

            uint256 mostVoted;
            uint256 mostVotes = 1;
            uint256 tieIndex = 0;
            uint256[] memory mostVotedTies = new uint256[](totalNFTs);

            // !!! change this to view function to save gas

            for (uint16 i = 0; i < survivingNFTs.length; i++) {
                uint256 element = survivingNFTs[i];

                if (element == 0) {
                    break;
                }

                uint256 voteCount = voteTally[epoch][element];

                if (voteCount > mostVotes) {
                    mostVoted = element;
                    mostVotes = voteCount;
                    delete mostVotedTies;
                    tieIndex = 0;
                } else if (voteCount == mostVotes) {
                    mostVotedTies[tieIndex] = element;
                    tieIndex = tieIndex + 1;
                }
            }

            uint256 requestId = i_vrfCoordinator.requestRandomWords(
                i_gasLane,
                i_subscriptionId,
                REQUEST_CONFIRMATIONS,
                i_callbackGasLimit,
                NUM_WORDS
            );

            // !!! have to implement the actual tie breaking here

            emit RandomRequested(requestId);

            // Delete from surviving NFTs and Purchased NFTs the most voted NFT
            purchasedNFTs[mostVoted] = address(0);
            delete survivingNFTs[mostVoted];
            totalNFTs = totalNFTs - 1;
            emit NFTVotedOut(mostVoted);
        }

        voteBool[epoch][msg.sender] = true;

        // have to check if the nftid they are voting for is valid
        voteTally[epoch][nftId] = voteTally[epoch][nftId] + 1;
    }

    // !!! change to fit VRF
    function fulfillRandomWords(
        uint256 requestId,
        uint256[] memory randomWords
    ) internal override {}

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

        winner.transfer(address(this).balance);
    }

    /* ======================== Helpers ======================== */

    function getSurviving(uint256 _NFTid) public view returns (bool surviving) {
        if (survivingNFTs[_NFTid] != 0) {
            return true;
        }
    }
}
