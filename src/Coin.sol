// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "solady/tokens/ERC20.sol";

/// @notice ERC20 continiously lazy-emitted by Ocmeme. Used to mint/vote for Pages.
/// @author smarsx.eth
/// @author modified from Art-Gobblers (https://github.com/artgobblers/art-gobblers/blob/master/src/Pages.sol)
contract Coin is ERC20 {
    error Unauthorized();
    address public immutable ocmeme;
    address public immutable pages;

    constructor(address _ocmeme, address _pages) {
        ocmeme = _ocmeme;
        pages = _pages;
    }

    /// @dev Returns the name of the token.
    function name() public view virtual override returns (string memory) {
        return "COIN";
    }

    /// @dev Returns the symbol of the token.
    function symbol() public view virtual override returns (string memory) {
        return "COIN";
    }

    /// @notice Requires caller address to match user address.
    modifier only(address user) {
        if (msg.sender != user) revert Unauthorized();

        _;
    }

    /// @notice Mint any amount of coin to a user. Can only be called by Ocmeme.
    /// @param to The address of the user to mint coin to.
    /// @param amount The amount of coin to mint.
    function mintCoin(address to, uint256 amount) external only(ocmeme) {
        _mint(to, amount);
    }

    /// @notice Burn any amount of coin from a user. Can only be called by Ocmeme.
    /// @param from The address of the user to burn coin from.
    /// @param amount The amount of coin to burn.
    function burnCoin(address from, uint256 amount) external only(ocmeme) {
        _burn(from, amount);
    }

    /// @notice Burn any amount of coin from a user. Can only be called by Pages.
    /// @param from The address of the user to burn coin from.
    /// @param amount The amount of coin to burn.
    function burnForPages(address from, uint256 amount) external only(pages) {
        _burn(from, amount);
    }
}
