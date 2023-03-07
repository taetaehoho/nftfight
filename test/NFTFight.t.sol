// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;

import "forge-std/Test.sol";
import "../src/NFTfight.sol";

contract NFTfightTest is Test {
    NFTfight nftfight;

    /**        
     *  address vrfCoordinatorV2,
        uint64 subscriptionId,
        bytes32 gasLane, // keyHash
        uint32 callbackGasLimit,
        uint32 _totalNFTs,
        uint32 _voteDuration,
        uint256 _minEth */

    address vrfCoordinatorV2;
    uint64 subscriptionId;
    bytes32 gasLane;
    uint32 callbackGasLimit;
    uint32 _totalNFTs;
    uint32 _voteDuration = 86400;
    uint256 _minEth = 5;

    function setup() {
        nftfight = new NFTfight();
    }

    function testPurchaseNFT() {}
}
