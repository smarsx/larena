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
import {Unrevealed as NewUnrevealed} from "../utils/Unrevealed.sol";

contract UnrevealedIntegrationTest is Test {
    Larena larena;
    Coin internal coin;
    Pages internal pages;
    Reserve internal reserve;
    Unrevealed internal unrevealed;
    NewUnrevealed internal newUnrevealed;
    Utilities internal utils;
    Decoder internal decoder;
    address actor;

    function setUp() public {
        utils = new Utilities();
        decoder = new Decoder();
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

    function testUnrevealedDecoded() public {
        string memory newDescription = "";
        larena.vaultMint();
        string memory uri = larena.tokenURI(1);
        Decoder.DecodedContent memory dc = decoder.decodeContent(
            false,
            NFTMeta.TypeURI(0),
            1,
            vm,
            uri
        );
        assertEq(dc.name, "larena #1");
        assertEq(dc.description, "larena #1");

        newUnrevealed = new NewUnrevealed(newDescription);
        larena.updateUnrevealedURI(address(newUnrevealed));

        uri = larena.tokenURI(1);
        Decoder.DecodedContent memory dc2 = decoder.decodeContent(
            false,
            NFTMeta.TypeURI(0),
            1,
            vm,
            uri
        );
        assertEq(dc2.name, "larena #1");
        assertEq(dc2.description, newDescription);
    }
}
