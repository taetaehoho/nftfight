// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "forge-std/Test.sol";

// review: run this: forge test --match-contract TesterTest -vvv

contract Tester {
    function arrayReduction(uint testNum) external pure returns (uint) {
        uint[] memory mostVotedTies = new uint[](40);

        // line 182
        uint length = mostVotedTies.length;
        assembly { mstore(mostVotedTies, sub(mload(mostVotedTies), length)) }

        // line 190
        mostVotedTies[0] = testNum;

        return mostVotedTies[0];
    }
}


contract TesterTest is Test {
    Tester tester;

    function setUp() public {
        tester = new Tester();
    }

    function testArrayReduction() public {
        uint num = tester.arrayReduction(5);

        assertEq(num, 5);
    }


}
