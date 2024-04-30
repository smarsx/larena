// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {Coin} from "../../src/Coin.sol";
import {Ocmeme} from "../../src/Ocmeme.sol";
import {Pages} from "../../src/Pages.sol";
import {Reserve} from "../../src/utils/Reserve.sol";
import {Utilities} from "../utils/Utilities.sol";
import {MemoryPlus} from "../utils/Memory.sol";

contract GeneralIntegrationTest is Test, MemoryPlus {
    Ocmeme ocmeme;
    Coin internal coin;
    Pages internal pages;
    Reserve internal reserve;
    Utilities internal utils;
    address actor;
    address[] users;

    function setUp() public {
        utils = new Utilities();
        address coinAddress = utils.predictContractAddress(address(this), 1, vm);
        address pagesAddress = utils.predictContractAddress(address(this), 2, vm);
        address ocmemeAddress = utils.predictContractAddress(address(this), 3, vm);
        reserve = new Reserve(
            Ocmeme(ocmemeAddress),
            Pages(pagesAddress),
            Coin(coinAddress),
            address(this)
        );
        coin = new Coin(ocmemeAddress, pagesAddress);
        pages = new Pages(block.timestamp, coin, address(reserve), Ocmeme(ocmemeAddress));
        ocmeme = new Ocmeme(coin, Pages(pagesAddress), address(reserve));
        actor = utils.createUsers(1, vm)[0];
        users = utils.createUsers(5, vm);

        vm.prank(ocmeme.owner());
        ocmeme.setStart();
    }

    function testShare(uint136 p) public view {
        uint256 a = FixedPointMathLib.mulDiv(p, ocmeme.GOLD_SHARE(), ocmeme.PAYOUT_DENOMINATOR());
        uint256 b = FixedPointMathLib.mulDiv(p, ocmeme.SILVER_SHARE(), ocmeme.PAYOUT_DENOMINATOR());
        uint256 c = FixedPointMathLib.mulDiv(p, ocmeme.BRONZE_SHARE(), ocmeme.PAYOUT_DENOMINATOR());
        uint256 d = p -
            (FixedPointMathLib.mulDiv(p, ocmeme.GOLD_SHARE(), ocmeme.PAYOUT_DENOMINATOR()) +
                FixedPointMathLib.mulDiv(p, ocmeme.SILVER_SHARE(), ocmeme.PAYOUT_DENOMINATOR()) +
                FixedPointMathLib.mulDiv(p, ocmeme.BRONZE_SHARE(), ocmeme.PAYOUT_DENOMINATOR()));
        assertEq(a + b + c + d, p);
    }

    function testBitPack() public pure {
        uint8 claims;
        uint256 a = claims & (1 << uint8(Ocmeme.ClaimType.GOLD));
        uint256 b = claims & (1 << uint8(Ocmeme.ClaimType.SILVER));
        uint256 c = claims & (1 << uint8(Ocmeme.ClaimType.BRONZE));
        uint256 d = claims & (1 << uint8(Ocmeme.ClaimType.VAULT));
        assertEq(a, 0);
        assertEq(b, 0);
        assertEq(c, 0);
        assertEq(d, 0);

        claims = uint8(claims | (1 << uint8(Ocmeme.ClaimType.GOLD)));
        claims = uint8(claims | (1 << uint8(Ocmeme.ClaimType.BRONZE)));

        assertEq(1, claims & (1 << uint8(Ocmeme.ClaimType.GOLD)));
        assertTrue(claims & (1 << uint8(Ocmeme.ClaimType.BRONZE)) > 0);

        claims = 255;

        uint256 e = claims & (1 << uint8(Ocmeme.ClaimType.GOLD));
        uint256 f = claims & (1 << uint8(Ocmeme.ClaimType.SILVER));
        uint256 g = claims & (1 << uint8(Ocmeme.ClaimType.BRONZE));
        uint256 h = claims & (1 << uint8(Ocmeme.ClaimType.VAULT));
        assertTrue(e > 0);
        assertTrue(f > 0);
        assertTrue(g > 0);
        assertTrue(h > 0);
    }

    function testTime(uint48 _warp) public view {
        vm.assume(_warp > 0);
        (uint256 epochID, uint256 time) = ocmeme.currentEpoch();
        uint256 time2 = ocmeme.epochStart(epochID);
        assertEq(time, time2);
    }

    function testBasicImpl(uint40 _warp) public brutalizeMemory {
        vm.assume(_warp > 0);
        vm.warp(_warp);

        (uint256 a, uint256 b) = ocmeme.currentEpoch();
        (uint256 c, uint256 d) = currentEpochBasic();
        assertEq(a, c);
        assertEq(b, d);
    }

    function currentEpochBasic() internal view returns (uint256, uint256) {
        uint256 epochID;
        uint256 start;
        epochID = block.timestamp - ocmeme.$start();
        epochID = epochID / ocmeme.EPOCH_LENGTH();
        epochID = epochID + 1;

        start = epochID - 1;
        start = start * ocmeme.EPOCH_LENGTH();
        start = start + ocmeme.$start();
        return (epochID, start);
    }

    function test_index_strictly_increases_or_resets() public {
        uint256 prev;

        for (uint i = 1; i < 100; i++) {
            uint256 p = ocmeme.getPrice();
            vm.deal(actor, p);
            vm.prank(actor);
            ocmeme.mint{value: p}();

            (uint256 index, , , ) = ocmeme.getMemeData(i);
            if (1 == index) {} else {
                assertGt(index, prev);
            }
            prev = index;
        }
    }
}
