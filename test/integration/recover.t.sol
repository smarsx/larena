// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {stdError} from "forge-std/StdError.sol";
import {fromDaysWadUnsafe} from "solmate/utils/SignedWadMath.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";

import {Coin} from "../../src/Coin.sol";
import {Ocmeme} from "../../src/Ocmeme.sol";
import {Pages} from "../../src/Pages.sol";
import {Reserve} from "../../src/utils/Reserve.sol";
import {Utilities} from "../utils/Utilities.sol";
import {NFTMeta} from "../../src/libraries/NFTMeta.sol";
import {MemoryPlus} from "../utils/Memory.sol";
import {Interfaces} from "../utils/Interfaces.sol";

contract RecoverIntegrationTest is Test, MemoryPlus, Interfaces {
    Ocmeme ocmeme;
    Coin internal coin;
    Pages internal pages;
    Reserve internal reserve;
    Utilities internal utils;
    address[] internal users;
    uint256 epochID;

    function setUp() public {
        utils = new Utilities();
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
        users = utils.createUsers(5, vm);

        vm.prank(ocmeme.owner());
        ocmeme.setStart();

        (epochID, ) = ocmeme.currentEpoch();
        for (uint i; i < users.length; i++) {
            address user = users[i];

            // mint page
            uint256 price = pages.pagePrice();
            vm.prank(address(ocmeme));
            coin.mintCoin(user, price);

            vm.prank(address(user));
            uint256 pageID = pages.mintFromCoin(price, false);

            // submit
            vm.prank(address(user));
            ocmeme.submit(pageID, 0, NFTMeta.TypeURI(0), "", "");
        }

        // mint ocmeme
        for (uint256 i; i < 100; i++) {
            address user = users[i % users.length];
            uint256 mprice = ocmeme.getPrice();
            vm.deal(user, mprice);
            vm.prank(address(user));
            ocmeme.mint{value: mprice}();
        }

        ocmeme.vaultMint();

        // warp past epoch
        vm.warp(block.timestamp + ocmeme.EPOCH_LENGTH());
        ocmeme.crownWinners();
    }

    function testTime(uint40 _time) public {
        uint256 start = ocmeme.epochStart(epochID);
        uint256 rd = start + ocmeme.RECOVERY_PERIOD();
        vm.assume(_time < rd);
        vm.assume(_time > 2);
        vm.warp(start + ocmeme.RECOVERY_PERIOD() - _time);

        vm.startPrank(address(ocmeme.owner()));
        vm.expectRevert(Ocmeme.InvalidTime.selector);
        ocmeme.recoverPayout(epochID);
        vm.stopPrank();
    }

    function testRecoverPayout(uint256 _seed) public brutalizeMemory {
        uint256 idx = _seed % 4;
        address vault = ocmeme.$vault();
        Ocmeme.Epoch memory e = getEpochs(epochID, ocmeme);

        address winner;
        uint256 winnerbal;
        uint256 winnings;
        if (idx == 0) {
            winner = pages.ownerOf(e.goldPageID);
            winnerbal = address(winner).balance;
            vm.prank(winner);
            ocmeme.claimGold(epochID);
        } else if (idx == 1) {
            winner = pages.ownerOf(e.silverPageID);
            winnerbal = address(winner).balance;
            vm.prank(winner);
            ocmeme.claimSilver(epochID);
        } else if (idx == 2) {
            winner = pages.ownerOf(e.bronzePageID);
            winnerbal = address(winner).balance;
            vm.prank(winner);
            ocmeme.claimBronze(epochID);
        }

        winnings = address(winner).balance - winnerbal;
        vm.warp(block.timestamp + ocmeme.RECOVERY_PERIOD());
        uint256 b = address(vault).balance;
        vm.prank(ocmeme.owner());
        ocmeme.recoverPayout(epochID);

        assertTrue(address(vault).balance == (b + e.proceeds) - winnings);
    }
}
