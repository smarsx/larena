# larena

On-chain user-generated autonomous art competition.
Inspired by art-gobblers, basepaint, and inscriptions.
Proceeds are paid to top-voted pages.

Live at app.larena.io

## Deployments

| Network       | Address                                                                           |
| ------------- | --------------------------------------------------------------------------------- |
| Base          |[0x000000000005b7e7a344d73d7a1f0b6bb89ff355](https://basescan.org/address/0x000000000005b7e7a344d73d7a1f0b6bb89ff355)|
| Base-sepolia  |[0x000000000005b7e7a344d73d7a1f0b6bb89ff355](https://basescan.org/address/0x000000000005b7e7a344d73d7a1f0b6bb89ff355)|

## Note

This document is not a complete or exhaustive source. At this moment the best source of information is the contracts themselves. Most of the logic is in larena.sol.

## Epoch

- a continuous loop of 30-day epochs create the submit/vote/crown_winner loop
- once an epoch has concluded, votes are tallied, winning pages are crowned, and submitting/voting is opened for the next epoch

## Tokens

### larena

- ERC-721 priced on logistic-to-linear [VRGDA](https://www.paradigm.xyz/2022/08/vrgda#logistic-issuance-schedule) curve
- around epoch 42 curve switches to linear, limiting supply to 10 per epoch (120/year) for eternity
- minted with ether
- continuous lazy $COIN emission (see $COIN)
- when the winning page is crowned, larena's metadata is inherited from this page
![larena supply](/assets/larena%20supply.png)

### pages

- ERC-721 priced on linear [VRGDA](https://www.paradigm.xyz/2022/08/vrgda#linear) curve
- minted with $COIN
- allows a single submission
- stores metadata: royalty & sstore2 pointer to onchain data-uri

### coin

- ERC-20 using [Gradual Ownership Optimization](https://www.paradigm.xyz/2022/09/goo)
- $COIN is lazily emitted by larena's based on their emission multiple
- use $COIN to vote on and mint $PAGES

## Actions
- Mint
- Submit
- Vote
- Claim

*code shown below is an approximation*

### Mint

```solidity
function mint() external payable {
    (uint256 epochID, uint256 epochStart) = currentEpoch();
    uint256 price = _getPrice(epochStart, count);
    if (msg.value < price) revert InsufficientFunds();

    $epochs[epochID].proceeds += price;

    _mint(msg.sender, ++$prevTokenID, epochID, ++count);

    // refund ether sent > price
    SafeTransferLib.safeTransferETH(msg.sender, msg.value - price);
}
```

- main entry point to larena
- minting a larena gives you a constant emission of $COIN, which is then used to mint and vote on $PAGES
- when epoch concludes tokenURI is inherited from top-voted page
- any funds paid > price are auto-refunded
- minting is available 24/7, price will modulate supply based on VRGDA parameters

### Submit

```solidity
/// @notice Submit page to an epoch.
/// @param _pageID Page token to use.
/// @param _royalty Royalty in basis points.
/// @param _typeUri Data key in tokenuri output.
/// @param _description Description in tokenuri output.
/// @param _duri DataURI value.
function submit(
    uint256 _pageID,
    uint256 _royalty,
    NFTMeta.TypeURI _typeUri,
    string calldata _description,
    string calldata _duri
) external {
    ...
    address pointer = SSTORE2.write(
        NFTMeta.constructTokenURI(..., _duri, _description)
    );
    $pages.setMetadata(_pageID, _royalty, pointer);
    $submissions[currentEpoch].push(_pageID);
    ...
}
```

- an unused $PAGES token is required to make a submission
- max 100 submissions per epoch
- top 3 submissions ranked by votes are crowned winners at conclusion of epoch
- larena tokenURI & royalty are inherited from top-voted submission

- _duri: any valid [data-uri](https://developer.mozilla.org/en-US/docs/Web/HTTP/Basics_of_HTTP/Data_URLs)
- _typeURI (image(0) or animation(1)) - choose data key in tokenURI json. 
    - {name: "", description: "", **image**: ""} 
    - vs.
    - {name: "", description: "", **animation_url**: ""}

### Submit Delegate
```solidity
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

/// @notice Submit delegate page to an epoch.
/// @param _pageID Page token to use.
/// @param _royalty Royalty in basis points.
/// @param _pointer Delegate page contract. Must implement DelegatePage interface.
function submitDelegate(uint256 _pageID, uint256 _royalty, address _pointer) {
    ...
    $pages.setMetadata(_pageID, _royalty, _pointer, true);
    $submissions[epochID].push(_pageID);
    ...
}
```

- instead of directly submitting a data-uri for a page, submit an address that implements DelegatePage interface.
- this allows not just onchain data-uri's but generative work as well.
- not available through UI (in-progress) but contracts are deployed so go crazy

### Vote

- use $COIN to vote on $PAGES
- voting burns $COIN used
- in the hours preceeding end of epoch, there is a penalty applied to votes.

### Claim

- once epoch is concluded the owners of top-voted $PAGES can claim their winnings.
- Gold: 85%
- Silver: 8%
- Bronze: 4%
- Protocol: 3%

## Disclaimer
This is dangerous unaudited code.
chaos never died, this is not a meme, i love you ❣
