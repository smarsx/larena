// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Base64} from "solady/utils/Base64.sol";
import {LibString} from "solady/utils/LibString.sol";

/// @title NFTMeta
/// @author smarsx.eth
/// @notice Helper functions for encoding/decoding larenas data-uris.
library NFTMeta {
    using LibString for uint256;

    enum TypeURI {
        IMG,
        ANIMATION
    }

    struct MetaParams {
        TypeURI typeUri;
        string name;
        string description;
        string duri;
    }

    /// @notice Construct partial URI.
    /// @dev rest of URI will be added in render/renderWithTraits.
    /// @dev 'partial' in this context means missing data-uri prefix and closing json brace.
    function constructTokenURI(MetaParams memory _params) public pure returns (bytes memory) {
        string memory uriHead = _params.typeUri == TypeURI.IMG
            ? '", "image": "'
            : '", "animation_url": "';

        return
            abi.encodePacked(
                '{"name":"',
                _params.name,
                '", "description":"',
                _params.description,
                uriHead,
                _params.duri,
                '"'
            );
    }

    /// @notice Render content with no added traits.
    /// @dev prepends the data-uri prefix and postends closing brace.
    function render(bytes memory _uri) public pure returns (string memory) {
        return
            string(
                abi.encodePacked(
                    "data:application/json;base64,",
                    Base64.encode(abi.encodePacked(_uri, "}"))
                )
            );
    }

    /// @notice Render content with added traits.
    /// @dev prepends data-uri prefix and postends traits and closing brace.
    function renderWithTraits(
        uint256 _emissionMultiple,
        bytes memory _uri
    ) public pure returns (string memory) {
        return
            string(
                abi.encodePacked(
                    "data:application/json;base64,",
                    Base64.encode(
                        abi.encodePacked(
                            _uri,
                            ', "attributes": [{ "trait_type": "Emission Multiple", "value": "',
                            _emissionMultiple.toString(),
                            '"}]}'
                        )
                    )
                )
            );
    }
}
