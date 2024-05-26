// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2 as console} from "forge-std/console2.sol";
import {stdError} from "forge-std/StdError.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";

import {Coin} from "../../src/Coin.sol";
import {Larena} from "../../src/Larena.sol";
import {Pages} from "../../src/Pages.sol";
import {Reserve} from "../../src/utils/Reserve.sol";
import {NFTMeta} from "../../src/libraries/NFTMeta.sol";
import {Utilities} from "../utils/Utilities.sol";
import {MemoryPlus} from "../utils/Memory.sol";
import {GasHelpers} from "../utils/GasHelper.t.sol";
import {Interfaces} from "../utils/Interfaces.sol";
import {Unrevealed} from "../../src/utils/Unrevealed.sol";

contract WinnersIntegrationTest is Test, GasHelpers, MemoryPlus, Interfaces {
    Larena larena;
    Coin internal coin;
    Pages internal pages;
    Reserve internal reserve;
    Unrevealed internal unrevealed;
    Utilities internal utils;
    address actor;
    address[] actors;

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
        actors = utils.createUsers(10, vm);

        vm.warp(block.timestamp + 1 days);
        vm.prank(larena.owner());
        larena.setStart();
    }

    function testInitialepoch() public {
        vm.expectRevert(stdError.indexOOBError);
        larena.crownWinners();
    }

    function testClaim() public brutalizeMemory {
        (uint256 epochID, ) = larena.currentEpoch();

        // make submissions
        for (uint i; i < 5; i++) {
            // mint page
            uint256 price = pages.pagePrice();
            vm.prank(address(larena));
            coin.mintCoin(actor, price);

            vm.prank(address(actor));
            uint256 pageID = pages.mintFromCoin(price, false);

            // submit
            vm.prank(address(actor));
            larena.submit(pageID, 0, NFTMeta.TypeURI(0), "", "");
        }

        // mint larena
        for (uint256 i; i < 100; i++) {
            uint256 mprice = larena.getPrice();
            vm.deal(actor, mprice);
            vm.prank(address(actor));
            larena.mint{value: mprice}();
        }

        // warp past epoch
        vm.warp(block.timestamp + larena.EPOCH_LENGTH());
        larena.crownWinners();

        Larena.Epoch memory e = getEpochs(epochID, larena);

        uint256 a = FixedPointMathLib.mulDiv(
            e.proceeds,
            larena.GOLD_SHARE(),
            larena.PAYOUT_DENOMINATOR()
        );
        uint256 b = FixedPointMathLib.mulDiv(
            e.proceeds,
            larena.SILVER_SHARE(),
            larena.PAYOUT_DENOMINATOR()
        );
        uint256 c = FixedPointMathLib.mulDiv(
            e.proceeds,
            larena.BRONZE_SHARE(),
            larena.PAYOUT_DENOMINATOR()
        );
        uint256 d = e.proceeds -
            (FixedPointMathLib.mulDiv(
                e.proceeds,
                larena.GOLD_SHARE(),
                larena.PAYOUT_DENOMINATOR()
            ) +
                FixedPointMathLib.mulDiv(
                    e.proceeds,
                    larena.SILVER_SHARE(),
                    larena.PAYOUT_DENOMINATOR()
                ) +
                FixedPointMathLib.mulDiv(
                    e.proceeds,
                    larena.BRONZE_SHARE(),
                    larena.PAYOUT_DENOMINATOR()
                ));

        vm.startPrank(actor);
        uint256 bal = address(actor).balance;
        larena.claim(epochID, Larena.ClaimType.GOLD);
        assertEq(bal + a, address(actor).balance);

        bal = address(actor).balance;
        larena.claim(epochID, Larena.ClaimType.SILVER);
        assertEq(bal + b, address(actor).balance);

        bal = address(actor).balance;
        larena.claim(epochID, Larena.ClaimType.BRONZE);
        assertEq(bal + c, address(actor).balance);

        bal = address(reserve).balance;
        larena.vaultClaim(epochID);
        assertEq(bal + d, address(reserve).balance);
        vm.stopPrank();
    }

    function testDupClaim() public brutalizeMemory {
        (uint256 epochID, ) = larena.currentEpoch();

        // make submissions
        for (uint i; i < 5; i++) {
            // mint page
            uint256 price = pages.pagePrice();
            vm.prank(address(larena));
            coin.mintCoin(actor, price);

            vm.prank(address(actor));
            uint256 pageID = pages.mintFromCoin(price, false);

            // submit
            vm.prank(address(actor));
            larena.submit(pageID, 0, NFTMeta.TypeURI(0), "", "");
        }

        // mint larena
        for (uint256 i; i < 100; i++) {
            uint256 mprice = larena.getPrice();
            vm.deal(actor, mprice);
            vm.prank(address(actor));
            larena.mint{value: mprice}();
        }

        // warp past epoch
        vm.warp(block.timestamp + larena.EPOCH_LENGTH());
        larena.crownWinners();

        vm.startPrank(actor);
        larena.claim(epochID, Larena.ClaimType.GOLD);
        vm.expectRevert(Larena.DuplicateClaim.selector);
        larena.claim(epochID, Larena.ClaimType.GOLD);

        larena.claim(epochID, Larena.ClaimType.SILVER);
        vm.expectRevert(Larena.DuplicateClaim.selector);
        larena.claim(epochID, Larena.ClaimType.SILVER);

        larena.claim(epochID, Larena.ClaimType.BRONZE);
        vm.expectRevert(Larena.DuplicateClaim.selector);
        larena.claim(epochID, Larena.ClaimType.BRONZE);

        larena.vaultClaim(epochID);
        vm.expectRevert(Larena.DuplicateClaim.selector);
        larena.vaultClaim(epochID);

        vm.stopPrank();
    }

    function testCrownWinnerMaxGas() public {
        uint256 max = larena.MAX_SUBMISSIONS();
        for (uint256 i; i < max; i++) {
            address act = actors[i % actors.length];
            uint256 price = pages.pagePrice();

            vm.prank(address(larena));
            coin.mintCoin(act, price + i);

            vm.startPrank(address(act));
            uint256 pageID = pages.mintFromCoin(price, false);
            larena.submit(pageID, 1, NFTMeta.TypeURI(0), "", "");

            larena.vote(pageID, i, false);
            vm.stopPrank();
        }

        vm.warp(block.timestamp + larena.EPOCH_LENGTH());

        startMeasuringGas("x");
        larena.crownWinners();
        uint256 gas = stopMeasuringGas();
        console.log(gas);
    }
}
