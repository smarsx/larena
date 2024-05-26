// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Content} from "../Content.sol";
import {Decoder} from "../utils/Decoder.sol";
import {SSTORE2} from "solady/utils/SSTORE2.sol";
import {NFTMeta} from "../../src/libraries/NFTMeta.sol";
import {Utilities} from "../utils/Utilities.sol";
import {Reserve} from "../../src/utils/Reserve.sol";
import {Coin} from "../../src/Coin.sol";
import {Larena} from "../../src/Larena.sol";
import {Pages} from "../../src/Pages.sol";
import {Decoder} from "../utils/Decoder.sol";
import {MemoryPlus} from "../utils/Memory.sol";
import {Unrevealed} from "../../src/utils/Unrevealed.sol";

contract RenderTest is Test, Content, MemoryPlus {
    Larena larena;
    Coin internal coin;
    Pages internal pages;
    Reserve internal reserve;
    Unrevealed internal unrevealed;
    Utilities internal utils;
    Decoder internal decoder;

    address internal user;
    address internal owner;
    uint256 epochID;

    error InvalidID();

    function setUp() public override {
        utils = new Utilities();
        decoder = new Decoder();
        super.setUp();

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

        user = utils.createUsers(1, vm)[0];

        owner = larena.owner();

        vm.prank(owner);
        larena.setStart();

        (epochID, ) = larena.currentEpoch();
        larena.vaultMint();

        for (uint i; i < 256; i++) {
            uint256 p = larena.getPrice();
            vm.deal(user, p);
            vm.prank(user);
            larena.mint{value: p}();
        }
    }

    function testRevertBigId() public {
        vm.expectRevert(Larena.InvalidID.selector);
        larena.tokenURI(10000);
    }

    function testUnrevealedUri(uint8 _tokenID) public {
        vm.assume(_tokenID > 0);
        string memory title = getTitle(epochID);
        string memory uri = larena.tokenURI(_tokenID);
        _checkMemory(uri);

        Decoder.DecodedContent memory decoded = decoder.decodeContent(
            false,
            NFTMeta.TypeURI.IMG,
            16,
            vm,
            uri
        );

        assertEq(decoded.name, title);
        assertEq(decoded.description, title);
    }

    function testUri() public {
        string memory expectedSvg = getImg();
        string memory expectedDescription = "larena loader";
        string memory title = getTitle(epochID);

        uint256 p = pages.pagePrice();
        vm.prank(address(larena));
        coin.mintCoin(user, p);
        vm.prank(user);
        uint256 pageID = pages.mintFromCoin(p, false);

        vm.prank(user);
        larena.submit(pageID, 0, NFTMeta.TypeURI(0), expectedDescription, expectedSvg);

        uint256 start = larena.epochStart(epochID);
        vm.warp(start + larena.EPOCH_LENGTH());
        larena.crownWinners();

        string memory uri = larena.tokenURI(1);
        _checkMemory(uri);

        Decoder.DecodedContent memory decoded = decoder.decodeContent(
            false,
            NFTMeta.TypeURI.IMG,
            22,
            vm,
            uri
        );

        assertEq(decoded.name, title);
        assertEq(decoded.description, expectedDescription);
        assertEq(decoded.content, expectedSvg);
    }

    function testUriHtml() public {
        string memory expectedAni = getAnimation();
        string memory expectedDescription = "larena loader";
        string memory title = getTitle(epochID);

        uint256 p = pages.pagePrice();

        vm.prank(address(larena));
        coin.mintCoin(user, p);
        vm.prank(address(user));
        uint256 pageID = pages.mintFromCoin(p, false);

        vm.prank(user);
        larena.submit(pageID, 0, NFTMeta.TypeURI(1), expectedDescription, expectedAni);

        uint256 start = larena.epochStart(epochID);
        vm.warp(start + larena.EPOCH_LENGTH());
        larena.crownWinners();

        string memory uri = larena.tokenURI(1);
        _checkMemory(uri);

        Decoder.DecodedContent memory decoded = decoder.decodeContent(
            false,
            NFTMeta.TypeURI.ANIMATION,
            21,
            vm,
            uri
        );

        assertEq(decoded.name, title);
        assertEq(decoded.description, expectedDescription);
        assertEq(decoded.content, expectedAni);
    }

    function testEmptyBaseURI() public {
        vm.startPrank(address(owner));
        string memory baseURI = "https://hotdog.com/";
        string memory expectedURI = string.concat(baseURI, "1");

        larena.updateBaseURI(baseURI);
        string memory uri = larena.tokenURI(1);
        assertEq(uri, expectedURI);

        larena.updateBaseURI("");
        string memory uri2 = larena.tokenURI(1);
        assertTrue(bytes(uri2).length > 30);
        vm.stopPrank();
    }
}
