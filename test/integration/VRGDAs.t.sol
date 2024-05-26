// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Vm} from "forge-std/Vm.sol";
import {Test} from "forge-std/Test.sol";
import {console2 as console} from "forge-std/console2.sol";
import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";
import {toDaysWadUnsafe} from "solmate/utils/SignedWadMath.sol";
import {Coin} from "../../src/Coin.sol";
import {Larena} from "../../src/Larena.sol";
import {Pages} from "../../src/Pages.sol";
import {Reserve} from "../../src/utils/Reserve.sol";
import {NFTMeta} from "../../src/libraries/NFTMeta.sol";
import {Utilities} from "../utils/Utilities.sol";
import {Unrevealed} from "../../src/utils/Unrevealed.sol";

contract VRGDATest is DSTestPlus {
    Vm internal immutable vm = Vm(HEVM_ADDRESS);
    uint256 constant ONE_HUNDRED_YEARS = 356 days * 100;
    uint256 constant FIVE_YEARS = 356 days * 5;
    Larena larena;
    Coin internal coin;
    Pages internal pages;
    Reserve internal reserve;
    Unrevealed internal unrevealed;
    Utilities internal utils;
    address actor;

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
    }

    function testNoOverflowForMostLarena(uint256 timeSinceStart, uint256 sold) public {
        larena.getVRGDAPrice(
            toDaysWadUnsafe(bound(timeSinceStart, 0 days, ONE_HUNDRED_YEARS)),
            bound(sold, 0, 1000)
        );
    }

    function testNoOverflowForAllLarena(uint256 timeSinceStart, uint256 sold) public {
        larena.getVRGDAPrice(
            toDaysWadUnsafe(bound(timeSinceStart, FIVE_YEARS, ONE_HUNDRED_YEARS)),
            bound(sold, 0, 10000)
        );
    }

    function testLarenaPriceStrictlyIncreasesForMostLarena() public {
        uint256 sold;
        uint256 prev;

        while (sold < 5000) {
            uint256 price = larena.getVRGDAPrice(0 days, sold++);
            assertGt(price, prev);
            prev = price;
        }
    }

    function testNoOverflowForFirstXPages(uint256 timeSinceStart, uint256 sold) public {
        pages.getVRGDAPrice(
            toDaysWadUnsafe(bound(timeSinceStart, 0 days, ONE_HUNDRED_YEARS)),
            bound(sold, 0, 1000)
        );
    }

    function testPagePriceStrictlyIncreases() public {
        uint256 sold;
        uint256 prev;

        while (sold < 1000) {
            uint256 price = pages.getVRGDAPrice(0 days, sold++);
            assertGt(price, prev);
            prev = price;
        }
    }
}
