// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

error purchaseNFT__MintPriceNotMet();
error purchaseNFT__SoldOut();
error claimEth__GameNotOver();
error vote__IneligibleToVote();
error vote__NFTAlreadyVotedOut();
error InsufficientMints();
error claimETH__VoteIncomplete();

import "chainlink/v0.8/VRFConsumerBaseV2.sol";
import "chainlink/v0.8/interfaces/VRFCoordinatorV2Interface.sol";

contract NFTfight is VRFConsumerBaseV2 {
    // VRF parameters
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    uint64 private immutable i_subscriptionId;
    bytes32 private immutable i_gasLane;
    uint32 private immutable i_callbackGasLimit;
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;

    // NFTid incremented per purchase
    uint32 public NFTid = 0;

    // Epoch incremented per vote epoch
    uint32 public epoch;

    // Total number of NFTs
    uint32 public immutable i_totalNFTs;

    // Total number of remaining NFTs
    uint32 public remainingNFTs;

    // The duration of a vote, in seconds
    uint32 public voteDuration;

    // NFTid => purchaser Address
    mapping(uint32 => address) public purchasedNFTs;

    // purchaser Address => purchase Price
    mapping(address => uint256) public purchasePrice;

    // Keeps track of what NFTs are still surviving
    uint32[] survivingNFTs;

    // Epoch => (tokenid => vote)
    mapping(uint32 => mapping(uint32 => uint32)) voteTally;

    // Epoch => address => bool whether address has voted for this epoch or not
    mapping(uint32 => mapping(address => bool)) voteBool;

    // The timestamp of the last vote
    uint256 public lastVote;

    // The minimum amount of ETH required to purchase an NFT
    uint256 public minEth;

    event NFTVotedOut(uint256 indexed _NFTid);
    event NFTPurchased(uint256 indexed _NFTid, address indexed _buyer);
    event TieBreakerRequested(uint256 indexed requestId);
    event Winner(address indexed _winner);

    constructor(
        address vrfCoordinatorV2,
        uint64 subscriptionId,
        bytes32 gasLane, // keyHash
        uint32 callbackGasLimit,
        uint32 _totalNFTs,
        uint32 _voteDuration,
        uint256 _minEth
    ) VRFConsumerBaseV2(vrfCoordinatorV2) {
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinatorV2);
        i_gasLane = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;
        lastVote = block.timestamp;
        i_totalNFTs = _totalNFTs;
        remainingNFTs = _totalNFTs;
        minEth = _minEth;
        voteDuration = _voteDuration;
    }

    // can send more ETH than min ETH!
    function purchaseNft() public payable {
        // Check if the user has sent the minimum amount of ETH
        if (msg.value < minEth) {
            revert purchaseNFT__MintPriceNotMet();
        }

        if (NFTid >= i_totalNFTs) {
            revert purchaseNFT__SoldOut();
        }

        purchasedNFTs[NFTid] = msg.sender;
        survivingNFTs.push(NFTid);
        purchasePrice[msg.sender] = msg.value;

        emit NFTPurchased(NFTid, msg.sender);

        NFTid = NFTid + 1;
    }

    // Allows a user to vote on which NFT to burn
    function vote(uint16 nftId, uint16 yournftId) public {
        // if you do not have an NFT, have already been voted out then you cannot vote
        if (purchasedNFTs[yournftId] != msg.sender) {
            revert vote__IneligibleToVote();
        }

        // you cannot vote for an NFT that is already out!
        if (survivingNFTs[nftId] == 0) {
            revert vote__NFTAlreadyVotedOut();
        }

        // game cannot start until all NFTs have been minted
        if (NFTid < i_totalNFTs) {
            revert InsufficientMints();
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

            uint32 mostVoted;
            uint32 mostVotes = 1;
            uint32 tieIndex = 0;
            uint32[] memory mostVotedTies = new uint32[](i_totalNFTs);

            // !!! change this to view function to save gas

            for (uint16 i = 0; i < survivingNFTs.length; i++) {
                uint32 element = survivingNFTs[i];

                if (element == 0) {
                    break;
                }

                uint32 voteCount = voteTally[epoch][element];

                // !!! implement array resizing in Yul otherwise mostVotedTies will remain length of highest ties
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

            uint256[] memory tieLength = new uint256[](mostVotedTies.length);

            // !!! does this work or is the array init at totalNFTs
            for (uint16 i = 0; i < mostVotedTies.length; i++) {
                tieLength[i] = purchasePrice[purchasedNFTs[mostVotedTies[i]]];
            }

            uint256 minVal = type(uint256).max;

            for (uint16 i = 0; i < tieLength.length; i++) {
                if (tieLength[i] < minVal) {
                    minVal = tieLength[i];
                    mostVoted = mostVotedTies[i];
                }
            }

            // Delete from surviving NFTs and Purchased NFTs the most voted NFT
            purchasedNFTs[mostVoted] = address(0);
            delete survivingNFTs[mostVoted];
            remainingNFTs = remainingNFTs - 1;
            emit NFTVotedOut(mostVoted);
        }

        voteBool[epoch][msg.sender] = true;

        voteTally[epoch][nftId] = voteTally[epoch][nftId] + 1;
    }

    function claimETH() public {
        if (remainingNFTs > 2) {
            revert claimETH__VoteIncomplete();
        }

        if (i_totalNFTs != NFTid) {
            revert InsufficientMints();
        }

        uint32 winningNFT;

        uint32[] memory winningNFTs = constructWinningArr();

        uint256[] memory pricePaid = new uint256[](2);
        for (uint256 i = 0; i < 2; i++) {
            pricePaid[i] = purchasePrice[purchasedNFTs[winningNFTs[i]]];
        }

        // give NFT to whoever paid more initially
        if (pricePaid[0] > pricePaid[1]) {
            winningNFT = winningNFTs[0];
            transferToWinner(purchasedNFTs[winningNFT]);
        } else if (pricePaid[0] < pricePaid[1]) {
            winningNFT = winningNFTs[1];
            transferToWinner(purchasedNFTs[winningNFT]);
        } else {
            uint256 requestId = i_vrfCoordinator.requestRandomWords(
                i_gasLane,
                i_subscriptionId,
                REQUEST_CONFIRMATIONS,
                i_callbackGasLimit,
                NUM_WORDS
            );

            emit TieBreakerRequested(requestId);
        }
    }

    function fulfillRandomWords(
        uint256 /* requestId */,
        uint256[] memory randomWords
    ) internal override {
        // !!! Any way to not have to redo this work while still using memory array?

        uint32[] memory winningNFTs = constructWinningArr();

        uint256 indexOfWinner = randomWords[0] % 2;

        address winnerAddress = purchasedNFTs[winningNFTs[indexOfWinner]];

        transferToWinner(winnerAddress);
    }

    /* ======================== Helpers ======================== */

    function getSurviving(uint256 _NFTid) public view returns (bool surviving) {
        if (survivingNFTs[_NFTid] != 0) {
            return true;
        }
    }

    function constructWinningArr()
        public
        view
        returns (uint32[] memory _winningNFTs)
    {
        uint32[] memory winningNFTs = new uint32[](2);
        uint8 counter = 0;

        for (uint256 i = 0; i < survivingNFTs.length; i++) {
            if (survivingNFTs[i] != 0) {
                winningNFTs[counter] = survivingNFTs[i];
                counter = counter + 1;
            }
        }

        return winningNFTs;
    }

    function transferToWinner(address _winner) public {
        address payable winner = payable(_winner);
        winner.transfer(address(this).balance);

        emit Winner(winner);
    }
}
