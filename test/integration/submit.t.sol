// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {Coin} from "../../src/Coin.sol";
import {Larena} from "../../src/Larena.sol";
import {Pages} from "../../src/Pages.sol";
import {Reserve} from "../../src/utils/Reserve.sol";
import {NFTMeta} from "../../src/libraries/NFTMeta.sol";
import {Utilities} from "../utils/Utilities.sol";
import {Unrevealed} from "../../src/utils/Unrevealed.sol";
import {Constants} from "../utils/Constants.sol";

contract SubmitIntegrationTest is Test {
    Larena larena;
    Coin internal coin;
    Pages internal pages;
    Reserve internal reserve;
    Unrevealed internal unrevealed;
    Utilities internal utils;
    Constants internal constants;
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

        constants = new Constants();
        actor = utils.createUsers(1, vm)[0];

        vm.prank(larena.owner());
        larena.setStart();
    }

    function testMakeSubmission() public {
        uint256 price = pages.pagePrice();
        uint256 bal = larena.coinBalance(actor);
        if (bal < price) {
            vm.prank(address(larena));
            coin.mintCoin(actor, price);
        }
        vm.startPrank(actor);
        uint256 pageID = pages.mintFromCoin(price, false);
        larena.submit(pageID, 1, NFTMeta.TypeURI(0), "", "");
        vm.stopPrank();
    }

    function testSubmissionDelay(uint256 _warp) public {
        _warp = bound(_warp, 1, type(uint48).max);
        vm.warp(_warp);

        uint256 price = pages.pagePrice();
        uint256 bal = larena.coinBalance(actor);
        if (bal < price) {
            vm.prank(address(larena));
            coin.mintCoin(actor, price);
        }
        vm.startPrank(actor);
        uint256 pageID = pages.mintFromCoin(price, false);

        (uint256 epochID, ) = larena.currentEpoch();
        uint256 start = larena.epochStart(epochID);

        if (block.timestamp - start > constants.SUBMISSION_DEADLINE()) {
            vm.expectRevert(Larena.InvalidTime.selector);
            larena.submit(pageID, 1, NFTMeta.TypeURI(0), "", "");
        } else {
            larena.submit(pageID, 1, NFTMeta.TypeURI(0), "", "");
        }
        vm.stopPrank();
    }

    function testDuplicate() public {
        uint256 price = pages.pagePrice();

        vm.prank(address(larena));
        coin.mintCoin(actor, price);

        vm.startPrank(address(actor));
        uint256 pageID = pages.mintFromCoin(price, false);
        larena.submit(pageID, 1, NFTMeta.TypeURI(0), "", "");

        vm.expectRevert(Pages.Used.selector);
        larena.submit(pageID, 1, NFTMeta.TypeURI(0), "", "");
        vm.stopPrank();
    }
}
