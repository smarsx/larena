// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {Coin} from "../../src/Coin.sol";
import {Larena} from "../../src/Larena.sol";
import {Pages} from "../../src/Pages.sol";
import {Reserve} from "../../src/utils/Reserve.sol";
import {Utilities} from "../utils/Utilities.sol";
import {MemoryPlus} from "../utils/Memory.sol";
import {Unrevealed} from "../../src/utils/Unrevealed.sol";
import {Interfaces} from "../utils/Interfaces.sol";
import {Constants} from "../utils/Constants.sol";

contract GeneralIntegrationTest is Test, MemoryPlus {
    Larena larena;
    Coin internal coin;
    Pages internal pages;
    Reserve internal reserve;
    Unrevealed internal unrevealed;
    Utilities internal utils;
    Interfaces internal interfaces;
    Constants internal constants;
    address actor;
    address[] users;

    function setUp() public {
        utils = new Utilities();
        interfaces = new Interfaces();
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

        constants = new Constants();
        users = utils.createUsers(5, vm);

        vm.prank(larena.owner());
        larena.setStart();
    }

    function testShare(uint136 p) public view {
        uint256 a = FixedPointMathLib.mulDiv(
            p,
            constants.GOLD_SHARE(),
            constants.PAYOUT_DENOMINATOR()
        );
        uint256 b = FixedPointMathLib.mulDiv(
            p,
            constants.SILVER_SHARE(),
            constants.PAYOUT_DENOMINATOR()
        );
        uint256 c = FixedPointMathLib.mulDiv(
            p,
            constants.BRONZE_SHARE(),
            constants.PAYOUT_DENOMINATOR()
        );
        uint256 d = p -
            (FixedPointMathLib.mulDiv(p, constants.GOLD_SHARE(), constants.PAYOUT_DENOMINATOR()) +
                FixedPointMathLib.mulDiv(
                    p,
                    constants.SILVER_SHARE(),
                    constants.PAYOUT_DENOMINATOR()
                ) +
                FixedPointMathLib.mulDiv(
                    p,
                    constants.BRONZE_SHARE(),
                    constants.PAYOUT_DENOMINATOR()
                ));
        assertEq(a + b + c + d, p);
    }

    function testBitPack() public pure {
        uint8 claims;
        uint256 a = claims & (1 << uint8(Larena.ClaimType.GOLD));
        uint256 b = claims & (1 << uint8(Larena.ClaimType.SILVER));
        uint256 c = claims & (1 << uint8(Larena.ClaimType.BRONZE));
        uint256 d = claims & (1 << uint8(Larena.ClaimType.VAULT));
        assertEq(a, 0);
        assertEq(b, 0);
        assertEq(c, 0);
        assertEq(d, 0);

        claims = uint8(claims | (1 << uint8(Larena.ClaimType.GOLD)));
        claims = uint8(claims | (1 << uint8(Larena.ClaimType.BRONZE)));

        assertEq(1, claims & (1 << uint8(Larena.ClaimType.GOLD)));
        assertTrue(claims & (1 << uint8(Larena.ClaimType.BRONZE)) > 0);

        claims = 255;

        uint256 e = claims & (1 << uint8(Larena.ClaimType.GOLD));
        uint256 f = claims & (1 << uint8(Larena.ClaimType.SILVER));
        uint256 g = claims & (1 << uint8(Larena.ClaimType.BRONZE));
        uint256 h = claims & (1 << uint8(Larena.ClaimType.VAULT));
        assertTrue(e > 0);
        assertTrue(f > 0);
        assertTrue(g > 0);
        assertTrue(h > 0);
    }

    function testTime(uint48 _warp) public view {
        vm.assume(_warp > 0);
        (uint256 epochID, uint256 time) = larena.currentEpoch();
        uint256 time2 = larena.epochStart(epochID);
        assertEq(time, time2);
    }

    function testBasicImpl(uint40 _warp) public brutalizeMemory {
        vm.assume(_warp > 0);
        vm.warp(_warp);

        (uint256 a, uint256 b) = larena.currentEpoch();
        (uint256 c, uint256 d) = currentEpochBasic();
        assertEq(a, c);
        assertEq(b, d);
    }

    function currentEpochBasic() internal view returns (uint256, uint256) {
        uint256 epochID;
        uint256 start;
        epochID = block.timestamp - larena.$start();
        epochID = epochID / larena.EPOCH_LENGTH();
        epochID = epochID + 1;

        start = epochID - 1;
        start = start * larena.EPOCH_LENGTH();
        start = start + larena.$start();
        return (epochID, start);
    }

    function test_index_strictly_increases_or_resets() public {
        uint256 prev;

        for (uint i = 1; i < 100; i++) {
            uint256 p = larena.getPrice();
            vm.deal(actor, p);
            vm.prank(actor);
            larena.mint{value: p}();

            (uint256 index, , , ) = larena.getLarenaData(i);
            if (1 == index) {} else {
                assertGt(index, prev);
            }
            prev = index;
        }
    }

    function testVaultSupply(uint256 _epochID) public view {
        _epochID = bound(_epochID, 1, 1000);
        uint256 vaultSupply = interfaces.getVaultSupply(
            _epochID,
            constants.INITIAL_VAULT_SUPPLY_PER_EPOCH(),
            constants.VAULT_SUPPLY_PER_EPOCH(),
            constants.VAULT_SUPPLY_SWITCHOVER()
        );
        assertTrue(vaultSupply >= 2);
        assertTrue(vaultSupply <= constants.INITIAL_VAULT_SUPPLY_PER_EPOCH());
    }

    function testVaultSupplyStrictlyDecreasesOrPlateaus() public view {
        uint256 prev;
        for (uint256 i = 1; i < 1000; i++) {
            uint256 vaultSupply = interfaces.getVaultSupply(
                i,
                constants.INITIAL_VAULT_SUPPLY_PER_EPOCH(),
                constants.VAULT_SUPPLY_PER_EPOCH(),
                constants.VAULT_SUPPLY_SWITCHOVER()
            );
            if (prev == 0) {
                prev = vaultSupply;
                continue;
            } else if (prev == 2) {
                assertEq(prev, vaultSupply);
                break;
            }
            assertTrue(vaultSupply < prev);
        }
    }
}
