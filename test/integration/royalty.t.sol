// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {stdError} from "forge-std/StdError.sol";
import {fromDaysWadUnsafe} from "solmate/utils/SignedWadMath.sol";

import {Goo} from "../../src/Goo.sol";
import {Ocmeme} from "../../src/Ocmeme.sol";
import {Pages} from "../../src/Pages.sol";
import {Reserve} from "../../src/utils/Reserve.sol";
import {Utilities} from "../utils/Utilities.sol";
import {NFTMeta} from "../../src/libraries/NFTMeta.sol";

contract RoyaltyIntegrationTest is Test {
    Ocmeme ocmeme;
    Goo internal goo;
    Pages internal pages;
    Reserve internal reserve;
    Utilities internal utils;
    address internal user;

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
        user = utils.createUsers(1, vm)[0];

        vm.prank(ocmeme.owner());
        ocmeme.setStart();
    }

    function testValidId(uint16 _royalty, uint64 _salePrice) public {
        uint256 expectedRoyalty = (uint256(_salePrice) * uint256(_royalty)) /
            ocmeme.ROYALTY_DENOMINATOR();

        uint256 price = pages.pagePrice();
        uint256 bal = ocmeme.gooBalance(user);
        if (bal < price) {
            vm.prank(address(ocmeme));
            goo.mintGoo(user, price);
        }

        vm.startPrank(user);
        uint256 pageID = pages.mintFromGoo(price, false);
        ocmeme.submit(pageID, _royalty, NFTMeta.TypeURI(0), "", "");
        vm.stopPrank();

        ocmeme.vaultMint();

        vm.warp(ocmeme.EPOCH_LENGTH() + 2 days);
        ocmeme.crownWinners();

        (address creator, uint256 royalty) = ocmeme.royaltyInfo(1, uint256(_salePrice));
        assertEq(creator, user);
        assertEq(royalty, expectedRoyalty);
    }
}
