// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {DeployBase} from "./DeployBase.s.sol";

contract DeployTestnet is DeployBase {
    address public immutable coldWallet = vm.envAddress("COLDWALLET_ADDRESS");
    uint256 public immutable pageStart = block.timestamp - 365 days;

    constructor() DeployBase(coldWallet, pageStart) {}
}
