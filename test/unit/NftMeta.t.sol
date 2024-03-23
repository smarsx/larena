// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Content} from "../Content.sol";
import {Decoder} from "../utils/Decoder.sol";
import {SSTORE2} from "solady/utils/SSTORE2.sol";
import {NFTMeta} from "../../src/libraries/NFTMeta.sol";

contract NftMetaTest is Test, Content {
    Decoder internal decoder;

    function setUp() public override {
        decoder = new Decoder();
        super.setUp();
    }

    function testSvgDecodeAll() public {
        NFTMeta.MetaParams[] memory imgs = getImgContents();
        uint256 len = imgs.length;
        for (uint256 i; i < len; i++) {
            // construct token uri
            // store sstore2
            address pointer = SSTORE2.write(NFTMeta.constructTokenURI(imgs[i]));
            string memory uri = NFTMeta.render(string(SSTORE2.read(pointer)));

            Decoder.DecodedContent memory content = decoder.decodeContent(
                false,
                NFTMeta.TypeURI.IMG,
                1,
                vm,
                uri
            );

            assertEq(content.name, imgs[i].name);
            assertEq(content.description, imgs[i].description);
            assertEq(content.content, imgs[i].duri);
        }
    }

    function testHtmlDecodeAll() public {
        NFTMeta.MetaParams[] memory imgs = getAniContents();
        uint256 len = imgs.length;
        for (uint256 i; i < len; i++) {
            // construct token uri
            // sstore2
            address pointer = SSTORE2.write(NFTMeta.constructTokenURI(imgs[i]));
            string memory uri = NFTMeta.render(string(SSTORE2.read(pointer)));

            Decoder.DecodedContent memory content = decoder.decodeContent(
                false,
                NFTMeta.TypeURI.ANIMATION,
                2,
                vm,
                uri
            );

            assertEq(content.name, imgs[i].name);
            assertEq(content.description, imgs[i].description);
            assertEq(content.content, imgs[i].duri);
        }
    }
}
