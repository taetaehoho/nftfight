// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

// This contract allows people to purchase NFTs for 0.05 ETH, and then to
// participate in a weekly vote to determine which NFT to burn. The final
// NFT left standing gets to claim all the ETH.

error purchaseNFT__MintPriceNotMet();
error purchaseNFT__SoldOut();
error claimEth__GameNotOver();
error vote__IneligibleToVote();
error vote__NFTAlreadyVotedOut();
error InsufficientMints();
error claimETH__VoteIncomplete();

contract NFTfight {
    // NFT Id
    uint32 public NFTid = 0;

    // epoch Counter
    uint32 public epoch;

    // Total number of NFTs
    uint32 public immutable i_totalNFTs;

    // Total number of remaining NFTs
    uint32 public remainingNFTs;

    // The duration of a vote, in seconds (1 day) max value 32 years
    uint32 public voteDuration;

    // NFTid => purchaser Address
    mapping(uint256 => address) public purchasedNFTs;

    // purchaser Address => NFTid
    mapping(address => uint256) public purchasePrice;

    // Keeps track of what NFTs are still existing
    uint32[] survivingNFTs;

    // Epoch => (tokenid => vote)
    mapping(uint256 => mapping(uint256 => uint256)) voteTally;

    // Epoch => address => bool whether address has voted for this epoch or not
    mapping(uint256 => mapping(address => bool)) voteBool;

    // The timestamp of the last vote
    uint256 public lastVote;

    // The minimum amount of ETH required to purchase an NFT
    uint256 public minEth;

    // The constructor, which sets the owner of the contract
    constructor(uint32 _totalNFTs, uint32 _voteDuration, uint256 _minEth) {
        lastVote = block.timestamp;
        i_totalNFTs = _totalNFTs;
        remainingNFTs = _totalNFTs;
        minEth = _minEth;
        voteDuration = _voteDuration;
    }

    event NFTVotedOut(uint256 indexed _NFTid);
    event NFTPurchased(uint256 indexed _NFTid, address indexed _buyer);

    // Allows a user to purchase an NFT
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
        // !!! revisit design decision
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
            // !!! factor out into a "changing state function"

            uint256 mostVoted;
            uint256 mostVotes = 1;
            uint256 tieIndex = 0;
            uint256[] memory mostVotedTies = new uint256[](i_totalNFTs);

            // !!! change this to view function to save gas

            for (uint16 i = 0; i < survivingNFTs.length; i++) {
                uint256 element = survivingNFTs[i];

                if (element == 0) {
                    break;
                }

                uint256 voteCount = voteTally[epoch][element];

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

        uint32[] memory winningNFT = new uint32[](2);
        uint8 counter = 0;

        for (uint256 i = 0; i < survivingNFTs.length; i++) {
            if (survivingNFTs[i] != 0) {
                winningNFT[counter] = survivingNFTs[i];
                counter = counter + 1;
            }
        }

        // !!! decide some tie breaking mechanism for last 2 NFTs

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
