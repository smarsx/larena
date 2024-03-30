// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "solady/tokens/ERC20.sol";

/// @notice ERC20 continiously lazy-emitted by Ocmeme. Used to mint/vote for Pages.
/// @author smarsx.eth
/// @author modified from Art-Gobblers (https://github.com/artgobblers/art-gobblers/blob/master/src/Pages.sol)
contract Goo is ERC20 {
    error Unauthorized();
    address public immutable ocmeme;
    address public immutable pages;

    constructor(address _ocmeme, address _pages) {
        ocmeme = _ocmeme;
        pages = _pages;
    }

    /// @dev Returns the name of the token.
    function name() public view virtual override returns (string memory) {
        return "GOO";
    }

    /// @dev Returns the symbol of the token.
    function symbol() public view virtual override returns (string memory) {
        return "GOO";
    }

    /// @notice Requires caller address to match user address.
    modifier only(address user) {
        if (msg.sender != user) revert Unauthorized();

        _;
    }

    /// @notice Mint any amount of goo to a user. Can only be called by Ocmeme.
    /// @param to The address of the user to mint goo to.
    /// @param amount The amount of goo to mint.
    function mintGoo(address to, uint256 amount) external only(ocmeme) {
        _mint(to, amount);
    }

    /// @notice Burn any amount of goo from a user. Can only be called by Ocmeme.
    /// @param from The address of the user to burn goo from.
    /// @param amount The amount of goo to burn.
    function burnGoo(address from, uint256 amount) external only(ocmeme) {
        _burn(from, amount);
    }

    /// @notice Burn any amount of goo from a user. Can only be called by Pages.
    /// @param from The address of the user to burn goo from.
    /// @param amount The amount of goo to burn.
    function burnForPages(address from, uint256 amount) external only(pages) {
        _burn(from, amount);
    }
}
