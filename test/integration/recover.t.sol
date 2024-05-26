// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {stdError} from "forge-std/StdError.sol";
import {fromDaysWadUnsafe} from "solmate/utils/SignedWadMath.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";

import {Coin} from "../../src/Coin.sol";
import {Larena} from "../../src/Larena.sol";
import {Pages} from "../../src/Pages.sol";
import {Reserve} from "../../src/utils/Reserve.sol";
import {Utilities} from "../utils/Utilities.sol";
import {NFTMeta} from "../../src/libraries/NFTMeta.sol";
import {MemoryPlus} from "../utils/Memory.sol";
import {Interfaces} from "../utils/Interfaces.sol";
import {Unrevealed} from "../../src/utils/Unrevealed.sol";

contract RecoverIntegrationTest is Test, MemoryPlus, Interfaces {
    Larena larena;
    Coin internal coin;
    Pages internal pages;
    Reserve internal reserve;
    Unrevealed internal unrevealed;
    Utilities internal utils;
    address[] internal users;
    uint256 epochID;

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
        users = utils.createUsers(5, vm);

        vm.prank(larena.owner());
        larena.setStart();

        (epochID, ) = larena.currentEpoch();
        for (uint i; i < users.length; i++) {
            address user = users[i];

            // mint page
            uint256 price = pages.pagePrice();
            vm.prank(address(larena));
            coin.mintCoin(user, price);

            vm.prank(address(user));
            uint256 pageID = pages.mintFromCoin(price, false);

            // submit
            vm.prank(address(user));
            larena.submit(pageID, 0, NFTMeta.TypeURI(0), "", "");
        }

        // mint larena
        for (uint256 i; i < 100; i++) {
            address user = users[i % users.length];
            uint256 mprice = larena.getPrice();
            vm.deal(user, mprice);
            vm.prank(address(user));
            larena.mint{value: mprice}();
        }

        larena.vaultMint();

        // warp past epoch
        vm.warp(block.timestamp + larena.EPOCH_LENGTH());
        larena.crownWinners();
    }

    function testTime(uint40 _time) public {
        uint256 start = larena.epochStart(epochID);
        uint256 rd = start + larena.RECOVERY_PERIOD();
        vm.assume(_time < rd);
        vm.assume(_time > 2);
        vm.warp(start + larena.RECOVERY_PERIOD() - _time);

        vm.startPrank(address(larena.owner()));
        vm.expectRevert(Larena.InvalidTime.selector);
        larena.recoverPayout(epochID);
        vm.stopPrank();
    }

    function testRecoverPayout(uint256 _seed) public brutalizeMemory {
        uint256 idx = _seed % 4;
        address vault = larena.$vault();
        Larena.Epoch memory e = getEpochs(epochID, larena);

        address winner;
        uint256 winnerbal;
        uint256 winnings;
        if (idx == 0) {
            winner = pages.ownerOf(e.goldPageID);
            winnerbal = address(winner).balance;
            vm.prank(winner);
            larena.claim(epochID, Larena.ClaimType.GOLD);
        } else if (idx == 1) {
            winner = pages.ownerOf(e.silverPageID);
            winnerbal = address(winner).balance;
            vm.prank(winner);
            larena.claim(epochID, Larena.ClaimType.SILVER);
        } else if (idx == 2) {
            winner = pages.ownerOf(e.bronzePageID);
            winnerbal = address(winner).balance;
            vm.prank(winner);
            larena.claim(epochID, Larena.ClaimType.BRONZE);
        }

        winnings = address(winner).balance - winnerbal;
        vm.warp(block.timestamp + larena.RECOVERY_PERIOD());
        uint256 b = address(vault).balance;
        vm.prank(larena.owner());
        larena.recoverPayout(epochID);

        assertTrue(address(vault).balance == (b + e.proceeds) - winnings);
    }
}
