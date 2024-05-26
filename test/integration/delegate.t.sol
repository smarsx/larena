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
import {Decoder} from "../utils/Decoder.sol";
import {Delegate} from "../utils/DelegatePage.t.sol";

contract DelegateIntegrationTest is Test {
    Larena larena;
    Coin internal coin;
    Pages internal pages;
    Reserve internal reserve;
    Unrevealed internal unrevealed;
    Delegate internal delegate;
    Utilities internal utils;
    Decoder internal decoder;
    address actor;

    function setUp() public {
        utils = new Utilities();
        decoder = new Decoder();
        delegate = new Delegate();
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

    function testPageDelegateDecoded() public {
        // mint page, submit delegate.
        uint256 pageID;
        {
            uint256 price = pages.pagePrice();
            uint256 bal = larena.coinBalance(actor);
            if (bal < price) {
                vm.prank(address(larena));
                coin.mintCoin(actor, price);
            }
            vm.startPrank(actor);
            pageID = pages.mintFromCoin(price, false);
            larena.submitDelegate(pageID, 1, address(delegate));
            vm.stopPrank();
        }
        string memory uri = pages.tokenURI(pageID);
        assertEq(
            uri,
            "data:image/svg+xml;base64,PHN2ZyB4bWxucz0naHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmcnIHZpZXdCb3g9JzAgMCAxIDEnPjxwYXRoIGZpbGw9J2JsdWUnIGQ9J00wLDBoMXYxSDB6Jy8+PC9zdmc+"
        );
    }

    function testLarenaPageDelegateDecoded() public {
        larena.vaultMint();

        // mint page, submit delegate.
        uint256 pageID;
        {
            uint256 price = pages.pagePrice();
            uint256 bal = larena.coinBalance(actor);
            if (bal < price) {
                vm.prank(address(larena));
                coin.mintCoin(actor, price);
            }
            vm.startPrank(actor);
            pageID = pages.mintFromCoin(price, false);
            larena.submitDelegate(pageID, 1, address(delegate));
            vm.stopPrank();
        }

        // vote
        {
            uint256 amt = 100e18;
            vm.prank(address(larena));
            coin.mintCoin(actor, amt);

            vm.prank(actor);
            larena.vote(pageID, amt, false);
        }

        // crown winners
        {
            vm.warp(block.timestamp + larena.EPOCH_LENGTH());
            larena.crownWinners();
        }

        string memory uri = larena.tokenURI(1);
        Decoder.DecodedContent memory dc = decoder.decodeContent(
            false,
            NFTMeta.TypeURI(0),
            12,
            vm,
            uri
        );
        assertEq(dc.name, "larena #1");
        assertEq(dc.description, "the delegated page.");
    }
}
