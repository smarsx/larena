// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Owned} from "solmate/auth/Owned.sol";

import {Ocmeme} from "../Ocmeme.sol";
import {Pages} from "../Pages.sol";
import {Goo} from "../Goo.sol";

interface IERC20 {
    function transfer(address recipient, uint256 amount) external returns (bool);

    function balanceOf(address account) external view returns (uint256);
}

contract Reserve is Owned {
    Ocmeme public immutable ocmeme;
    Pages public immutable pages;
    Goo public immutable goo;

    constructor(Ocmeme _ocmeme, Pages _pages, Goo _goo, address _owner) Owned(_owner) {
        ocmeme = _ocmeme;
        pages = _pages;
        goo = _goo;
    }

    function withdrawalOcmeme(address _to, uint256[] calldata _ids) external onlyOwner {
        unchecked {
            for (uint256 i; i < _ids.length; ++i) {
                ocmeme.transferFrom(address(this), _to, _ids[i]);
            }
        }
    }

    function withdrawalPage(address _to, uint256 _id) external onlyOwner {
        pages.transferFrom(address(this), _to, _id);
    }

    function withdrawalGoo(address _to, uint256 _goo) external onlyOwner {
        ocmeme.removeGoo(_goo);
        goo.transfer(_to, _goo);
    }

    function withdrawalToken(address _token, address _to, uint256 _amt) external onlyOwner {
        require(IERC20(_token).balanceOf(address(this)) >= _amt, "Insufficient balance");
        bool sent = IERC20(_token).transfer(_to, _amt);
        require(sent, "Token transfer failed");
    }

    function withdrawalEth(address payable _to, uint256 _amt) external onlyOwner {
        require(address(this).balance >= _amt, "Insufficient balance");
        _to.transfer(address(this).balance);
    }

    receive() external payable {}

    fallback() external payable {}
}
