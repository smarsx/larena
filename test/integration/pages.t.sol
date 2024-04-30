// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {stdError} from "forge-std/StdError.sol";
import {fromDaysWadUnsafe} from "solmate/utils/SignedWadMath.sol";

import {Coin} from "../../src/Coin.sol";
import {Ocmeme} from "../../src/Ocmeme.sol";
import {Pages} from "../../src/Pages.sol";
import {Reserve} from "../../src/utils/Reserve.sol";
import {Utilities} from "../utils/Utilities.sol";

contract PagesIntegrationTest is Test {
    Ocmeme ocmeme;
    Coin internal coin;
    Pages internal pages;
    Utilities internal utils;
    address internal user;
    address payable[] internal users;

    address internal vault = address(0xBEEF);

    error InsufficientBalance();

    function setUp() public {
        // Avoid starting at timestamp at 0 for ease of testing.
        vm.warp(block.timestamp + 1);

        utils = new Utilities();
        users = utils.createUsers(5, vm);

        coin = new Coin(
            // Ocmeme:
            address(this),
            // Pages:
            utils.predictContractAddress(address(this), 1, vm)
        );

        pages = new Pages(block.timestamp, coin, address(vault), Ocmeme(address(this)));

        user = users[0];
    }

    function testMintBeforeSetMint() public {
        vm.expectRevert(InsufficientBalance.selector);
        vm.prank(user);
        pages.mintFromCoin(type(uint256).max, false);
    }

    function testMintBeforeStart() public {
        vm.warp(block.timestamp - 1);

        vm.expectRevert(stdError.arithmeticError);
        vm.prank(user);
        pages.mintFromCoin(type(uint256).max, false);
    }

    function testRegularMint() public {
        coin.mintCoin(user, pages.pagePrice());
        vm.prank(user);
        pages.mintFromCoin(type(uint256).max, false);
        assertEq(user, pages.ownerOf(1));
    }

    function testTargetPrice() public {
        // Warp to the target sale time so that the page price equals the target price.
        vm.warp(block.timestamp + fromDaysWadUnsafe(pages.getTargetSaleTime(1e18)));

        uint256 cost = pages.pagePrice();
        assertApproxEqRel(cost, uint256(pages.targetPrice()), 0.00001e18);
    }

    function testMintVaultPagesFailsWithNoMints() public {
        vm.expectRevert(Pages.ReserveImbalance.selector);
        pages.mintVaultPages(1);
    }

    function testCanMintVault() public {
        mintPageToAddress(user, 9);

        pages.mintVaultPages(1);
        assertEq(pages.ownerOf(10), address(vault));
    }

    function testCanMintMultipleVault() public {
        mintPageToAddress(user, 90);

        pages.mintVaultPages(10);
        assertEq(pages.ownerOf(91), address(vault));
        assertEq(pages.ownerOf(92), address(vault));
        assertEq(pages.ownerOf(93), address(vault));
        assertEq(pages.ownerOf(94), address(vault));
        assertEq(pages.ownerOf(95), address(vault));
        assertEq(pages.ownerOf(96), address(vault));
        assertEq(pages.ownerOf(97), address(vault));
        assertEq(pages.ownerOf(98), address(vault));
        assertEq(pages.ownerOf(99), address(vault));
        assertEq(pages.ownerOf(100), address(vault));

        assertEq(pages.numMintedForVault(), 10);
        assertEq(pages.currentId(), 100);

        // Ensure id doesn't get messed up.
        mintPageToAddress(user, 1);
        assertEq(pages.ownerOf(101), user);
        assertEq(pages.currentId(), 101);
    }

    function testCantMintTooFastVault() public {
        mintPageToAddress(user, 18);

        vm.expectRevert(Pages.ReserveImbalance.selector);
        pages.mintVaultPages(3);
    }

    function testCantMintTooFastVaultOneByOne() public {
        mintPageToAddress(user, 90);

        pages.mintVaultPages(1);
        pages.mintVaultPages(1);
        pages.mintVaultPages(1);
        pages.mintVaultPages(1);
        pages.mintVaultPages(1);
        pages.mintVaultPages(1);
        pages.mintVaultPages(1);
        pages.mintVaultPages(1);
        pages.mintVaultPages(1);
        pages.mintVaultPages(1);

        vm.expectRevert(Pages.ReserveImbalance.selector);
        pages.mintVaultPages(1);
    }

    function testInsufficientBalance() public {
        vm.prank(user);
        vm.expectRevert(InsufficientBalance.selector);
        pages.mintFromCoin(type(uint256).max, false);
    }

    function testMintPriceExceededMax() public {
        uint256 cost = pages.pagePrice();
        coin.mintCoin(user, cost);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Pages.PriceExceededMax.selector, cost));
        pages.mintFromCoin(cost - 1, false);
    }

    function mintPageToAddress(address addr, uint256 num) internal {
        for (uint256 i = 0; i < num; ++i) {
            coin.mintCoin(addr, pages.pagePrice());

            vm.prank(addr);
            pages.mintFromCoin(type(uint256).max, false);
        }
    }

    function testOwnerRevertsOnZero() public {
        vm.expectRevert("NOT_MINTED");
        pages.ownerOf(0);
    }

    function testOwnerRevertsOnZero2() public {
        mintPageToAddress(user, 10);
        vm.expectRevert("NOT_MINTED");
        pages.ownerOf(0);
    }
}
