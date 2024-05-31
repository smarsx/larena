// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @dev example impl in test/utils/DelegatePage
interface DelegatePage {
    /// @notice return data-uri of resource.
    /// @dev "data:image/svg+xml;base64,xxx"
    /// @dev all types of data uri are technically valid, frontend support is not guaranteed.
    function tokenURI() external pure returns (string memory);

    /// @notice return data-uri with metadata.
    /// @dev data:application/json;base64
    /// @dev required fields: name, description, image and/or animation_url
    /// @dev prefer name to be "larena #{_epochID}"
    /// @dev for further info on params see src/utils/token/LarenaERC721.sol:LarenaData
    /// @param _epochID epoch of the respective larena.
    /// @param _emissionMultiple rate at which larena emits Coin.
    /// @param _index inner-epoch ID.
    function tokenURI(
        uint256 _epochID,
        uint256 _emissionMultiple,
        uint256 _index
    ) external pure returns (string memory);
}
