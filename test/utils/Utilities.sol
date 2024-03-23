// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Vm} from "forge-std/Vm.sol";
import {LibRLP} from "./LibRLP.sol";

contract Utilities {
    bytes32 internal nextUser = keccak256(abi.encodePacked("user address"));

    function getNextUserAddress() external returns (address payable) {
        // bytes32 to address conversion
        address payable user = payable(address(uint160(uint256(nextUser))));
        nextUser = keccak256(abi.encodePacked(nextUser));
        return user;
    }

    // create users with 100 ether balance
    function createUsers(uint256 userNum, Vm _vm) external returns (address payable[] memory) {
        address payable[] memory users = new address payable[](userNum);
        for (uint256 i = 0; i < userNum; ++i) {
            address payable user = this.getNextUserAddress();
            _vm.deal(user, 100 ether);
            users[i] = user;
        }
        return users;
    }

    function predictContractAddress(
        address user,
        uint256 distanceFromCurrentNonce,
        Vm _vm
    ) external view returns (address) {
        return LibRLP.computeAddress(user, _vm.getNonce(user) + distanceFromCurrentNonce);
    }
}
