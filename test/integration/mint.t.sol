// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2 as console} from "forge-std/console2.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {Coin} from "../../src/Coin.sol";
import {Larena} from "../../src/Larena.sol";
import {Pages} from "../../src/Pages.sol";
import {Reserve} from "../../src/utils/Reserve.sol";
import {Utilities} from "../utils/Utilities.sol";
import {Interfaces} from "../utils/Interfaces.sol";
import {Unrevealed} from "../../src/utils/Unrevealed.sol";

contract MintIntegrationTest is Test, Interfaces {
    Larena larena;
    Coin internal coin;
    Pages internal pages;
    Reserve internal reserve;
    Unrevealed internal unrevealed;
    Utilities internal utils;
    address actor;

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
        actor = utils.createUsers(1, vm)[0];

        vm.prank(larena.owner());
        larena.setStart();
    }

    function testLarenaIdGen(uint256 _amt) public {
        _amt = bound(_amt, 1, 100);
        (uint256 epochID, ) = larena.currentEpoch();
        uint256 vaultNum = getVaultSupply(
            epochID,
            larena.INITIAL_VAULT_SUPPLY_PER_EPOCH(),
            larena.VAULT_SUPPLY_PER_EPOCH(),
            larena.VAULT_SUPPLY_SWITCHOVER()
        );

        Larena.Epoch memory e;

        for (uint i; i < _amt; i++) {
            uint256 p = larena.getPrice();
            vm.deal(actor, p);
            vm.prank(actor);
            larena.mint{value: p}();
        }

        e = getEpochs(epochID, larena);
        assertEq(_amt, larena.$prevTokenID());

        // vault mint, which uses different mint function
        larena.vaultMint();

        e = getEpochs(epochID, larena);
        assertEq(_amt + vaultNum, larena.$prevTokenID());

        for (uint i; i < _amt; i++) {
            uint256 p = larena.getPrice();
            vm.deal(actor, p);
            vm.prank(actor);
            larena.mint{value: p}();
        }

        e = getEpochs(epochID, larena);
        assertEq(_amt + _amt + vaultNum, larena.$prevTokenID());
    }

    function testLarenaIndex(uint256 _amt) public {
        _amt = bound(_amt, 1, 100);

        if (_amt % 2 == 0) {
            larena.vaultMint();
        }

        for (uint i; i < _amt; i++) {
            uint256 p = larena.getPrice();
            vm.deal(actor, p);
            vm.prank(actor);
            larena.mint{value: p}();
        }

        if (_amt % 2 != 0) {
            larena.vaultMint();
        }

        uint256 maxId = larena.$prevTokenID();

        // this only works during first epoch.
        for (uint256 i = 1; i <= maxId; i++) {
            (uint32 index, , , ) = larena.getLarenaData(i);
            assertEq(index, i);
        }
    }
}
