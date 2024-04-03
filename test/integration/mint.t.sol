// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2 as console} from "forge-std/console2.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {Goo} from "../../src/Goo.sol";
import {Ocmeme} from "../../src/Ocmeme.sol";
import {Pages} from "../../src/Pages.sol";
import {Reserve} from "../../src/utils/Reserve.sol";
import {Utilities} from "../utils/Utilities.sol";
import {Interfaces} from "../utils/Interfaces.sol";

contract MintIntegrationTest is Test, Interfaces {
    Ocmeme ocmeme;
    Goo internal goo;
    Pages internal pages;
    Reserve internal reserve;
    Utilities internal utils;
    address actor;

    function setUp() public {
        utils = new Utilities();
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
        actor = utils.createUsers(1, vm)[0];

        vm.prank(ocmeme.owner());
        ocmeme.setStart();
    }

    function testOcmemeIdGen(uint8 _amt) public {
        bound(_amt, 1, 200);
        Ocmeme.Epoch memory e;
        uint256 amt = 100;
        (uint256 epochID, ) = ocmeme.currentEpoch();

        for (uint i; i < amt; i++) {
            uint256 p = ocmeme.getPrice();
            vm.deal(actor, p);
            vm.prank(actor);
            ocmeme.mint{value: p}();
        }

        e = getEpochs(epochID, ocmeme);
        assertEq(amt, e.count);
        assertEq(amt, ocmeme.$prevTokenID());

        ocmeme.vaultMint();

        e = getEpochs(epochID, ocmeme);
        assertEq(amt + ocmeme.VAULT_NUM(), e.count);
        assertEq(amt + ocmeme.VAULT_NUM(), ocmeme.$prevTokenID());

        for (uint i; i < amt; i++) {
            uint256 p = ocmeme.getPrice();
            vm.deal(actor, p);
            vm.prank(actor);
            ocmeme.mint{value: p}();
        }

        e = getEpochs(epochID, ocmeme);
        assertEq(amt + amt + ocmeme.VAULT_NUM(), e.count);
        assertEq(amt + amt + ocmeme.VAULT_NUM(), ocmeme.$prevTokenID());
    }

    function testDeath(uint256 _warp) public {
        bound(_warp, 10 * 52 weeks, type(uint256).max);
        (uint256 epochID, ) = ocmeme.currentEpoch();
        if (epochID > 125) {
            vm.expectRevert();
            ocmeme.getPrice();

            vm.deal(actor, type(uint248).max);
            vm.startPrank(actor);
            vm.expectRevert();
            ocmeme.mint{value: type(uint248).max}();
        }
    }
}
