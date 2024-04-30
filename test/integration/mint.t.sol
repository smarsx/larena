// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2 as console} from "forge-std/console2.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {Coin} from "../../src/Coin.sol";
import {Ocmeme} from "../../src/Ocmeme.sol";
import {Pages} from "../../src/Pages.sol";
import {Reserve} from "../../src/utils/Reserve.sol";
import {Utilities} from "../utils/Utilities.sol";
import {Interfaces} from "../utils/Interfaces.sol";

contract MintIntegrationTest is Test, Interfaces {
    Ocmeme ocmeme;
    Coin internal coin;
    Pages internal pages;
    Reserve internal reserve;
    Utilities internal utils;
    address actor;

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
        actor = utils.createUsers(1, vm)[0];

        vm.prank(ocmeme.owner());
        ocmeme.setStart();
    }

    function testOcmemeIdGen(uint256 _amt) public {
        _amt = bound(_amt, 1, 100);
        (uint256 epochID, ) = ocmeme.currentEpoch();
        uint256 vaultNum = epochID > 55 ? 0 : epochID > 28
            ? 2
            : ocmeme.INITIAL_VAULT_SUPPLY_PER_EPOCH() - epochID;

        Ocmeme.Epoch memory e;

        for (uint i; i < _amt; i++) {
            uint256 p = ocmeme.getPrice();
            vm.deal(actor, p);
            vm.prank(actor);
            ocmeme.mint{value: p}();
        }

        e = getEpochs(epochID, ocmeme);
        assertEq(_amt, ocmeme.$prevTokenID());

        // vault mint, which uses different mint function
        ocmeme.vaultMint();

        e = getEpochs(epochID, ocmeme);
        assertEq(_amt + vaultNum, ocmeme.$prevTokenID());

        for (uint i; i < _amt; i++) {
            uint256 p = ocmeme.getPrice();
            vm.deal(actor, p);
            vm.prank(actor);
            ocmeme.mint{value: p}();
        }

        e = getEpochs(epochID, ocmeme);
        assertEq(_amt + _amt + vaultNum, ocmeme.$prevTokenID());
    }
}
