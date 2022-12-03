// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// This contract allows people to purchase NFTs for 0.05 ETH, and then to
// participate in a weekly vote to determine which NFT to burn. The final
// NFT left standing gets to claim all the ETH.

import "@openzeppelin/contracts/utils/Counters.sol";

// review: chads use Foundry

contract MyContract {
    using Counters for Counters.Counter;

    // NFT Id (should not go above 1000)
    Counters.Counter private NFTid;

    // epoch Counter
    Counters.Counter private epoch;

    // review: why uint16?
    //
    // note:   people generally use smaller uints for slot packing, which saves gas, more than to give the number a cap
    //         EVM is stack-based and each unit in the stack is a slot. a slot holds 32 bytes (i.e. 256 bits — hence uint256)
    //         in some cases less slots = less gas (but only if you use enough to pack it to 32 bytes at a time, if not it actually
    //         uses more gas because EVM needs to pack the unused space with 0's, which costs gas)
    //         I'm still learning about EVM and packing but it looks like this doesn't get any gas benefits since your only pushing 1 uint16 at a time

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

    // review: what is the need for this when address(this).balance exists?
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

        // review: where does this require NFTid <= totalNFTs?
        uint16 uNFTid = uint16(NFTid.current());

        purchasedNFTs[uNFTid] = msg.sender;
        survivingNFTs.push(uNFTid);

        NFTid.increment();

        totalEth += msg.value;
    }

    // review: what if a user transfers the NFT?
    //
    // note:   you could make the NFT's soulbound — either forever or until the fight is won
    //         this can be done by overriding the OZ's NFT transfer functions once you implement the NFT part, and reverting if the auction isn't won
    //         look into overriding functions when you're ready

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

    // review: you already have epoch defined as a storage variable
    //         if you're using a solidity plugin for your code editor (you should!) this will have a 
    //         yellow line under it. also if you try to compile it would give you a yellow and red warning
    //         yellow: for creating a variable that shadows another
    //         red: for trying to get .current() out of that new variable, which isn't an OZ counter
    //
    // note:   pretty sure the main purpose of an OZ counter was to be safe back before EVM checked for overflow
    //         OZ counters are pretty useless now imo
    function getEpoch() public view returns (uint256 epoch) {
        return epoch.current();
    }
    
    // review: useless getter and variable is already defined
    //         getters are automatically created for public storage variables — and totalEth is public                
    function getTotalEth() public view returns (uint256 totalEth) {
        return totalEth;
    }

    // review: this doesn't work for a couple of reasons
    //         with array[i] you're querying the index of the survivingNFTs array — not the item in the array
    //         so for an array x = [1,2,3] and i = 1, x[i] == 2
    //         also it returns the id at index _NFTid, not a bool
    //
    // note:   use OpenZeppelin's EnummerableSet.sol
    //         to use it, import EnummerableSet.sol (it's in utils/structs) and in the contract (usually at the top, 
    //         but you can put it anywhere since solidity is effectively just a mess of letters before it compiles) 
    //         type 'using EnummerableSet for EnumerableSet.UintSet;'
    //         then instead of 'uint16[] survivingNFTs', do EnumerableSet.UintSet survivingNFTs' — then look at the functions
    //         in EnummerableSet.sol — one of them is .contains(). You can put survivingNFTs.contains(_NFTid) in this function
    //
    //         p.s.   the info on using EnummerableSet that I gave is also at the top of EnummerableSet.sol
    //         p.p.s. you didn't define the visibility of survivingNFTs (you wrote 'uint16[] survivingNFTs')
    //                because this defaults to private.. yet you used 'Counters.Counter private NFTid;' 
    //                instead of 'Counters.Counter NFTid;'  — just noting this randomly 
    function getSurviving(uint16 _NFTid) public view returns (bool surviving) {
        return survivingNFTs[_NFTid];
    }
}
