// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "forge-std/Script.sol";

import {LibRLP} from "../../test/utils/LibRLP.sol";

import {Reserve} from "../../src/utils/Reserve.sol";
import {Unrevealed} from "../../src/utils/Unrevealed.sol";

import {Coin} from "../../src/Coin.sol";
import {Pages} from "../../src/Pages.sol";
import {Larena} from "../../src/Larena.sol";

abstract contract DeployBase is Script {
    address private immutable coldWallet;
    uint256 private immutable pageStart;
    uint256 private immutable larenaStart;

    // deploy addresses
    Coin public coin;
    Pages public pages;
    Larena public larena;
    Reserve public reserve;
    Unrevealed public unrevealed;

    constructor(address _coldWallet, uint256 _pageStart) {
        coldWallet = _coldWallet;
        pageStart = _pageStart;
    }

    // cold wallet is owner of reserve & larena contracts
    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        uint256 larenaKey = vm.envUint("LARENA_PRIVATE_KEY");
        uint256 pagesKey = vm.envUint("PAGES_PRIVATE_KEY");
        uint256 coinKey = vm.envUint("COIN_PRIVATE_KEY");

        address larenaDeployerAddress = vm.addr(larenaKey);
        address pagesDeployerAddress = vm.addr(pagesKey);
        address coinDeployerAddress = vm.addr(coinKey);

        // precompute contract addresses, based on contract deploy nonces
        address larenaAddress = LibRLP.computeAddress(larenaDeployerAddress, 0);
        address pageAddress = LibRLP.computeAddress(pagesDeployerAddress, 0);
        address coinAddress = LibRLP.computeAddress(coinDeployerAddress, 0);

        vm.startBroadcast(deployerKey);

        // deploy reserve vault, owned by cold wallet
        reserve = new Reserve(
            Larena(larenaAddress),
            Pages(pageAddress),
            Coin(coinAddress),
            coldWallet
        );

        unrevealed = new Unrevealed();

        // fund deployer addresses
        // payable(larenaDeployerAddress).transfer(0.2 ether);
        // payable(pagesDeployerAddress).transfer(0.1 ether);
        // payable(coinDeployerAddress).transfer(0.1 ether);

        vm.stopBroadcast();

        // deploy coin
        vm.startBroadcast(coinKey);
        coin = new Coin(larenaAddress, pageAddress);
        if (address(coin) != coinAddress) revert("err computed address");
        vm.stopBroadcast();

        // deploy larena
        vm.startBroadcast(larenaKey);
        larena = new Larena(Coin(coinAddress), Pages(pageAddress), unrevealed, address(reserve));
        if (address(larena) != larenaAddress) revert("err computed address");
        larena.transferOwnership(coldWallet);
        vm.stopBroadcast();

        // deploy pages
        vm.startBroadcast(pagesKey);
        pages = new Pages(pageStart, Coin(coinAddress), address(reserve), Larena(larenaAddress));
        if (address(pages) != pageAddress) revert("err computed address");
        vm.stopBroadcast();
    }
}
