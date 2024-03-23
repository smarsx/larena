// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2 as console} from "forge-std/console2.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {Goo} from "../../src/Goo.sol";
import {Ocmeme} from "../../src/Ocmeme.sol";
import {Pages} from "../../src/Pages.sol";
import {Reserve} from "../../src/utils/Reserve.sol";
import {Utilities} from "../utils/Utilities.sol";
import {NFTMeta} from "../../src/libraries/NFTMeta.sol";

contract VoteIntegrationTest is Test {
    Ocmeme ocmeme;
    Goo internal goo;
    Pages internal pages;
    Reserve internal reserve;
    Utilities internal utils;
    address actor;

    uint256 public pageID;

    function setUp() public {
        utils = new Utilities();
        address gooAddress = utils.predictContractAddress(address(this), 1, vm);
        address pagesAddress = utils.predictContractAddress(address(this), 2, vm);
        address ocmemeAddress = utils.predictContractAddress(address(this), 3, vm);
        reserve = new Reserve(
            Ocmeme(ocmemeAddress),
            Pages(pagesAddress),
            Goo(gooAddress),
            address(this)
        );
        goo = new Goo(ocmemeAddress, pagesAddress);
        pages = new Pages(block.timestamp, goo, address(reserve), Ocmeme(ocmemeAddress));
        ocmeme = new Ocmeme(goo, Pages(pagesAddress), address(reserve));
        actor = utils.createUsers(1, vm)[0];

        vm.prank(ocmeme.owner());
        ocmeme.setStart();

        // mint page
        uint256 price = pages.pagePrice();
        vm.prank(address(ocmeme));
        goo.mintGoo(actor, price);

        vm.prank(address(actor));
        pageID = pages.mintFromGoo(price, false);

        // submit
        vm.prank(address(actor));
        ocmeme.submit(pageID, 0, NFTMeta.TypeURI(0), "", "");
    }

    function voteNoDeadzone(uint256 _warp, uint256 _amt) public {
        vm.assume(_warp < ocmeme.EPOCH_LENGTH());
        vm.warp(block.timestamp + _warp);

        Ocmeme.VotePair memory vp = ocmeme.votes(pageID);

        vm.prank(address(ocmeme));
        goo.mintGoo(actor, _amt);

        vm.prank(actor);
        ocmeme.vote(pageID, _amt, false);

        Ocmeme.VotePair memory vp2 = ocmeme.votes(pageID);

        assertEq(vp.votes + _amt, vp2.votes);
    }

    function voteMaybeDeadzone(uint256 _warp, uint256 _amt) public {
        vm.assume(_warp < ocmeme.EPOCH_LENGTH());
        vm.assume(_amt > 3);
        vm.warp(block.timestamp + _warp);

        (, uint256 start) = ocmeme.currentEpoch();
        bool isdz = block.timestamp - start > ocmeme.ACTIVE_PERIOD();

        // doesn't matter when this is called.
        // as long as it's post submission
        ocmeme.setVoteDeadzone();

        Ocmeme.VotePair memory vp = ocmeme.votes(pageID);

        vm.prank(address(ocmeme));
        goo.mintGoo(actor, _amt);

        vm.prank(actor);
        ocmeme.vote(pageID, _amt, false);

        Ocmeme.VotePair memory vp2 = ocmeme.votes(pageID);

        if (isdz) {
            assertTrue(vp.votes + _amt > vp2.votes);
        } else {
            assertEq(vp.votes + _amt, vp2.votes);
        }
    }

    function voteDeadzone() public {
        // doesn't matter when this is called.
        // as long as it's post-submission
        ocmeme.setVoteDeadzone();

        (, uint256 start) = ocmeme.currentEpoch();
        vm.warp(start + ocmeme.ACTIVE_PERIOD() + 1 hours);

        vm.prank(address(ocmeme));
        goo.mintGoo(actor, 100 ether);

        uint256[] memory diffs = new uint256[](5);
        for (uint i; i < 5; i++) {
            vm.warp(block.timestamp + (i * 6 * 1 hours));

            Ocmeme.VotePair memory vp = ocmeme.votes(pageID);
            vm.prank(actor);
            ocmeme.vote(pageID, 1 ether, false);
            Ocmeme.VotePair memory vp2 = ocmeme.votes(pageID);

            diffs[i] = (vp2.votes - vp.votes);
        }

        assertTrue(diffs[0] < diffs[1]);
        assertTrue(diffs[1] < diffs[2]);
        assertTrue(diffs[2] < diffs[3]);
        assertTrue(diffs[3] < diffs[4]);
    }
}