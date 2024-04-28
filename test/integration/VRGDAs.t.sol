// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Vm} from "forge-std/Vm.sol";
import {Test} from "forge-std/Test.sol";
import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";
import {toDaysWadUnsafe} from "solmate/utils/SignedWadMath.sol";
import {Goo} from "../../src/Goo.sol";
import {Ocmeme} from "../../src/Ocmeme.sol";
import {Pages} from "../../src/Pages.sol";
import {Reserve} from "../../src/utils/Reserve.sol";
import {NFTMeta} from "../../src/libraries/NFTMeta.sol";
import {Utilities} from "../utils/Utilities.sol";

contract VRGDATest is DSTestPlus {
    Vm internal immutable vm = Vm(HEVM_ADDRESS);
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

    function testNoOverflowForMostOcmeme(uint256 timeSinceStart, uint256 sold) public {
        ocmeme.getVRGDAPrice(
            toDaysWadUnsafe(bound(timeSinceStart, 0 days, ONE_THOUSAND_YEARS)),
            bound(sold, 0, 9000)
        );
    }

    function testNoOverflowForAllOcmeme(uint256 timeSinceStart, uint256 sold) public {
        ocmeme.getVRGDAPrice(
            toDaysWadUnsafe(bound(timeSinceStart, 120 days, ONE_THOUSAND_YEARS)),
            bound(sold, 0, 9999)
        );
    }

    function testOcmemePriceStrictlyIncreasesForMostOcmeme() public {
        uint256 sold;
        uint256 prev;

        while (sold < 9000) {
            uint256 price = ocmeme.getVRGDAPrice(0 days, sold++);
            assertGt(price, prev);
            prev = price;
        }
    }

    /// @notice Test that the pricing switch does now significantly slow down or speed up the issuance of ocmemes.
    function testSwitchSmoothness() public {
        uint256 switchMemeSaleTime = uint256(
            ocmeme.getTargetSaleTime(9995e18) - ocmeme.getTargetSaleTime(9994e18)
        );

        assertRelApproxEq(
            uint256(ocmeme.getTargetSaleTime(9994e18) - ocmeme.getTargetSaleTime(9993e18)),
            switchMemeSaleTime,
            0.025e18
        );

        assertRelApproxEq(
            switchMemeSaleTime,
            uint256(ocmeme.getTargetSaleTime(9996e18) - ocmeme.getTargetSaleTime(9995e18)),
            0.025e18
        );
    }

    /// @notice Test that ocmeme pricing matches expected behavior before switch.
    function testMemePricingPricingBeforeSwitch() public {
        // Expected sales rate according to mathematical formula.
        uint256 timeDelta = 60 days;
        uint256 numMint = 3572;

        vm.warp(block.timestamp + timeDelta);

        uint256 targetPrice = uint256(ocmeme.targetPrice());

        for (uint256 i = 0; i < numMint; ++i) {
            uint256 price = ocmeme.getPrice();
            vm.deal(actor, price);
            vm.prank(actor);
            ocmeme.mint{value: price}();
        }

        uint256 finalPrice = ocmeme.getPrice();

        // If selling at target rate, final price should equal starting price.
        assertRelApproxEq(targetPrice, finalPrice, 0.01e18);
    }

    /// @notice Test that page pricing matches expected behavior after switch.
    function testMemePricingPricingAfterSwitch() public {
        uint256 timeDelta = 360 days;
        uint256 numMint = 9479;

        vm.warp(block.timestamp + timeDelta);

        uint256 targetPrice = uint256(ocmeme.targetPrice());

        for (uint256 i = 0; i < numMint; ++i) {
            uint256 price = ocmeme.getPrice();
            vm.deal(actor, price);
            vm.prank(actor);
            ocmeme.mint{value: price}();
        }

        uint256 finalPrice = ocmeme.getPrice();

        // If selling at target rate, final price should equal starting price.
        assertRelApproxEq(finalPrice, targetPrice, 0.02e18);
    }

    function testNoOverflowForFirstXPages(uint256 timeSinceStart, uint256 sold) public {
        pages.getVRGDAPrice(
            toDaysWadUnsafe(bound(timeSinceStart, 0 days, ONE_THOUSAND_YEARS)),
            bound(sold, 0, 10000)
        );
    }

    function testPagePriceStrictlyIncreases() public {
        uint256 sold;
        uint256 prev;

        while (sold < 10000) {
            uint256 price = pages.getVRGDAPrice(0 days, sold++);
            assertGt(price, prev);
            prev = price;
        }
    }
}
