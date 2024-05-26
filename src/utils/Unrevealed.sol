// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Base64} from "solady/utils/Base64.sol";
import {LibString} from "solady/utils/LibString.sol";
import {UnrevealedURI} from "../interfaces/UnrevealedURI.sol";

contract Unrevealed is UnrevealedURI {
    using LibString for uint256;

    function tokenUri(uint256 _epochID, uint256 _index) external pure returns (string memory) {
        string memory title = string.concat("larena #", _epochID.toString());
        string memory svg = generateBaseSvg(_index);
        return
            string(
                abi.encodePacked(
                    "data:application/json;base64,",
                    Base64.encode(
                        abi.encodePacked(
                            '{"name":"',
                            title,
                            '", "description":"',
                            title,
                            '", "image": "data:image/svg+xml;base64,',
                            svg,
                            '"}'
                        )
                    )
                )
            );
    }

    function generateBaseSvg(uint256 _num) internal pure returns (string memory) {
        string memory pre = _num < 500 ? ".00" : _num < 5000 ? ".0" : ".";
        bytes memory num = abi.encodePacked(pre, _num.toString());
        return
            Base64.encode(
                abi.encodePacked(
                    '<svg width="400px" height="400px" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"><defs><filter id="bg"><feTurbulence baseFrequency="',
                    num,
                    '"/><feColorMatrix values="0 0 0 9 -4 0 0 0 9 -4 0 0 0 9 -4 0 0 0 0 1"/></filter><linearGradient id="r" x1="0%" y1="0%" x2="100%" y2="100%" gradientUnits="objectBoundingBox"><stop stop-color="#FF6BA8" offset="0%"/><stop stop-color="#FF725E" offset="20%"/><stop stop-color="#FF8A30" offset="40%"/><stop stop-color="#C8FF3D" offset="60%"/><stop stop-color="#30D5C8" offset="80%"/><stop stop-color="#7E57C2" offset="100%"/></linearGradient><linearGradient id="f"><stop offset="0" stop-color="white"/><stop offset="1" stop-color="black"/></linearGradient></defs><rect width="100%" height="100%" filter="url(#bg)"/><g mask="url(#fade-symbol)"><rect fill="none" x="0px" y="0px" width="400px" height="400px" /><text x="200px" y="350px" fill="url(#r)" text-anchor="middle" font-family="\'Courier New\', monospace" font-weight="200" font-size="36px">1|larena</text><path d="M 100 200 200 200 150 100 z" stroke="black" stroke-width="1" fill="url(#f)" transform="scale(.8) translate(100,0)"/><path d="M 100 200 200 200 150 100 z" stroke="url(#r)" stroke-width="1" fill="url(#bg)" transform="scale(.2,-.2) translate(850,-800)"/></g></svg>'
                )
            );
    }
}
