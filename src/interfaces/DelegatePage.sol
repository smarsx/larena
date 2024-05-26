// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @dev example impl in test/utils/DelegatePage
interface DelegatePage {
    /// @notice return data-uri of resource.
    /// @dev "data:image/svg+xml;base64,xxx"
    /// @dev used in Pages.tokenURI
    function tokenUri() external view returns (string memory);

    /// @notice return data-uri with metadata and traits.
    /// @dev expected to be data-uri of type data:application/json;base64
    /// @dev required fields: name, description, attributes, image and/or animation_url
    /// @dev required attributes: emissionMultiple
    /// @dev prefer name to be "larena #{_epochID}"
    /// @dev used in larena.tokenURI when Page is the epochs winner (Gold).
    /// @dev for further info on params see src/utils/token/LarenaERC721.sol:LarenaData
    /// @param epochID epoch of the respective larena.
    /// @param emissionMultiple rate at which larena emits Coin.
    /// @param index inner-epoch ID.
    function tokenUri(
        uint256 epochID,
        uint256 emissionMultiple,
        uint256 index
    ) external view returns (string memory);
}
