// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DelegatePage} from "../../src/interfaces/DelegatePage.sol";
import {LibString} from "../../src/libraries/LibString.sol";
import {Base64} from "solady/utils/Base64.sol";

contract Delegate is DelegatePage {
    using LibString for uint256;

    /// @notice return data-uri of resource.
    /// @dev "data:image/svg+xml;base64,xxx"
    /// @dev all types of data uri are technically valid, frontend support is not guaranteed.
    function tokenURI() external pure returns (string memory) {
        return
            string(abi.encodePacked("data:image/svg+xml;base64,", Base64.encode(bytes(getSvg()))));
    }

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
    ) external pure returns (string memory) {
        return
            string(
                abi.encodePacked(
                    "data:application/json;base64,",
                    Base64.encode(
                        abi.encodePacked(
                            '{"name":"',
                            getTitle(_epochID),
                            '", "description":"the delegated page.", "image": "data:image/svg+xml;base64,',
                            Base64.encode(bytes(getSvg())),
                            '"}'
                        )
                    )
                )
            );
    }

    function getSvg() internal pure returns (string memory) {
        return
            "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 1 1'><path fill='blue' d='M0,0h1v1H0z'/></svg>";
    }

    function getTitle(uint256 _epochID) internal pure returns (string memory) {
        return string.concat("larena #", _epochID.toString());
    }
}
