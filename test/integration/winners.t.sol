// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2 as console} from "forge-std/console2.sol";
import {stdError} from "forge-std/StdError.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";

import {Coin} from "../../src/Coin.sol";
import {Ocmeme} from "../../src/Ocmeme.sol";
import {Pages} from "../../src/Pages.sol";
import {Reserve} from "../../src/utils/Reserve.sol";
import {NFTMeta} from "../../src/libraries/NFTMeta.sol";
import {Utilities} from "../utils/Utilities.sol";
import {MemoryPlus} from "../utils/Memory.sol";
import {GasHelpers} from "../utils/GasHelper.t.sol";
import {Interfaces} from "../utils/Interfaces.sol";

contract WinnersIntegrationTest is Test, GasHelpers, MemoryPlus, Interfaces {
    Ocmeme ocmeme;
    Coin internal coin;
    Pages internal pages;
    Reserve internal reserve;
    Utilities internal utils;
    address actor;
    address[] actors;

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
        actors = utils.createUsers(10, vm);

        vm.warp(block.timestamp + 1 days);
        vm.prank(ocmeme.owner());
        ocmeme.setStart();
    }

    function testInitialepoch() public {
        vm.expectRevert(stdError.indexOOBError);
        ocmeme.crownWinners();
    }

    function testClaim() public brutalizeMemory {
        (uint256 epochID, ) = ocmeme.currentEpoch();

        // make submissions
        for (uint i; i < 5; i++) {
            // mint page
            uint256 price = pages.pagePrice();
            vm.prank(address(ocmeme));
            coin.mintCoin(actor, price);

            vm.prank(address(actor));
            uint256 pageID = pages.mintFromCoin(price, false);

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

        Ocmeme.Epoch memory e = getEpochs(epochID, ocmeme);

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

    function testDupClaim() public brutalizeMemory {
        (uint256 epochID, ) = ocmeme.currentEpoch();

        // make submissions
        for (uint i; i < 5; i++) {
            // mint page
            uint256 price = pages.pagePrice();
            vm.prank(address(ocmeme));
            coin.mintCoin(actor, price);

            vm.prank(address(actor));
            uint256 pageID = pages.mintFromCoin(price, false);

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

    function testCrownWinnerMaxGas() public {
        uint256 max = ocmeme.MAX_SUBMISSIONS();
        for (uint256 i; i < max; i++) {
            address act = actors[i % actors.length];
            uint256 price = pages.pagePrice();

            vm.prank(address(ocmeme));
            coin.mintCoin(act, price + i);

            vm.startPrank(address(act));
            uint256 pageID = pages.mintFromCoin(price, false);
            ocmeme.submit(pageID, 1, NFTMeta.TypeURI(0), "", "");

            ocmeme.vote(pageID, i, false);
            vm.stopPrank();
        }

        vm.warp(block.timestamp + ocmeme.EPOCH_LENGTH());

        startMeasuringGas("x");
        ocmeme.crownWinners();
        uint256 gas = stopMeasuringGas();
        console.log(gas);
    }
}
