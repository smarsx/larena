// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2 as console} from "forge-std/console2.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {Coin} from "../../src/Coin.sol";
import {Ocmeme} from "../../src/Ocmeme.sol";
import {Pages} from "../../src/Pages.sol";
import {Reserve} from "../../src/utils/Reserve.sol";
import {Utilities} from "../utils/Utilities.sol";
import {NFTMeta} from "../../src/libraries/NFTMeta.sol";
import {MemoryPlus} from "../utils/Memory.sol";
import {Interfaces} from "../utils/Interfaces.sol";

contract VoteIntegrationTest is Test, MemoryPlus, Interfaces {
    Ocmeme ocmeme;
    Coin internal coin;
    Pages internal pages;
    Reserve internal reserve;
    Utilities internal utils;
    address actor;

    uint256 public pageID;

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

        vm.prank(ocmeme.owner());
        ocmeme.setStart();

        // mint page
        uint256 price = pages.pagePrice();
        vm.prank(address(ocmeme));
        coin.mintCoin(actor, price);

        vm.prank(address(actor));
        pageID = pages.mintFromCoin(price, false);

        // submit
        vm.prank(address(actor));
        ocmeme.submit(pageID, 0, NFTMeta.TypeURI(0), "", "");
    }

    function testNoDeadzone(uint256 _warp, uint200 _amt) public {
        vm.assume(_warp < ocmeme.DECAY_ZONE());
        vm.warp(block.timestamp + _warp);

        // mint too to be used in vote.
        vm.prank(address(ocmeme));
        coin.mintCoin(actor, _amt);

        // vote and capture before/after.
        Ocmeme.Vote memory vp = getVotes(pageID, ocmeme);
        vm.prank(actor);
        ocmeme.vote(pageID, _amt, false);
        Ocmeme.Vote memory vp2 = getVotes(pageID, ocmeme);

        // when no deadzone, vote utilization = 100%
        assertEq(vp.votes + _amt, vp2.votes);
    }

    function testMaybeDeadzone(uint256 _warp, uint200 _amt) public {
        vm.assume(_warp < ocmeme.EPOCH_LENGTH());
        vm.assume(_amt > 3);
        vm.warp(block.timestamp + _warp);

        (, uint256 start) = ocmeme.currentEpoch();
        bool isdz = block.timestamp - start > ocmeme.DECAY_ZONE();

        Ocmeme.Vote memory vp = getVotes(pageID, ocmeme);

        vm.prank(address(ocmeme));
        coin.mintCoin(actor, _amt);

        vm.prank(actor);
        ocmeme.vote(pageID, _amt, false);

        Ocmeme.Vote memory vp2 = getVotes(pageID, ocmeme);

        if (isdz) {
            assertTrue(vp.votes + _amt > vp2.votes);
        } else {
            assertEq(vp.votes + _amt, vp2.votes);
        }
    }

    function testDeadzone() public brutalizeMemory {
        (, uint256 start) = ocmeme.currentEpoch();
        vm.warp(start + ocmeme.DECAY_ZONE() + 1 hours);

        vm.prank(address(ocmeme));
        coin.mintCoin(actor, 100 ether);

        uint256[] memory diffs = new uint256[](5);
        for (uint i; i < 5; i++) {
            vm.warp(block.timestamp + 2 hours);

            Ocmeme.Vote memory vp = getVotes(pageID, ocmeme);
            vm.prank(actor);
            ocmeme.vote(pageID, 1 ether, false);
            Ocmeme.Vote memory vp2 = getVotes(pageID, ocmeme);

            diffs[i] = (vp2.votes - vp.votes);
        }

        assertTrue(diffs[0] > diffs[1]);
        assertTrue(diffs[1] > diffs[2]);
        assertTrue(diffs[2] > diffs[3]);
        assertTrue(diffs[3] > diffs[4]);
    }

    function testDeadzone2(uint256 _warp, uint200 _amt) public brutalizeMemory {
        _warp = bound(_warp, 1, 100 * ocmeme.EPOCH_LENGTH());
        _amt = uint200(bound(_amt, 1e18, type(uint200).max));
        vm.warp(_warp);

        (, uint256 start) = ocmeme.currentEpoch();

        // mint page
        uint256 price = pages.pagePrice();
        vm.prank(address(ocmeme));
        coin.mintCoin(actor, price);

        vm.prank(address(actor));
        uint256 mypage = pages.mintFromCoin(price, false);

        // submit, reverse time if submission deadzone. need to submit to vote.
        while (block.timestamp > start + ocmeme.SUBMISSION_DEADLINE()) {
            vm.warp(block.timestamp - 1 days);
        }
        vm.prank(address(actor));
        ocmeme.submit(mypage, 0, NFTMeta.TypeURI(0), "", "");

        // mint _amt to be voted with
        vm.prank(address(ocmeme));
        coin.mintCoin(actor, _amt);

        // vote and capture before/after results
        Ocmeme.Vote memory vp = getVotes(mypage, ocmeme);
        vm.prank(actor);
        ocmeme.vote(mypage, _amt, false);
        Ocmeme.Vote memory vp2 = getVotes(mypage, ocmeme);

        if (block.timestamp > start + ocmeme.DECAY_ZONE()) {
            assertTrue(vp2.votes - vp.votes < _amt);
        } else {
            assertEq(vp2.votes - vp.votes, _amt);
        }
    }

    function testMaxDecay() public {
        uint256 amt = 100 ether;
        uint256 expectedAmt = amt / 10;
        (, uint256 start) = ocmeme.currentEpoch();
        vm.warp(start + ocmeme.EPOCH_LENGTH() - 1000);

        // mint _amt to be voted with
        vm.prank(address(ocmeme));
        coin.mintCoin(actor, amt);

        // vote and capture before/after results
        Ocmeme.Vote memory vp = getVotes(pageID, ocmeme);
        vm.prank(actor);
        ocmeme.vote(pageID, amt, false);
        Ocmeme.Vote memory vp2 = getVotes(pageID, ocmeme);

        assertEq(vp2.votes - vp.votes, expectedAmt);
    }

    function testMinDecay() public {
        uint256 amt = 1000 ether;
        uint256 expectedAmt = 963 ether;
        (, uint256 start) = ocmeme.currentEpoch();
        vm.warp(start + ocmeme.DECAY_ZONE() + 1);

        // mint _amt to be voted with
        vm.prank(address(ocmeme));
        coin.mintCoin(actor, amt);

        // vote and capture before/after results
        Ocmeme.Vote memory vp = getVotes(pageID, ocmeme);
        vm.prank(actor);
        ocmeme.vote(pageID, amt, false);
        Ocmeme.Vote memory vp2 = getVotes(pageID, ocmeme);

        assertEq(vp2.votes - vp.votes, expectedAmt);
    }
}
