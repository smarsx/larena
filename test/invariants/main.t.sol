// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2 as console} from "forge-std/console2.sol";

import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";

import {Ocmeme} from "../../src/Ocmeme.sol";
import {Goo} from "../../src/Goo.sol";
import {Pages} from "../../src/Pages.sol";
import {Reserve} from "../../src/utils/Reserve.sol";
import {MainActor} from "./actors/mainActor.sol";
import {Utilities} from "../utils/Utilities.sol";

contract MainInvariantTest is Test {
    Ocmeme public ocmeme;
    MainActor public actor;

    Goo internal goo;
    Pages internal pages;
    Reserve internal reserve;
    Utilities internal utils;

    function setUp() public {
        utils = new Utilities();

        // pre-deploy compute deployed address
        address gooAddress = utils.predictContractAddress(address(this), 1, vm);
        address pagesAddress = utils.predictContractAddress(address(this), 2, vm);
        address ocmemeAddress = utils.predictContractAddress(address(this), 3, vm);

        // deploy
        reserve = new Reserve(
            Ocmeme(ocmemeAddress),
            Pages(pagesAddress),
            Goo(gooAddress),
            address(this)
        );
        goo = new Goo(ocmemeAddress, pagesAddress);
        pages = new Pages(block.timestamp, goo, address(reserve), Ocmeme(ocmemeAddress));
        ocmeme = new Ocmeme(goo, Pages(pagesAddress), address(reserve));

        // set start
        vm.prank(ocmeme.owner());
        ocmeme.setStart();

        // create handler
        actor = new MainActor(ocmeme, pages, goo, reserve);

        // transfer ownership to handler
        ocmeme.transferOwnership(address(actor));
        reserve.transferOwnership(address(actor));

        // restrict function selectors in handler
        bytes4[] memory selectors = new bytes4[](9);
        selectors[0] = MainActor.mint.selector;
        selectors[1] = MainActor.submit.selector;
        selectors[2] = MainActor.vote.selector;
        selectors[3] = MainActor.transfer.selector;
        selectors[4] = MainActor.setWinners.selector;
        selectors[5] = MainActor.claim.selector;
        selectors[6] = MainActor.vaultMint.selector;
        selectors[7] = MainActor.recoverClaims.selector;
        selectors[8] = MainActor.setDeadzone.selector;

        targetSelector(FuzzSelector({addr: address(actor), selectors: selectors}));
        targetContract(address(actor));
    }

    // can pay claims
    function invariant_solvency() public view {
        (uint256 maxid, ) = ocmeme.currentEpoch();
        uint256 d = ocmeme.PAYOUT_DENOMINATOR();
        uint256 credits;
        for (uint256 i = 1; i <= maxid; i++) {
            Ocmeme.Epoch memory e = ocmeme.epochs(i);
            uint256 goldClaims = e.claims & (1 << uint8(Ocmeme.ClaimType.GOLD));
            uint256 silverClaims = e.claims & (1 << uint8(Ocmeme.ClaimType.SILVER));
            uint256 bronzeClaims = e.claims & (1 << uint8(Ocmeme.ClaimType.BRONZE));
            uint256 vaultClaims = e.claims & (1 << uint8(Ocmeme.ClaimType.VAULT));

            if (goldClaims == 0) {
                credits += FixedPointMathLib.mulDiv(e.proceeds, ocmeme.GOLD_SHARE(), d);
            }
            if (silverClaims == 0) {
                credits += FixedPointMathLib.mulDiv(e.proceeds, ocmeme.SILVER_SHARE(), d);
            }
            if (bronzeClaims == 0) {
                credits += FixedPointMathLib.mulDiv(e.proceeds, ocmeme.BRONZE_SHARE(), d);
            }
            if (vaultClaims == 0) {
                credits += FixedPointMathLib.mulDiv(e.proceeds, ocmeme.VAULT_SHARE(), d);
            }
        }
        assertTrue(address(ocmeme).balance >= credits);
    }

    // each event.count < max_supply
    function invariant_supply() public view {
        (uint256 maxid, ) = ocmeme.currentEpoch();
        for (uint i = 1; i <= maxid; i++) {
            Ocmeme.Epoch memory e = ocmeme.epochs(i);
            assertTrue(e.count <= ocmeme.SUPPLY_PER_EPOCH());
        }
    }

    // each event.pages.length < max_submissions
    function invariant_pages() public view {
        (uint256 maxid, ) = ocmeme.currentEpoch();
        for (uint i = 1; i <= maxid; i++) {
            uint256[] memory pageIds = ocmeme.submissions(i);
            assertTrue(pageIds.length <= ocmeme.MAX_SUBMISSIONS());
        }
    }

    // sum events.count = tokenid
    function invariant_tokenId() public view {
        uint256 sumCount;
        (uint256 maxid, ) = ocmeme.currentEpoch();
        for (uint i = 1; i <= maxid; i++) {
            Ocmeme.Epoch memory e = ocmeme.epochs(i);
            sumCount += uint256(e.count);
        }
        assertEq(uint256(ocmeme.prevTokenID()), sumCount);
    }

    function invariant_meme_accounting() public view {
        uint256 maxTokenId = ocmeme.prevTokenID();
        address[] memory users = actor.getUsers();

        uint32[] memory emissions = new uint32[](maxTokenId + 1);
        address[] memory owners = new address[](maxTokenId + 1);

        // load token data
        for (uint256 i = 1; i <= maxTokenId; i++) {
            (, uint32 _em, , address _owner) = ocmeme.getMemeData(i);
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

            (uint32 userCount, uint32 userEm, , ) = ocmeme.getUserData(user);
            assertEq(ocCount, userCount);
            assertEq(ocEm, userEm);
        }
    }

    function invariant_user_accounting() public view {
        // users
        address[] memory users = actor.getUsers();
        for (uint256 i; i < users.length; i++) {
            (uint32 count, uint32 em, , ) = ocmeme.getUserData(users[i]);
            assertTrue((count == 0 && em == 0) || em > count);
        }
    }

    function invariant_no_claims() public view {
        uint256[] memory recoveries = actor.getRecoveries();
        for (uint i; i < recoveries.length; i++) {
            Ocmeme.Epoch memory e = ocmeme.epochs(i);
            uint256 goldClaims = e.claims & (1 << uint8(Ocmeme.ClaimType.GOLD));
            uint256 silverClaims = e.claims & (1 << uint8(Ocmeme.ClaimType.SILVER));
            uint256 bronzeClaims = e.claims & (1 << uint8(Ocmeme.ClaimType.BRONZE));
            uint256 vaultClaims = e.claims & (1 << uint8(Ocmeme.ClaimType.VAULT));
            assertTrue(goldClaims > 0);
            assertTrue(silverClaims > 0);
            assertTrue(bronzeClaims > 0);
            assertTrue(vaultClaims == 0);
        }
    }

    function invariant_winners() public view {
        (uint256 maxid, ) = ocmeme.currentEpoch();
        for (uint i = 1; i <= maxid; i++) {
            Ocmeme.Epoch memory e = ocmeme.epochs(i);
            if (e.goldPageID > 0) {
                uint256 gold;
                uint256 silver;
                uint256 bronze;
                uint256 goldIdx;
                uint256 silverIdx;
                uint256 bronzeIdx;
                uint256[] memory pageIDs = ocmeme.submissions(i);
                for (uint256 j; j < pageIDs.length; j++) {
                    Ocmeme.VotePair memory v = ocmeme.votes(j);
                    if (v.votes > gold) {
                        // silver -> bronze
                        bronze = silver;
                        bronzeIdx = silverIdx;
                        // gold -> silver
                        silver = gold;
                        silverIdx = goldIdx;
                        // new gold
                        gold = v.votes;
                        goldIdx = i;
                    } else if (v.votes > silver) {
                        // silver -> bronze
                        bronze = silver;
                        bronzeIdx = silverIdx;

                        // new silver
                        silver = v.votes;
                        silverIdx = i;
                    } else if (v.votes > bronze) {
                        // new bronze
                        bronze = v.votes;
                        bronzeIdx = i;
                    }
                }
                assertEq(e.goldPageID, gold);
                assertEq(e.silverPageID, silver);
                assertEq(e.bronzePageID, bronze);
            }
        }
    }
}
