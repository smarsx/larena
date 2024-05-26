// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Larena} from "../../../src/Larena.sol";
import {Coin} from "../../../src/Coin.sol";
import {Pages} from "../../../src/Pages.sol";
import {Reserve} from "../../../src/utils/Reserve.sol";
import {NFTMeta} from "../../../src/libraries/NFTMeta.sol";
import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {console2 as console} from "forge-std/console2.sol";
import {Interfaces} from "../../utils/Interfaces.sol";

contract MainActor is CommonBase, StdCheats, StdUtils, Interfaces {
    Larena larena;
    Pages pages;
    Coin coin;
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

    constructor(Larena _larena, Pages _pages, Coin _coin, Reserve _reserve) {
        larena = _larena;
        pages = _pages;
        coin = _coin;
        reserve = _reserve;
    }

    function mint(uint256 _seed) public virtual useUser(_seed) countCall("mint") {
        uint256 price = larena.getPrice();
        vm.deal(currentUser, price * 2);
        vm.prank(currentUser);
        // this shouldn't effect any accounting because it will get refunded.
        larena.mint{value: price * 2}();
        ocOwner[currentUser].push(larena.$prevTokenID());
    }

    function vote(uint256 _seed) public virtual useUser(_seed) usePage(_seed) countCall("vote") {
        uint256 amt = uint32(_seed);
        vm.prank(address(larena));
        coin.mintCoin(currentUser, amt);

        vm.prank(currentUser);
        larena.vote(currentPageID, amt, false);
    }

    function submit(uint256 _seed) public virtual useUser(_seed) countCall("submit") {
        uint256 price = pages.pagePrice();
        uint256 bal = larena.coinBalance(currentUser);
        bool useVirtual = _seed % 2 == 0;

        if (bal < price) {
            vm.prank(address(larena));
            coin.mintCoin(currentUser, price);
            if (useVirtual) {
                vm.prank(currentUser);
                larena.addCoin(price);
            }
        } else {
            // vbalance > price
            if (!useVirtual) {
                // withdrawal
                vm.prank(currentUser);
                larena.removeCoin(price);
            }
        }

        vm.prank(currentUser);
        uint256 pageID = pages.mintFromCoin(price, useVirtual);
        vm.prank(currentUser);
        larena.submit(pageID, 1, NFTMeta.TypeURI(0), "", "");
        pageIds.push(pageID);
    }

    function setWinners(uint256 _seed) public virtual countCall("setWinners") {
        vm.warp(block.timestamp + (1 days * (_seed % 20)));
        if (_seed % 5 == 0) {
            larena.crownWinners();
        }
    }

    function transfer(
        uint256 _seed
    ) public virtual useUser(_seed) useOtherUser(_seed) countCall("transfer") {
        uint256[] memory tokens = ocOwner[currentUser];
        (uint256 _count, , , ) = larena.getUserData(currentUser);
        if (_count > 0) {
            // load token were about to pop
            uint256 token = tokens[_count - 1];
            ocOwner[currentUser].pop();
            // add token to otheruser
            ocOwner[otherUser].push(token);
            // transfer
            vm.prank(currentUser);
            larena.transferFrom(currentUser, otherUser, token);
        }
    }

    function vaultMint(uint256 _seed) public virtual countCall("vaultMint") {
        if (_seed % 10 == 0) {
            larena.vaultMint();
        }
    }

    function claim(uint256 _seed) public virtual countCall("claim") {
        (uint256 maxepochID, ) = larena.currentEpoch();
        uint256 epochID = _seed % maxepochID;
        if (epochID > 0) {
            uint256 claimType = _seed % 3;
            Larena.Epoch memory e = getEpochs(epochID, larena);
            if (e.goldPageID > 0) {
                if (claimType == 0) {
                    address owner = pages.ownerOf(e.goldPageID);
                    vm.prank(owner);
                    larena.claim(epochID, Larena.ClaimType.GOLD);
                } else if (claimType == 1) {
                    address owner = pages.ownerOf(e.silverPageID);
                    vm.prank(owner);
                    larena.claim(epochID, Larena.ClaimType.SILVER);
                } else if (claimType == 2) {
                    address owner = pages.ownerOf(e.bronzePageID);
                    vm.prank(owner);
                    larena.claim(epochID, Larena.ClaimType.BRONZE);
                }
            }
        }
    }

    function recoverClaims() public virtual countCall("recover") {
        (uint256 epochID, ) = larena.currentEpoch();
        for (uint i = 1; i < epochID; i++) {
            bool found;
            for (uint j; j < recoveries.length; j++) {
                if (recoveries[j] == i) {
                    found = true;
                    break;
                }
            }
            if (found) continue;

            uint256 estart = larena.epochStart(i);
            if (estart + larena.RECOVERY_PERIOD() < block.timestamp) {
                vm.prank(larena.owner());
                larena.recoverPayout(i);
                recoveries.push(i);
            } else {
                break;
            }
        }
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
