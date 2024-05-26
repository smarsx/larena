// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2 as console} from "forge-std/console2.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {Coin} from "../../src/Coin.sol";
import {Larena} from "../../src/Larena.sol";
import {Pages} from "../../src/Pages.sol";
import {Reserve} from "../../src/utils/Reserve.sol";
import {Utilities} from "../utils/Utilities.sol";
import {NFTMeta} from "../../src/libraries/NFTMeta.sol";
import {MemoryPlus} from "../utils/Memory.sol";
import {Interfaces} from "../utils/Interfaces.sol";
import {Unrevealed} from "../../src/utils/Unrevealed.sol";

contract VoteIntegrationTest is Test, MemoryPlus, Interfaces {
    Larena larena;
    Coin internal coin;
    Pages internal pages;
    Reserve internal reserve;
    Unrevealed internal unrevealed;
    Utilities internal utils;
    address actor;

    uint256 public pageID;

    function setUp() public {
        utils = new Utilities();
        address coinAddress = utils.predictContractAddress(address(this), 2, vm);
        address pagesAddress = utils.predictContractAddress(address(this), 3, vm);
        address larenaAddress = utils.predictContractAddress(address(this), 4, vm);
        reserve = new Reserve(
            Larena(larenaAddress),
            Pages(pagesAddress),
            Coin(coinAddress),
            address(this)
        );
        unrevealed = new Unrevealed();
        coin = new Coin(larenaAddress, pagesAddress);
        pages = new Pages(block.timestamp, coin, address(reserve), Larena(larenaAddress));
        larena = new Larena(coin, Pages(pagesAddress), unrevealed, address(reserve));
        actor = utils.createUsers(1, vm)[0];

        vm.prank(larena.owner());
        larena.setStart();

        // mint page
        uint256 price = pages.pagePrice();
        vm.prank(address(larena));
        coin.mintCoin(actor, price);

        vm.prank(address(actor));
        pageID = pages.mintFromCoin(price, false);

        // submit
        vm.prank(address(actor));
        larena.submit(pageID, 0, NFTMeta.TypeURI(0), "", "");
    }

    function testNoDeadzone(uint256 _warp, uint200 _amt) public {
        vm.assume(_warp < larena.DECAY_ZONE());
        vm.warp(block.timestamp + _warp);

        // mint too to be used in vote.
        vm.prank(address(larena));
        coin.mintCoin(actor, _amt);

        // vote and capture before/after.
        Larena.Vote memory vp = getVotes(pageID, larena);
        vm.prank(actor);
        larena.vote(pageID, _amt, false);
        Larena.Vote memory vp2 = getVotes(pageID, larena);

        // when no deadzone, vote utilization = 100%
        assertEq(vp.votes + _amt, vp2.votes);
    }

    function testMaybeDeadzone(uint256 _warp, uint200 _amt) public {
        vm.assume(_warp < larena.EPOCH_LENGTH());
        vm.assume(_amt > 3);
        vm.warp(block.timestamp + _warp);

        (, uint256 start) = larena.currentEpoch();
        bool isdz = block.timestamp - start > larena.DECAY_ZONE();

        Larena.Vote memory vp = getVotes(pageID, larena);

        vm.prank(address(larena));
        coin.mintCoin(actor, _amt);

        vm.prank(actor);
        larena.vote(pageID, _amt, false);

        Larena.Vote memory vp2 = getVotes(pageID, larena);

        if (isdz) {
            assertTrue(vp.votes + _amt > vp2.votes);
        } else {
            assertEq(vp.votes + _amt, vp2.votes);
        }
    }

    function testDeadzone() public brutalizeMemory {
        (, uint256 start) = larena.currentEpoch();
        vm.warp(start + larena.DECAY_ZONE() + 1 hours);

        vm.prank(address(larena));
        coin.mintCoin(actor, 100 ether);

        uint256[] memory diffs = new uint256[](5);
        for (uint i; i < 5; i++) {
            vm.warp(block.timestamp + 2 hours);

            Larena.Vote memory vp = getVotes(pageID, larena);
            vm.prank(actor);
            larena.vote(pageID, 1 ether, false);
            Larena.Vote memory vp2 = getVotes(pageID, larena);

            diffs[i] = (vp2.votes - vp.votes);
        }

        assertTrue(diffs[0] > diffs[1]);
        assertTrue(diffs[1] > diffs[2]);
        assertTrue(diffs[2] > diffs[3]);
        assertTrue(diffs[3] > diffs[4]);
    }

    function testDeadzone2(uint256 _warp, uint200 _amt) public brutalizeMemory {
        _warp = bound(_warp, 1, 100 * larena.EPOCH_LENGTH());
        _amt = uint200(bound(_amt, 1e18, type(uint200).max));
        vm.warp(_warp);

        (, uint256 start) = larena.currentEpoch();

        // mint page
        uint256 price = pages.pagePrice();
        vm.prank(address(larena));
        coin.mintCoin(actor, price);

        vm.prank(address(actor));
        uint256 mypage = pages.mintFromCoin(price, false);

        // submit, reverse time if submission deadzone. need to submit to vote.
        while (block.timestamp > start + larena.SUBMISSION_DEADLINE()) {
            vm.warp(block.timestamp - 1 days);
        }
        vm.prank(address(actor));
        larena.submit(mypage, 0, NFTMeta.TypeURI(0), "", "");

        // mint _amt to be voted with
        vm.prank(address(larena));
        coin.mintCoin(actor, _amt);

        // vote and capture before/after results
        Larena.Vote memory vp = getVotes(mypage, larena);
        vm.prank(actor);
        larena.vote(mypage, _amt, false);
        Larena.Vote memory vp2 = getVotes(mypage, larena);

        if (block.timestamp > start + larena.DECAY_ZONE()) {
            assertTrue(vp2.votes - vp.votes < _amt);
        } else {
            assertEq(vp2.votes - vp.votes, _amt);
        }
    }

    function testMaxDecay() public {
        uint256 amt = 100 ether;
        uint256 expectedAmt = amt / 10;
        (, uint256 start) = larena.currentEpoch();
        vm.warp(start + larena.EPOCH_LENGTH() - 1000);

        // mint _amt to be voted with
        vm.prank(address(larena));
        coin.mintCoin(actor, amt);

        // vote and capture before/after results
        Larena.Vote memory vp = getVotes(pageID, larena);
        vm.prank(actor);
        larena.vote(pageID, amt, false);
        Larena.Vote memory vp2 = getVotes(pageID, larena);

        assertEq(vp2.votes - vp.votes, expectedAmt);
    }

    function testMinDecay() public {
        uint256 amt = 1000 ether;
        uint256 expectedAmt = 963 ether;
        (, uint256 start) = larena.currentEpoch();
        vm.warp(start + larena.DECAY_ZONE() + 1);

        // mint _amt to be voted with
        vm.prank(address(larena));
        coin.mintCoin(actor, amt);

        // vote and capture before/after results
        Larena.Vote memory vp = getVotes(pageID, larena);
        vm.prank(actor);
        larena.vote(pageID, amt, false);
        Larena.Vote memory vp2 = getVotes(pageID, larena);

        assertEq(vp2.votes - vp.votes, expectedAmt);
    }
}
