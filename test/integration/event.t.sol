// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2 as console} from "forge-std/console2.sol";

import {Coin} from "../../src/Coin.sol";
import {Larena} from "../../src/Larena.sol";
import {Pages} from "../../src/Pages.sol";
import {Reserve} from "../../src/utils/Reserve.sol";
import {Utilities} from "../utils/Utilities.sol";
import {MemoryPlus} from "../utils/Memory.sol";
import {Unrevealed} from "../../src/utils/Unrevealed.sol";

contract EpochIntegrationTest is Test, MemoryPlus {
    Larena larena;
    Coin internal coin;
    Pages internal pages;
    Reserve internal reserve;
    Unrevealed internal unrevealed;
    Utilities internal utils;
    address internal user;

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
        user = utils.createUsers(1, vm)[0];

        vm.prank(larena.owner());
        larena.setStart();
    }

    function testStartTime(uint256 _warp) public brutalizeMemory {
        _warp = bound(_warp, 1, type(uint48).max);
        vm.warp(_warp);

        (uint256 epochID, uint256 start) = larena.currentEpoch();

        assertTrue(epochID > 0);
        assertTrue(start >= larena.$start());
    }
}
