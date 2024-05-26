// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface UnrevealedURI {
    function tokenUri(uint256 _epochID, uint256 _index) external view returns (string memory);
}
