// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Vm} from "forge-std/Vm.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Base64} from "solady/utils/Base64.sol";
import {LibString} from "solady/utils/LibString.sol";

import {NFTMeta} from "../../src/libraries/NFTMeta.sol";

contract Decoder {
    using stdJson for string;
    using LibString for string;
    using LibString for uint256;

    struct DecodedContent {
        uint32 emissionMultiple;
        string name;
        string description;
        string content;
    }

    function getTempJsonPath(Vm _vm, uint256 _idx) public view returns (string memory) {
        // file-ending so tests have diff file.
        return string.concat(_vm.projectRoot(), "/temp/temp", _idx.toString(), ".json");
    }

    function decodeContent(
        bool _hasTraits,
        NFTMeta.TypeURI _typ,
        uint256 _fileEnding,
        Vm _vm,
        string memory _uri
    ) external returns (DecodedContent memory) {
        string memory tempjson = getTempJsonPath(_vm, _fileEnding);

        string memory decodedUri = string(Base64.decode(_uri.slice(29)));

        // write / read
        _vm.writeJson(decodedUri, tempjson);
        string memory json = _vm.readFile(tempjson);

        // decode
        string memory dname = abi.decode(json.parseRaw(".name"), (string));
        string memory ddescription = abi.decode(json.parseRaw(".description"), (string));
        string memory dcontent = abi.decode(
            json.parseRaw(_typ == NFTMeta.TypeURI.IMG ? ".image" : ".animation_url"),
            (string)
        );
        // extract attribute
        uint32 emissionMultiple = _hasTraits ? pyEmissionMultiple(_vm, tempjson) : 0;

        return
            DecodedContent({
                emissionMultiple: emissionMultiple,
                name: dname,
                description: ddescription,
                content: dcontent
            });
    }

    function pyEmissionMultiple(Vm _vm, string memory _path) private returns (uint32) {
        string[] memory inputs = new string[](5);
        inputs[0] = "python3";
        inputs[1] = "analysis/get_attributes.py";
        inputs[2] = "emissionMultiple";
        inputs[3] = "--path";
        inputs[4] = _path;

        return abi.decode(_vm.ffi(inputs), (uint32));
    }

    function pyStrings(
        Vm _vm,
        string memory _path,
        string memory _key
    ) private returns (string memory) {
        string[] memory inputs = new string[](5);
        inputs[0] = "python3";
        inputs[1] = "analysis/get_attributes.py";
        inputs[2] = _key;
        inputs[3] = "--path";
        inputs[4] = _path;

        return string(bytes(_vm.ffi(inputs)));
    }
}
