// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Vm} from "forge-std/Vm.sol";
import {Test} from "forge-std/Test.sol";
import {console2 as console} from "forge-std/console2.sol";
import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";
import {toDaysWadUnsafe} from "solmate/utils/SignedWadMath.sol";
import {Coin} from "../../src/Coin.sol";
import {Ocmeme} from "../../src/Ocmeme.sol";
import {Pages} from "../../src/Pages.sol";
import {Reserve} from "../../src/utils/Reserve.sol";
import {NFTMeta} from "../../src/libraries/NFTMeta.sol";
import {Utilities} from "../utils/Utilities.sol";

contract VRGDATest is DSTestPlus {
    Vm internal immutable vm = Vm(HEVM_ADDRESS);
    uint256 constant ONE_HUNDRED_YEARS = 356 days * 100;
    uint256 constant FIVE_YEARS = 356 days * 5;
    Ocmeme ocmeme;
    Coin internal coin;
    Pages internal pages;
    Reserve internal reserve;
    Utilities internal utils;
    address actor;

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
    }

    function testNoOverflowForMostOcmeme(uint256 timeSinceStart, uint256 sold) public {
        ocmeme.getVRGDAPrice(
            toDaysWadUnsafe(bound(timeSinceStart, 0 days, ONE_HUNDRED_YEARS)),
            bound(sold, 0, 1000)
        );
    }

    function testNoOverflowForAllOcmeme(uint256 timeSinceStart, uint256 sold) public {
        ocmeme.getVRGDAPrice(
            toDaysWadUnsafe(bound(timeSinceStart, FIVE_YEARS, ONE_HUNDRED_YEARS)),
            bound(sold, 0, 10000)
        );
    }

    function testOcmemePriceStrictlyIncreasesForMostOcmeme() public {
        uint256 sold;
        uint256 prev;

        while (sold < 5000) {
            uint256 price = ocmeme.getVRGDAPrice(0 days, sold++);
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
