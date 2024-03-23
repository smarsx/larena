// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {Goo} from "../../src/Goo.sol";
import {Ocmeme} from "../../src/Ocmeme.sol";
import {Pages} from "../../src/Pages.sol";
import {Reserve} from "../../src/utils/Reserve.sol";
import {NFTMeta} from "../../src/libraries/NFTMeta.sol";
import {Utilities} from "../utils/Utilities.sol";

contract SubmitIntegrationTest is Test {
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

    function testMakeSubmission() public {
        uint256 price = pages.pagePrice();
        uint256 bal = ocmeme.gooBalance(actor);
        if (bal < price) {
            vm.prank(address(ocmeme));
            goo.mintGoo(actor, price);
        }
        vm.startPrank(actor);
        uint256 pageID = pages.mintFromGoo(price, false);
        ocmeme.submit(pageID, 1, NFTMeta.TypeURI(0), "", "");
        vm.stopPrank();
    }

    function testSubmissionDelay(uint256 _warp) public {
        _warp = bound(_warp, 1, type(uint48).max);
        vm.warp(_warp);

        uint256 price = pages.pagePrice();
        uint256 bal = ocmeme.gooBalance(actor);
        if (bal < price) {
            vm.prank(address(ocmeme));
            goo.mintGoo(actor, price);
        }
        vm.startPrank(actor);
        uint256 pageID = pages.mintFromGoo(price, false);

        (uint256 eventID, ) = ocmeme.currentEpoch();
        uint256 start = ocmeme.epochStart(eventID);

        if (block.timestamp - start > ocmeme.ACTIVE_PERIOD()) {
            vm.expectRevert(Ocmeme.InvalidTime.selector);
            ocmeme.submit(pageID, 1, NFTMeta.TypeURI(0), "", "");
        } else {
            ocmeme.submit(pageID, 1, NFTMeta.TypeURI(0), "", "");
        }
        vm.stopPrank();
    }

    function testDuplicate() public {
        uint256 price = pages.pagePrice();

        vm.prank(address(ocmeme));
        goo.mintGoo(actor, price);

        vm.startPrank(address(actor));
        uint256 pageID = pages.mintFromGoo(price, false);
        ocmeme.submit(pageID, 1, NFTMeta.TypeURI(0), "", "");

        vm.expectRevert(Pages.Used.selector);
        ocmeme.submit(pageID, 1, NFTMeta.TypeURI(0), "", "");
        vm.stopPrank();
    }
}