// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Content} from "../Content.sol";
import {Decoder} from "../utils/Decoder.sol";
import {SSTORE2} from "solady/utils/SSTORE2.sol";
import {NFTMeta} from "../../src/libraries/NFTMeta.sol";
import {Utilities} from "../utils/Utilities.sol";
import {Reserve} from "../../src/utils/Reserve.sol";
import {Goo} from "../../src/Goo.sol";
import {Ocmeme} from "../../src/Ocmeme.sol";
import {Pages} from "../../src/Pages.sol";
import {Decoder} from "../utils/Decoder.sol";

contract RenderTest is Test, Content {
    Ocmeme ocmeme;
    Goo internal goo;
    Pages internal pages;
    Reserve internal reserve;
    Utilities internal utils;
    Decoder internal decoder;

    address internal user;
    address internal owner;
    uint256 eventID;

    error InvalidID();

    function setUp() public override {
        utils = new Utilities();
        decoder = new Decoder();
        super.setUp();

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

        owner = ocmeme.owner();

        vm.prank(owner);
        ocmeme.setStart();

        (eventID, ) = ocmeme.currentEpoch();
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
        string memory uri = ocmeme.tokenURI(_tokenID);
        string memory title = getTitle(eventID);

        Decoder.DecodedContent memory res = decoder.decodeContent(
            false,
            NFTMeta.TypeURI.IMG,
            1,
            vm,
            uri
        );

        assertEq(res.name, title);
        assertEq(res.description, title);
    }

    function testUri() public {
        string memory expectedSvg = getImg();
        string memory expectedDescription = "ocmeme loader";
        string memory title = getTitle(eventID);

        uint256 p = pages.pagePrice();
        vm.prank(address(ocmeme));
        goo.mintGoo(user, p);
        vm.prank(user);
        uint256 pageID = pages.mintFromGoo(p, false);

        vm.prank(user);
        ocmeme.submit(pageID, 0, NFTMeta.TypeURI(0), expectedDescription, expectedSvg);

        uint256 start = ocmeme.epochStart(eventID);
        vm.warp(start + ocmeme.EPOCH_LENGTH());
        ocmeme.crownWinners();

        string memory uri = ocmeme.tokenURI(1);
        Decoder.DecodedContent memory res = decoder.decodeContent(
            false,
            NFTMeta.TypeURI.IMG,
            2,
            vm,
            uri
        );

        assertEq(res.name, title);
        assertEq(res.description, expectedDescription);
        assertEq(res.content, expectedSvg);
    }

    function testUriHtml() public {
        string memory expectedAni = getAnimation();
        string memory expectedDescription = "ocmeme loader";
        string memory title = getTitle(eventID);

        uint256 p = pages.pagePrice();

        vm.prank(address(ocmeme));
        goo.mintGoo(user, p);
        vm.prank(address(user));
        uint256 pageID = pages.mintFromGoo(p, false);

        vm.prank(user);
        ocmeme.submit(pageID, 0, NFTMeta.TypeURI(1), expectedDescription, expectedAni);

        uint256 start = ocmeme.epochStart(eventID);
        vm.warp(start + ocmeme.EPOCH_LENGTH());
        ocmeme.crownWinners();

        string memory uri = ocmeme.tokenURI(1);
        Decoder.DecodedContent memory res = decoder.decodeContent(
            false,
            NFTMeta.TypeURI.ANIMATION,
            2,
            vm,
            uri
        );

        assertEq(res.name, title);
        assertEq(res.description, expectedDescription);
        assertEq(res.content, expectedAni);
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
