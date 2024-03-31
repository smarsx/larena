// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {stdError} from "forge-std/StdError.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";

import {Goo} from "../../src/Goo.sol";
import {Ocmeme} from "../../src/Ocmeme.sol";
import {Pages} from "../../src/Pages.sol";
import {Reserve} from "../../src/utils/Reserve.sol";
import {NFTMeta} from "../../src/libraries/NFTMeta.sol";
import {Utilities} from "../utils/Utilities.sol";

contract WinnersIntegrationTest is Test {
    Ocmeme ocmeme;
    Goo internal goo;
    Pages internal pages;
    Reserve internal reserve;
    Utilities internal utils;
    address actor;

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
    }

    function testInitialepoch() public {
        vm.expectRevert(stdError.indexOOBError);
        ocmeme.crownWinners();
    }

    function testClaim() public {
        (uint256 epochID, ) = ocmeme.currentEpoch();

        // make submissions
        for (uint i; i < 5; i++) {
            // mint page
            uint256 price = pages.pagePrice();
            vm.prank(address(ocmeme));
            goo.mintGoo(actor, price);

            vm.prank(address(actor));
            uint256 pageID = pages.mintFromGoo(price, false);

            // submit
            vm.prank(address(actor));
            ocmeme.submit(pageID, 0, NFTMeta.TypeURI(0), "", "");
        }

        // mint ocmeme
        for (uint256 i; i < 100; i++) {
            uint256 mprice = ocmeme.getPrice();
            vm.deal(actor, mprice);
            vm.prank(address(actor));
            ocmeme.mint{value: mprice}();
        }

        // warp past epoch
        vm.warp(block.timestamp + ocmeme.EPOCH_LENGTH());
        ocmeme.crownWinners();

        Ocmeme.Epoch memory e = ocmeme.epochs(epochID);

        uint256 a = FixedPointMathLib.mulDiv(
            e.proceeds,
            ocmeme.GOLD_SHARE(),
            ocmeme.PAYOUT_DENOMINATOR()
        );
        uint256 b = FixedPointMathLib.mulDiv(
            e.proceeds,
            ocmeme.SILVER_SHARE(),
            ocmeme.PAYOUT_DENOMINATOR()
        );
        uint256 c = FixedPointMathLib.mulDiv(
            e.proceeds,
            ocmeme.BRONZE_SHARE(),
            ocmeme.PAYOUT_DENOMINATOR()
        );
        uint256 d = e.proceeds -
            (FixedPointMathLib.mulDiv(
                e.proceeds,
                ocmeme.GOLD_SHARE(),
                ocmeme.PAYOUT_DENOMINATOR()
            ) +
                FixedPointMathLib.mulDiv(
                    e.proceeds,
                    ocmeme.SILVER_SHARE(),
                    ocmeme.PAYOUT_DENOMINATOR()
                ) +
                FixedPointMathLib.mulDiv(
                    e.proceeds,
                    ocmeme.BRONZE_SHARE(),
                    ocmeme.PAYOUT_DENOMINATOR()
                ));

        vm.startPrank(actor);
        uint256 bal = address(actor).balance;
        ocmeme.claimGold(epochID);
        assertEq(bal + a, address(actor).balance);

        bal = address(actor).balance;
        ocmeme.claimSilver(epochID);
        assertEq(bal + b, address(actor).balance);

        bal = address(actor).balance;
        ocmeme.claimBronze(epochID);
        assertEq(bal + c, address(actor).balance);

        bal = address(reserve).balance;
        ocmeme.claimVault(epochID);
        assertEq(bal + d, address(reserve).balance);
        vm.stopPrank();
    }

    function testDupClaim() public {
        (uint256 epochID, ) = ocmeme.currentEpoch();

        // make submissions
        for (uint i; i < 5; i++) {
            // mint page
            uint256 price = pages.pagePrice();
            vm.prank(address(ocmeme));
            goo.mintGoo(actor, price);

            vm.prank(address(actor));
            uint256 pageID = pages.mintFromGoo(price, false);

            // submit
            vm.prank(address(actor));
            ocmeme.submit(pageID, 0, NFTMeta.TypeURI(0), "", "");
        }

        // mint ocmeme
        for (uint256 i; i < 100; i++) {
            uint256 mprice = ocmeme.getPrice();
            vm.deal(actor, mprice);
            vm.prank(address(actor));
            ocmeme.mint{value: mprice}();
        }

        // warp past epoch
        vm.warp(block.timestamp + ocmeme.EPOCH_LENGTH());
        ocmeme.crownWinners();

        vm.startPrank(actor);
        ocmeme.claimGold(epochID);
        vm.expectRevert(Ocmeme.DuplicateClaim.selector);
        ocmeme.claimGold(epochID);

        ocmeme.claimSilver(epochID);
        vm.expectRevert(Ocmeme.DuplicateClaim.selector);
        ocmeme.claimSilver(epochID);

        ocmeme.claimBronze(epochID);
        vm.expectRevert(Ocmeme.DuplicateClaim.selector);
        ocmeme.claimBronze(epochID);

        ocmeme.claimVault(epochID);
        vm.expectRevert(Ocmeme.DuplicateClaim.selector);
        ocmeme.claimVault(epochID);

        vm.stopPrank();
    }
}
