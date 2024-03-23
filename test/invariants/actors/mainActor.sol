// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ocmeme} from "../../../src/Ocmeme.sol";
import {Goo} from "../../../src/Goo.sol";
import {Pages} from "../../../src/Pages.sol";
import {Reserve} from "../../../src/utils/Reserve.sol";
import {NFTMeta} from "../../../src/libraries/NFTMeta.sol";
import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {console2 as console} from "forge-std/console2.sol";

contract MainActor is CommonBase, StdCheats, StdUtils {
    Ocmeme ocmeme;
    Pages pages;
    Goo goo;
    Reserve reserve;

    address[] users = [
        address(uint160(1111)),
        address(uint160(2222)),
        address(uint160(3333)),
        address(uint160(4444)),
        address(uint160(5555)),
        address(uint160(6666)),
        address(uint160(7777)),
        address(uint160(8888)),
        address(uint160(9999)),
        address(uint160(1112))
    ];

    uint256[] internal recoveries;
    uint256[] internal pageIds;
    uint256 internal currentPageID;
    address internal currentUser;
    address internal otherUser;

    mapping(bytes32 => uint256) public calls;
    mapping(address => uint256[]) public ocOwner;

    modifier useUser(uint256 _seed) {
        currentUser = users[_seed % users.length];
        _;
    }

    modifier usePage(uint256 _seed) {
        if (pageIds.length > 0) {
            currentPageID = pageIds[_seed % pageIds.length];
        } else {
            currentPageID = 0;
        }
        _;
    }

    // get non-current-user
    modifier useOtherUser(uint256 _seed) {
        uint256 index = _seed % users.length;
        if (index == users.length) {
            otherUser = address(0);
        } else {
            uint256 newIndex = (index + 1) % users.length;
            otherUser = users[newIndex];
        }
        _;
    }

    modifier countCall(bytes32 _key) {
        calls[_key]++;
        _;
    }

    constructor(Ocmeme _ocmeme, Pages _pages, Goo _goo, Reserve _reserve) {
        ocmeme = _ocmeme;
        pages = _pages;
        goo = _goo;
        reserve = _reserve;
    }

    function mint(uint256 _seed) public virtual useUser(_seed) countCall("mint") {
        uint256 price = ocmeme.getPrice();
        vm.deal(currentUser, price * 2);
        vm.prank(currentUser);
        // this shouldn't effect any accounting because it will get refunded.
        ocmeme.mint{value: price * 2}();
        ocOwner[currentUser].push(ocmeme.prevTokenID());
    }

    function vote(uint256 _seed) public virtual useUser(_seed) usePage(_seed) countCall("vote") {
        uint256 amt = uint32(_seed);
        vm.prank(address(ocmeme));
        goo.mintGoo(currentUser, amt);

        vm.prank(currentUser);
        ocmeme.vote(currentPageID, amt, false);
    }

    function submit(uint256 _seed) public virtual useUser(_seed) countCall("submit") {
        uint256 price = pages.pagePrice();
        uint256 bal = ocmeme.gooBalance(currentUser);
        bool useVirtual = _seed % 2 == 0;

        if (bal < price) {
            vm.prank(address(ocmeme));
            goo.mintGoo(currentUser, price);
            if (useVirtual) {
                vm.prank(currentUser);
                ocmeme.addGoo(price);
            }
        } else {
            // vbalance > price
            if (!useVirtual) {
                // withdrawal
                vm.prank(currentUser);
                ocmeme.removeGoo(price);
            }
        }

        vm.prank(currentUser);
        uint256 pageID = pages.mintFromGoo(price, useVirtual);
        vm.prank(currentUser);
        ocmeme.submit(pageID, 1, NFTMeta.TypeURI(0), "", "");
        pageIds.push(pageID);
    }

    function setWinners(uint256 _seed) public virtual countCall("setWinners") {
        vm.warp(block.timestamp + (1 days * (_seed % 20)));
        if (_seed % 5 == 0) {
            ocmeme.crownWinners();
        }
    }

    function transfer(
        uint256 _seed
    ) public virtual useUser(_seed) useOtherUser(_seed) countCall("transfer") {
        uint256[] memory tokens = ocOwner[currentUser];
        (uint256 _count, , , ) = ocmeme.getUserData(currentUser);
        if (_count > 0) {
            // load token were about to pop
            uint256 token = tokens[_count - 1];
            ocOwner[currentUser].pop();
            // add token to otheruser
            ocOwner[otherUser].push(token);
            // transfer
            vm.prank(currentUser);
            ocmeme.transferFrom(currentUser, otherUser, token);
        }
    }

    function vaultMint(uint256 _seed) public virtual countCall("vaultMint") {
        if (_seed % 10 == 0) {
            ocmeme.vaultMint();
        }
    }

    function claim(uint256 _seed) public virtual countCall("claim") {
        (uint256 maxEventID, ) = ocmeme.currentEpoch();
        uint256 eventID = _seed % maxEventID;
        if (eventID > 0) {
            uint256 claimType = _seed % 3;
            Ocmeme.Epoch memory e = ocmeme.epochs(eventID);
            if (e.goldPageID > 0) {
                if (claimType == 0) {
                    address owner = pages.ownerOf(e.goldPageID);
                    vm.prank(owner);
                    ocmeme.claimGold(eventID);
                } else if (claimType == 1) {
                    address owner = pages.ownerOf(e.silverPageID);
                    vm.prank(owner);
                    ocmeme.claimSilver(eventID);
                } else if (claimType == 2) {
                    address owner = pages.ownerOf(e.bronzePageID);
                    vm.prank(owner);
                    ocmeme.claimBronze(eventID);
                }
            }
        }
    }

    function recoverClaims() public virtual countCall("recover") {
        (uint256 epochID, ) = ocmeme.currentEpoch();
        for (uint i = 1; i < epochID; i++) {
            bool found;
            for (uint j; j < recoveries.length; j++) {
                if (recoveries[j] == i) {
                    found = true;
                    break;
                }
            }
            if (found) continue;

            uint256 estart = ocmeme.epochStart(i);
            if (estart + ocmeme.RECOVERY_PERIOD() < block.timestamp) {
                vm.prank(ocmeme.owner());
                ocmeme.recoverPayout(i);
                recoveries.push(i);
            } else {
                break;
            }
        }
    }

    function setDeadzone() public virtual countCall("deadzone") {
        ocmeme.setVoteDeadzone();
    }

    function getUsers() public view returns (address[] memory) {
        address[] memory u = new address[](users.length);
        for (uint256 i; i < users.length; i++) {
            u[i] = users[i];
        }
        return u;
    }

    function getRecoveries() public view returns (uint256[] memory) {
        return recoveries;
    }

    fallback() external payable {}

    receive() external payable {}
}
