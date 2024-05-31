// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {stdError} from "forge-std/StdError.sol";
import {fromDaysWadUnsafe} from "solmate/utils/SignedWadMath.sol";

import {Coin} from "../../src/Coin.sol";
import {Larena} from "../../src/Larena.sol";
import {Pages} from "../../src/Pages.sol";
import {Reserve} from "../../src/utils/Reserve.sol";
import {Utilities} from "../utils/Utilities.sol";
import {NFTMeta} from "../../src/libraries/NFTMeta.sol";
import {Unrevealed} from "../../src/utils/Unrevealed.sol";
import {Constants} from "../utils/Constants.sol";
import {console2 as console} from "forge-std/console2.sol";

contract RoyaltyIntegrationTest is Test {
    Larena larena;
    Coin internal coin;
    Pages internal pages;
    Reserve internal reserve;
    Unrevealed internal unrevealed;
    Utilities internal utils;
    address internal user;
    Constants internal constants;

    function setUp() public {
        utils = new Utilities();
        address coinAddress = utils.predictContractAddress(address(this), 1, vm);
        address pagesAddress = utils.predictContractAddress(address(this), 2, vm);
        address larenaAddress = utils.predictContractAddress(address(this), 3, vm);
        reserve = new Reserve(
            Larena(larenaAddress),
            Pages(pagesAddress),
            Coin(coinAddress),
            address(this)
        );
        coin = new Coin(larenaAddress, pagesAddress);
        pages = new Pages(block.timestamp, coin, address(reserve), Larena(larenaAddress));
        larena = new Larena(coin, Pages(pagesAddress), unrevealed, address(reserve));

        constants = new Constants();
        user = utils.createUsers(1, vm)[0];

        vm.prank(larena.owner());
        larena.setStart();
    }

    function testValidId(uint16 _royalty, uint64 _salePrice) public {
        uint256 expectedRoyalty = (uint256(_salePrice) * uint256(_royalty)) /
            constants.ROYALTY_DENOMINATOR();

        uint256 price = pages.pagePrice();
        uint256 bal = larena.coinBalance(user);
        if (bal < price) {
            vm.prank(address(larena));
            coin.mintCoin(user, price);
        }

        vm.startPrank(user);
        uint256 pageID = pages.mintFromCoin(price, false);
        larena.submit(pageID, _royalty, NFTMeta.TypeURI(0), "", "");
        vm.stopPrank();

        larena.vaultMint();

        vm.warp(larena.EPOCH_LENGTH() + 2 days);
        larena.crownWinners();

        (address creator, uint256 royalty) = larena.royaltyInfo(pageID, uint256(_salePrice));
        assertEq(creator, user);
        assertEq(royalty, expectedRoyalty);
    }
}
