// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "forge-std/Script.sol";

import {LibRLP} from "../../test/utils/LibRLP.sol";

import {Reserve} from "../../src/utils/Reserve.sol";

import {Coin} from "../../src/Coin.sol";
import {Pages} from "../../src/Pages.sol";
import {Ocmeme} from "../../src/Ocmeme.sol";

abstract contract DeployBase is Script {
    address private immutable coldWallet;
    uint256 private immutable pageStart;
    uint256 private immutable ocmemeStart;

    // deploy addresses
    Coin public coin;
    Pages public pages;
    Ocmeme public ocmeme;
    Reserve public reserve;

    constructor(address _coldWallet, uint256 _pageStart) {
        coldWallet = _coldWallet;
        pageStart = _pageStart;
    }

    // cold wallet is owner of reserve & ocmeme contracts
    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        uint256 ocmemeKey = vm.envUint("OCMEME_PRIVATE_KEY");
        uint256 pagesKey = vm.envUint("PAGES_PRIVATE_KEY");
        uint256 coinKey = vm.envUint("COIN_PRIVATE_KEY");

        address ocmemeDeployerAddress = vm.addr(ocmemeKey);
        address pagesDeployerAddress = vm.addr(pagesKey);
        address coinDeployerAddress = vm.addr(coinKey);

        // precompute contract addresses, based on contract deploy nonces
        address ocmemeAddress = LibRLP.computeAddress(ocmemeDeployerAddress, 0);
        address pageAddress = LibRLP.computeAddress(pagesDeployerAddress, 0);
        address coinAddress = LibRLP.computeAddress(coinDeployerAddress, 0);

        vm.startBroadcast(deployerKey);

        // deploy reserve vault, owned by cold wallet
        reserve = new Reserve(
            Ocmeme(ocmemeAddress),
            Pages(pageAddress),
            Coin(coinAddress),
            coldWallet
        );

        // fund deployer addresses
        payable(ocmemeDeployerAddress).transfer(0.2 ether);
        payable(pagesDeployerAddress).transfer(0.1 ether);
        payable(coinDeployerAddress).transfer(0.1 ether);

        vm.stopBroadcast();

        // deploy coin
        vm.startBroadcast(coinKey);
        coin = new Coin(ocmemeAddress, pageAddress);
        if (address(coin) != coinAddress) revert("err computed address");
        vm.stopBroadcast();

        // deploy ocmeme
        vm.startBroadcast(ocmemeKey);
        ocmeme = new Ocmeme(Coin(coinAddress), Pages(pageAddress), address(reserve));
        if (address(ocmeme) != ocmemeAddress) revert("err computed address");
        ocmeme.transferOwnership(coldWallet);
        vm.stopBroadcast();

        // deploy pages
        vm.startBroadcast(pagesKey);
        pages = new Pages(pageStart, Coin(coinAddress), address(reserve), Ocmeme(ocmemeAddress));
        if (address(pages) != pageAddress) revert("err computed address");
        vm.stopBroadcast();
    }
}
