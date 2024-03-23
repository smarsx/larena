// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {toDaysWadUnsafe} from "solmate/utils/SignedWadMath.sol";

import {Goo} from "../../src/Goo.sol";
import {Ocmeme} from "../../src/Ocmeme.sol";
import {Pages} from "../../src/Pages.sol";
import {Reserve} from "../../src/utils/Reserve.sol";
import {NFTMeta} from "../../src/libraries/NFTMeta.sol";
import {Utilities} from "../utils/Utilities.sol";

contract VRGDATest is Test {
    uint256 constant ONE_THOUSAND_YEARS = 356 days * 1000;

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

    function testNoOverflowForMostOcmeme(uint256 timeSinceStart, uint256 sold) public view {
        ocmeme.getVRGDAPrice(
            toDaysWadUnsafe(bound(timeSinceStart, 0 days, ONE_THOUSAND_YEARS)),
            bound(sold, 0, 381)
        );
    }

    function testNoOverflowForAllOcmeme(uint256 timeSinceStart, uint256 sold) public view {
        ocmeme.getVRGDAPrice(
            toDaysWadUnsafe(bound(timeSinceStart, 120 days, ONE_THOUSAND_YEARS)),
            bound(sold, 0, 499)
        );
    }

    function testFailOverflowForBeyondLimitOcmeme(
        uint256 timeSinceStart,
        uint256 sold
    ) public view {
        ocmeme.getVRGDAPrice(
            toDaysWadUnsafe(bound(timeSinceStart, 0 days, ONE_THOUSAND_YEARS)),
            bound(sold, 500, type(uint128).max)
        );
    }

    function testOcmemePriceStrictlyIncreasesForMostOcmeme() public view {
        uint256 sold;
        uint256 prev;

        while (sold < 381) {
            uint256 price = ocmeme.getVRGDAPrice(0 days, sold++);
            assertGt(price, prev);
            prev = price;
        }
    }

    function testNoOverflowForFirstXPages(uint256 timeSinceStart, uint256 sold) public view {
        pages.getVRGDAPrice(
            toDaysWadUnsafe(bound(timeSinceStart, 0 days, ONE_THOUSAND_YEARS)),
            bound(sold, 0, 500)
        );
    }

    function testPagePriceStrictlyIncreases() public view {
        uint256 sold;
        uint256 prev;

        while (sold < 500) {
            uint256 price = pages.getVRGDAPrice(0 days, sold++);
            assertGt(price, prev);
            prev = price;
        }
    }
}
