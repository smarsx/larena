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
import {Ocmeme} from "../../src/Ocmeme.sol";
import {Pages} from "../../src/Pages.sol";
import {Decoder} from "../utils/Decoder.sol";
import {MemoryPlus} from "../utils/Memory.sol";

contract RenderTest is Test, Content, MemoryPlus {
    Ocmeme ocmeme;
    Coin internal coin;
    Pages internal pages;
    Reserve internal reserve;
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

        user = utils.createUsers(1, vm)[0];

        owner = ocmeme.owner();

        vm.prank(owner);
        ocmeme.setStart();

        (epochID, ) = ocmeme.currentEpoch();
        ocmeme.vaultMint();

        for (uint i; i < 256; i++) {
            uint256 p = ocmeme.getPrice();
            vm.deal(user, p);
            vm.prank(user);
            ocmeme.mint{value: p}();
        }
    }

    function testRevertBigId() public {
        vm.expectRevert(Ocmeme.InvalidID.selector);
        ocmeme.tokenURI(10000);
    }

    function testUnrevealedUri(uint8 _tokenID) public {
        vm.assume(_tokenID > 0);
        string memory title = getTitle(epochID);
        string memory uri = ocmeme.tokenURI(_tokenID);
        _checkMemory(uri);

        Decoder.DecodedContent memory decoded = decoder.decodeContent(
            false,
            NFTMeta.TypeURI.IMG,
            1,
            vm,
            uri
        );

        assertEq(decoded.name, title);
        assertEq(decoded.description, title);
    }

    function testUri() public {
        string memory expectedSvg = getImg();
        string memory expectedDescription = "ocmeme loader";
        string memory title = getTitle(epochID);

        uint256 p = pages.pagePrice();
        vm.prank(address(ocmeme));
        coin.mintCoin(user, p);
        vm.prank(user);
        uint256 pageID = pages.mintFromCoin(p, false);

        vm.prank(user);
        ocmeme.submit(pageID, 0, NFTMeta.TypeURI(0), expectedDescription, expectedSvg);

        uint256 start = ocmeme.epochStart(epochID);
        vm.warp(start + ocmeme.EPOCH_LENGTH());
        ocmeme.crownWinners();

        string memory uri = ocmeme.tokenURI(1);
        _checkMemory(uri);

        Decoder.DecodedContent memory decoded = decoder.decodeContent(
            false,
            NFTMeta.TypeURI.IMG,
            2,
            vm,
            uri
        );

        assertEq(decoded.name, title);
        assertEq(decoded.description, expectedDescription);
        assertEq(decoded.content, expectedSvg);
    }

    function testUriHtml() public {
        string memory expectedAni = getAnimation();
        string memory expectedDescription = "ocmeme loader";
        string memory title = getTitle(epochID);

        uint256 p = pages.pagePrice();

        vm.prank(address(ocmeme));
        coin.mintCoin(user, p);
        vm.prank(address(user));
        uint256 pageID = pages.mintFromCoin(p, false);

        vm.prank(user);
        ocmeme.submit(pageID, 0, NFTMeta.TypeURI(1), expectedDescription, expectedAni);

        uint256 start = ocmeme.epochStart(epochID);
        vm.warp(start + ocmeme.EPOCH_LENGTH());
        ocmeme.crownWinners();

        string memory uri = ocmeme.tokenURI(1);
        _checkMemory(uri);

        Decoder.DecodedContent memory decoded = decoder.decodeContent(
            false,
            NFTMeta.TypeURI.ANIMATION,
            2,
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

        ocmeme.updateBaseURI(baseURI);
        string memory uri = ocmeme.tokenURI(1);
        assertEq(uri, expectedURI);

        ocmeme.updateBaseURI("");
        string memory uri2 = ocmeme.tokenURI(1);
        assertTrue(bytes(uri2).length > 30);
        vm.stopPrank();
    }
}
