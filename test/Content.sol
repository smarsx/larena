// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {NFTMeta} from "../src/libraries/NFTMeta.sol";
import {LibString} from "solady/utils/LibString.sol";

contract Content {
    using LibString for uint256;
    NFTMeta.MetaParams[] arr;
    NFTMeta.MetaParams[] invalidarr;
    NFTMeta.MetaParams[] bigarr;

    function setUp() public virtual {
        // img
        {
            arr.push(
                NFTMeta.MetaParams({
                    name: "tim",
                    description: "Privacy is necessary for an open society in the electronic age",
                    typeUri: NFTMeta.TypeURI.IMG,
                    duri: "data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIxMDAiIGhlaWdodD0iMTAwIj48cmVjdCBmaWxsPSIjMDBCMUZGIiB3aWR0aD0iMTAwIiBoZWlnaHQ9IjEwMCIvPjwvc3ZnPg=="
                })
            );
            arr.push(
                NFTMeta.MetaParams({
                    name: "alice",
                    typeUri: NFTMeta.TypeURI.IMG,
                    description: "but the freedom of speech, even more than privacy, is fundamental to an open society; we seek not to restrict any speech at all",
                    duri: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAgAAAAIBAMAAAA2IaO4AAAAFVBMVEXk5OTn5+ft7e319fX29vb5+fn///++GUmVAAAALUlEQVQIHWNICnYLZnALTgpmMGYIFWYIZTA2ZFAzTTFlSDFVMwVyQhmAwsYMAKDaBy0axX/iAAAAAElFTkSuQmCC   "
                })
            );
            arr.push(
                NFTMeta.MetaParams({
                    name: "bob",
                    typeUri: NFTMeta.TypeURI.IMG,
                    description: "The power of electronic communications has enabled such group speech, and it will not go away merely because we might want it to",
                    duri: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABAAAAAQAQMAAAAlPW0iAAAABlBMVEUAAAD///+l2Z/dAAAAM0lEQVR4nGP4/5/h/1+G/58ZDrAz3D/McH8yw83NDDeNGe4Ug9C9zwz3gVLMDA/A6P9/AFGGFyjOXZtQAAAAAElFTkSuQmCC"
                })
            );
            arr.push(
                NFTMeta.MetaParams({
                    name: "sue",
                    description: "Information does not just want to be free, it longs to be free.",
                    typeUri: NFTMeta.TypeURI.IMG,
                    duri: "data:image/png;name=foo.png;base64,iVBORw0KGgoAAAANSUhEUgAAAAgAAAAIBAMAAAA2IaO4AAAAFVBMVEXk5OTn5+ft7e319fX29vb5+fn///++GUmVAAAALUlEQVQIHWNICnYLZnALTgpmMGYIFWYIZTA2ZFAzTTFlSDFVMwVyQhmAwsYMAKDaBy0axX/iAAAAAElFTkSuQmCC"
                })
            );
            arr.push(
                NFTMeta.MetaParams({
                    name: "jim",
                    typeUri: NFTMeta.TypeURI.IMG,
                    description: "Information expands to fill the available storage space.",
                    duri: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAgAAAAIBAMAAAA2IaO4AAAAFVBMVEXk5OTn5+ft7e319fX29vb5+fn///++GUmVAAAALUlEQVQIHWNICnYLZnALTgpmMGYIFWYIZTA2ZFAzTTFlSDFVMwVyQhmAwsYMAKDaBy0axX/iAAAAAElFTkSuQmCC"
                })
            );
            arr.push(
                NFTMeta.MetaParams({
                    name: "tina",
                    typeUri: NFTMeta.TypeURI.IMG,
                    description: "Information is Rumor's younger, stronger cousin; Information is fleeter of foot, has more eyes, knows more, and understands less than Rumor",
                    duri: "data:image/svg+xml;charset=utf-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22100%22%20height%3D%22100%22%3E%3Crect%20fill%3D%22%2300B1FF%22%20width%3D%22100%22%20height%3D%22100%22%2F%3E%3C%2Fsvg%3E"
                })
            );
            arr.push(
                NFTMeta.MetaParams({
                    name: "revtina",
                    description: "Cypherpunks write code.",
                    typeUri: NFTMeta.TypeURI.IMG,
                    duri: "data:image/svg+xml;charset=utf-8;name=bar.svg,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22100%22%20height%3D%22100%22%3E%3Crect%20fill%3D%22%2300B1FF%22%20width%3D%22100%22%20height%3D%22100%22%2F%3E%3C%2Fsvg%3E"
                })
            );
        }

        // animation
        {
            arr.push(
                NFTMeta.MetaParams({
                    name: "revtina",
                    description: "We publish our code so that our fellow Cypherpunks may practice and play with it.",
                    typeUri: NFTMeta.TypeURI.ANIMATION,
                    duri: "data:text/html;charset=US-ASCII,%3Ch1%3EHello World!%3C%2Fh1%3E"
                })
            );
            arr.push(
                NFTMeta.MetaParams({
                    name: "tina",
                    description: "We don't much care if you don't approve of the software we write.",
                    typeUri: NFTMeta.TypeURI.ANIMATION,
                    duri: "data:audio/mp3;base64,%3Ch1%3EHello!%3C%2Fh1%3E"
                })
            );
            arr.push(
                NFTMeta.MetaParams({
                    name: "jim",
                    description: "We know that software can't be destroyed and that a widely dispersed system can't be shut down.",
                    typeUri: NFTMeta.TypeURI.ANIMATION,
                    duri: "data:video/x-ms-wmv;base64,%3Ch1%3EHello!%3C%2Fh1%3E"
                })
            );
            arr.push(
                NFTMeta.MetaParams({
                    name: "sue",
                    description: "Cypherpunks deplore regulations on cryptography, for encryption is fundamentally a private act.",
                    typeUri: NFTMeta.TypeURI.ANIMATION,
                    duri: "data:text/html,<script>alert('hi');</script>"
                })
            );
        }

        // invalid
        {
            invalidarr.push(
                NFTMeta.MetaParams({
                    name: "revtina",
                    description: "Let us proceed together apace \n Onward.",
                    typeUri: NFTMeta.TypeURI.IMG,
                    duri: "dataxbase64"
                })
            );
            invalidarr.push(
                NFTMeta.MetaParams({
                    name: "tina",
                    description: "Agents of chaos cast burning glances at anything or anyone capable of bearing witness to their condition, their fever of lux et voluptas. I am awake only in what I love & desire to the point of terror everything else is just shrouded furniture, quotidian anaesthesia, shit-for-brains, sub-reptilian ennui of totalitarian regimes, banal censorship & useless pain. .",
                    typeUri: NFTMeta.TypeURI.IMG,
                    duri: "data:text/html;charset=,%3Ch1%3EHello!%3C%2Fh1%3E"
                })
            );
            invalidarr.push(
                NFTMeta.MetaParams({
                    name: "jim",
                    description: "Avatars of chaos act as spies, saboteurs, criminals of amour fou, neither selfless nor selfish, accessible as children, mannered as barbarians, chafed with obsessions, unemployed, sensually deranged, wolfangels, mirrors for contemplation, eyes like flowers, pirates of all signs & meanings. .",
                    typeUri: NFTMeta.TypeURI.ANIMATION,
                    duri: "iVBORw0KGgoAAAANSUhEUgAAABAAAAAQAQMAAAAlPW0iAAAABlBMVEUAAAD///+l2Z/dAAAAM0lEQVR4nGP4/5/h/1+G/58ZDrAz3D/McH8yw83NDDeNGe4Ug9C9zwz3gVLMDA/A6P9/AFGGFyjOXZtQAAAAAElFTkSuQmCC"
                })
            );
            invalidarr.push(
                NFTMeta.MetaParams({
                    name: "sue",
                    description: "Here we are crawling the cracks between walls of church state school & factory, all the paranoid monoliths. Cut off from the tribe by feral nostalgia we tunnel after lost words, imaginary bombs. .",
                    typeUri: NFTMeta.TypeURI.ANIMATION,
                    duri: "base64"
                })
            );
        }
    }

    function getImg() public view returns (string memory) {
        return arr[0].duri;
    }

    function getAnimation() public view returns (string memory) {
        return arr[arr.length - 1].duri;
    }

    function getContent(
        uint256 _i,
        NFTMeta.TypeURI _typ
    ) public view returns (NFTMeta.MetaParams memory) {
        NFTMeta.MetaParams[] memory a = _typ == NFTMeta.TypeURI.IMG
            ? getImgContents()
            : getAniContents();

        return a[_i];
    }

    function getImgContents() internal view returns (NFTMeta.MetaParams[] memory) {
        NFTMeta.MetaParams[] memory ret = new NFTMeta.MetaParams[](7);
        uint j = 0;
        for (uint i; i < arr.length; i++) {
            if (arr[i].typeUri == NFTMeta.TypeURI.IMG) {
                ret[j] = arr[i];
                j++;
            }
        }
        return ret;
    }

    function getAniContents() internal view returns (NFTMeta.MetaParams[] memory) {
        NFTMeta.MetaParams[] memory ret = new NFTMeta.MetaParams[](4);
        uint j = 0;
        for (uint i; i < arr.length; i++) {
            if (arr[i].typeUri == NFTMeta.TypeURI.ANIMATION) {
                ret[j] = arr[i];
                j++;
            }
        }
        return ret;
    }

    function getInvalidContent(
        uint256 _i,
        NFTMeta.TypeURI _typ
    ) public view returns (NFTMeta.MetaParams memory) {
        NFTMeta.MetaParams[] memory a = getInvalidContents(_typ);
        return a[_i];
    }

    function getInvalidContents(
        NFTMeta.TypeURI _typ
    ) internal view returns (NFTMeta.MetaParams[] memory) {
        NFTMeta.MetaParams[] memory ret = new NFTMeta.MetaParams[](2);
        uint j = 0;
        for (uint i; i < arr.length; i++) {
            if (invalidarr[i].typeUri == _typ) {
                ret[j] = invalidarr[i];
                j++;
            }
        }
        return ret;
    }

    function getTitle(uint256 _eventID) internal pure returns (string memory _title) {
        _title = string.concat("OCmeme #", _eventID.toString());
    }
}
