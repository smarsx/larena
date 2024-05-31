// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2 as console} from "forge-std/console2.sol";

import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";

import {Larena} from "../../src/Larena.sol";
import {Coin} from "../../src/Coin.sol";
import {Pages} from "../../src/Pages.sol";
import {Reserve} from "../../src/utils/Reserve.sol";
import {MainActor} from "./actors/mainActor.sol";
import {Utilities} from "../utils/Utilities.sol";
import {Interfaces} from "../utils/Interfaces.sol";
import {Unrevealed} from "../../src/utils/Unrevealed.sol";
import {Constants} from "../utils/Constants.sol";

contract MainInvariantTest is Test, Interfaces {
    Larena public larena;
    MainActor public actor;

    Coin internal coin;
    Pages internal pages;
    Reserve internal reserve;
    Unrevealed internal unrevealed;
    Utilities internal utils;
    Constants internal constants;

    function setUp() public {
        utils = new Utilities();

        // pre-deploy compute deployed address
        address coinAddress = utils.predictContractAddress(address(this), 2, vm);
        address pagesAddress = utils.predictContractAddress(address(this), 3, vm);
        address larenaAddress = utils.predictContractAddress(address(this), 4, vm);

        // deploy
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
        constants = new Constants();

        // set start
        vm.prank(larena.owner());
        larena.setStart();

        // create handler
        actor = new MainActor(larena, pages, coin, reserve, constants);

        // transfer ownership to handler
        larena.transferOwnership(address(actor));
        reserve.transferOwnership(address(actor));

        // restrict function selectors in handler
        bytes4[] memory selectors = new bytes4[](8);
        selectors[0] = MainActor.mint.selector;
        selectors[1] = MainActor.submit.selector;
        selectors[2] = MainActor.vote.selector;
        selectors[3] = MainActor.transfer.selector;
        selectors[4] = MainActor.setWinners.selector;
        selectors[5] = MainActor.claim.selector;
        selectors[6] = MainActor.vaultMint.selector;
        selectors[7] = MainActor.recoverClaims.selector;

        targetSelector(FuzzSelector({addr: address(actor), selectors: selectors}));
        targetContract(address(actor));
    }

    // can pay claims
    function invariant_solvency() public view {
        (uint256 maxid, ) = larena.currentEpoch();
        uint256 d = constants.PAYOUT_DENOMINATOR();
        uint256 credits;
        for (uint256 i = 1; i <= maxid; i++) {
            Larena.Epoch memory e = getEpochs(i, larena);
            uint256 goldClaims = e.claims & (1 << uint8(Larena.ClaimType.GOLD));
            uint256 silverClaims = e.claims & (1 << uint8(Larena.ClaimType.SILVER));
            uint256 bronzeClaims = e.claims & (1 << uint8(Larena.ClaimType.BRONZE));
            uint256 vaultClaims = e.claims & (1 << uint8(Larena.ClaimType.VAULT));

            if (goldClaims == 0) {
                credits += FixedPointMathLib.mulDiv(e.proceeds, constants.GOLD_SHARE(), d);
            }
            if (silverClaims == 0) {
                credits += FixedPointMathLib.mulDiv(e.proceeds, constants.SILVER_SHARE(), d);
            }
            if (bronzeClaims == 0) {
                credits += FixedPointMathLib.mulDiv(e.proceeds, constants.BRONZE_SHARE(), d);
            }
            if (vaultClaims == 0) {
                credits += FixedPointMathLib.mulDiv(e.proceeds, constants.VAULT_SHARE(), d);
            }
        }
        assertTrue(address(larena).balance >= credits);
    }

    // each epoch.pages.length < max_submissions
    function invariant_pages() public view {
        (uint256 maxid, ) = larena.currentEpoch();
        for (uint i = 1; i <= maxid; i++) {
            uint256[] memory pageIds = larena.getSubmissions(i);
            assertTrue(pageIds.length <= constants.MAX_SUBMISSIONS());
        }
    }

    function invariant_accounting() public view {
        uint256 maxTokenId = larena.$prevTokenID();
        address[] memory users = actor.getUsers();

        uint32[] memory emissions = new uint32[](maxTokenId + 1);
        address[] memory owners = new address[](maxTokenId + 1);

        // load token data
        for (uint256 i = 1; i <= maxTokenId; i++) {
            (, uint32 _em, , address _owner) = larena.getLarenaData(i);
            assertTrue(_em > 0);
            emissions[i] = _em;
            owners[i] = _owner;
        }

        // iterate users
        for (uint256 j; j < users.length; j++) {
            uint32 ocCount;
            uint32 ocEm;
            address user = users[j];
            // iterate all tokens
            for (uint256 k = 1; k <= maxTokenId; k++) {
                if (owners[k] == user) {
                    ocCount++;
                    ocEm += emissions[k];
                }
            }

            (uint32 userCount, uint32 userEm, , ) = larena.getUserData(user);
            assertEq(ocCount, userCount);
            assertEq(ocEm, userEm);
        }
    }

    function invariant_user_accounting() public view {
        // users
        address[] memory users = actor.getUsers();
        for (uint256 i; i < users.length; i++) {
            (uint32 count, uint32 em, , ) = larena.getUserData(users[i]);
            assertTrue((count == 0 && em == 0) || em > count);
        }
    }

    function invariant_no_claims() public view {
        uint256[] memory recoveries = actor.getRecoveries();
        for (uint i; i < recoveries.length; i++) {
            Larena.Epoch memory e = getEpochs(i, larena);
            uint256 goldClaims = e.claims & (1 << uint8(Larena.ClaimType.GOLD));
            uint256 silverClaims = e.claims & (1 << uint8(Larena.ClaimType.SILVER));
            uint256 bronzeClaims = e.claims & (1 << uint8(Larena.ClaimType.BRONZE));
            uint256 vaultClaims = e.claims & (1 << uint8(Larena.ClaimType.VAULT));
            assertTrue(goldClaims > 0);
            assertTrue(silverClaims > 0);
            assertTrue(bronzeClaims > 0);
            assertTrue(vaultClaims == 0);
        }
    }

    function invariant_winners() public view {
        (uint256 maxid, ) = larena.currentEpoch();
        for (uint i = 1; i <= maxid; i++) {
            Larena.Epoch memory e = getEpochs(i, larena);
            if (e.goldPageID > 0) {
                uint256 gold;
                uint256 silver;
                uint256 bronze;
                uint256 goldIdx;
                uint256 silverIdx;
                uint256 bronzeIdx;
                uint256[] memory pageIDs = larena.getSubmissions(i);
                for (uint256 j; j < pageIDs.length; j++) {
                    uint256 pageId = pageIDs[j];
                    Larena.Vote memory v = getVotes(pageId, larena);
                    if (v.votes > gold) {
                        // silver -> bronze
                        bronze = silver;
                        bronzeIdx = silverIdx;
                        // gold -> silver
                        silver = gold;
                        silverIdx = goldIdx;
                        // new gold
                        gold = v.votes;
                        goldIdx = j;
                    } else if (v.votes > silver) {
                        // silver -> bronze
                        bronze = silver;
                        bronzeIdx = silverIdx;

                        // new silver
                        silver = v.votes;
                        silverIdx = j;
                    } else if (v.votes > bronze) {
                        // new bronze
                        bronze = v.votes;
                        bronzeIdx = j;
                    }
                }
                assertEq(e.goldPageID, pageIDs[goldIdx]);
                assertEq(e.silverPageID, pageIDs[silverIdx]);
                assertEq(e.bronzePageID, pageIDs[bronzeIdx]);
            }
        }
    }

    function invariant_index_strictly_inc_or_resets() public view {
        uint256 maxTokenId = larena.$prevTokenID();
        uint256 prev;

        for (uint256 i = 1; i <= maxTokenId; i++) {
            (uint256 index, , , ) = larena.getLarenaData(i);
            if (1 == index) {} else {
                assertTrue(index - prev == 1);
            }
            prev = index;
        }
    }
}
