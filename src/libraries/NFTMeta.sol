// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Base64} from "solady/utils/Base64.sol";
import {LibString} from "solady/utils/LibString.sol";

/// @title NFTMeta
/// @author smarsx @smarsx
/// @notice Helper functions for encoding/decoding ocmemes data-uris.
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

    /// @notice Construct partial URI with no padding.
    /// @dev constructs URI for sstore2 storage.
    /// @dev rest of URI will be added in render/renderWithTraits.
    /// we leave out the json closing bracket and use no padding to allow addition to json for traits.
    function constructTokenURI(MetaParams memory _params) public pure returns (bytes memory) {
        string memory uriHead = _params.typeUri == TypeURI.IMG
            ? '", "image": "'
            : '", "animation_url": "';

        return
            bytes(
                Base64.encode(
                    abi.encodePacked(
                        '{"name":"',
                        _params.name,
                        '", "description":"',
                        _params.description,
                        uriHead,
                        _params.duri,
                        '"'
                    ),
                    false,
                    // no-padding
                    true
                )
            );
    }

    /// @notice Render content with no added traits.
    /// @dev Decodes provided URI, appends a closing brace, re-encodes the concatenated result
    /// into base64. and prepends the data-uri prefix to form a valid data URI.
    function render(string memory _uri) public pure returns (string memory) {
        bytes memory decodedUri = Base64.decode(_uri);
        return
            string(
                abi.encodePacked(
                    bytes("data:application/json;base64,"),
                    Base64.encode(abi.encodePacked(decodedUri, bytes("}")))
                )
            );
    }

    /// @notice Render content with added traits.
    /// @dev Decode the given base64-encoded URI, concatenate it with the data-uri json prefix
    /// and traits, and then re-encode the result into base64.
    function renderWithTraits(
        uint256 _emissionMultiple,
        string memory _uri
    ) public pure returns (string memory) {
        return
            string(
                abi.encodePacked(
                    bytes("data:application/json;base64,"),
                    Base64.encode(
                        abi.encodePacked(
                            Base64.decode(_uri),
                            abi.encodePacked(
                                ', "attributes": [{ "trait_type": "Emission Multiple", "value": "',
                                _emissionMultiple == 0 ? "0" : _emissionMultiple == 1
                                    ? "1"
                                    : _emissionMultiple == 2
                                    ? "2"
                                    : _emissionMultiple == 3
                                    ? "3"
                                    : _emissionMultiple == 4
                                    ? "4"
                                    : _emissionMultiple == 5
                                    ? "5"
                                    : _emissionMultiple == 6
                                    ? "6"
                                    : "7",
                                '"}]}'
                            )
                        )
                    )
                )
            );
    }

    function constructBaseTokenURI(
        uint256 _idx,
        string memory _title
    ) public pure returns (string memory) {
        string memory svg = generateBaseSvg(_idx);
        return
            string(
                abi.encodePacked(
                    "data:application/json;base64,",
                    Base64.encode(
                        abi.encodePacked(
                            '{"name":"',
                            _title,
                            '", "description":"',
                            _title,
                            '", "image": "data:image/svg+xml;base64,',
                            svg,
                            '"}'
                        )
                    )
                )
            );
    }

    function generateBaseSvg(uint256 _num) public pure returns (string memory) {
        string memory num = string.concat(".", _num.toString());
        return
            Base64.encode(
                abi.encodePacked(
                    '<svg width="400px" height="400px" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"><defs><filter id="bg"><feTurbulence baseFrequency="',
                    num,
                    '"/><feColorMatrix values="0 0 0 9 -4 0 0 0 9 -4 0 0 0 9 -4 0 0 0 0 1"/></filter><linearGradient id="r" x1="0%" y1="0%" x2="100%" y2="100%" gradientUnits="objectBoundingBox"><stop stop-color="#FF6BA8" offset="0%"/><stop stop-color="#FF725E" offset="20%"/><stop stop-color="#FF8A30" offset="40%"/><stop stop-color="#C8FF3D" offset="60%"/><stop stop-color="#30D5C8" offset="80%"/><stop stop-color="#7E57C2" offset="100%"/></linearGradient><linearGradient id="f"><stop offset="0" stop-color="white"/><stop offset="1" stop-color="black"/></linearGradient></defs><rect width="100%" height="100%" filter="url(#bg)"/><g mask="url(#fade-symbol)"><rect fill="none" x="0px" y="0px" width="400px" height="400px" /><text x="200px" y="350px" fill="url(#r)" text-anchor="middle" font-family="\'Courier New\', monospace" font-weight="200" font-size="36px">1|OCMEME</text><path d="M 100 200 200 200 150 100 z" stroke="black" stroke-width="1" fill="url(#f)" transform="scale(.8) translate(100,0)"/><path d="M 100 200 200 200 150 100 z" stroke="url(#r)" stroke-width="1" fill="url(#bg)" transform="scale(.2,-.2) translate(850,-800)"/></g></svg>'
                )
            );
    }
}
