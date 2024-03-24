# OCmeme

On-chain user-generated autonomous art competition.
Inspired by art-gobblers, basepaint, and inscriptions.
Proceeds are paid to top-voted pages.

Live at ocmeme.com

## Deployments

| Network       | Address                                                                           |
| ------------- | --------------------------------------------------------------------------------- |
| Base          |[0x000000000005b7e7a344d73d7a1f0b6bb89ff355](https://basescan.org/address/0x000000000005b7e7a344d73d7a1f0b6bb89ff355)|
| Base-sepolia  |[0x000000000005b7e7a344d73d7a1f0b6bb89ff355](https://basescan.org/address/0x000000000005b7e7a344d73d7a1f0b6bb89ff355)|


## Epoch

- a continuous loop of 30-day epochs create the game loop
- once an epoch has concluded, votes are tallied, winners are crowned, and minting/submitting is opened for the next epoch

## Tokens

### Ocmeme

- ERC-721 priced on logistic [VRGDA](https://www.paradigm.xyz/2022/08/vrgda#logistic-issuance-schedule) curve
- Max 500 per event
- minted with ether
- given an emission multiple for continuous lazy $GOO emission (see $GOO)
- when events concludes, metadata is inherited from top-voted submission

### Pages

- ERC-721 priced on linear [VRGDA](https://www.paradigm.xyz/2022/08/vrgda#linear) curve
- minted with $GOO
- can only be used for a single submission
- stores metadata: royalty & sstore2 pointer to onchain data-uri

### Goo

- ERC-20 using [Gradual Ownership Optimization](https://www.paradigm.xyz/2022/09/goo)
- $GOO is lazily emitted by Ocmeme's based on their emission multiple
- use $GOO to vote on and mint $PAGES

## Actions
* code shown below is not identical to deployed code

### Mint

```solidity
function mint() external payable {
    (uint256 epochID, uint256 estart) = currentEpoch();
    uint256 price = _getPrice(estart, count);
    if (msg.value < price) revert InsufficientFunds();

    $epochs[epochID].proceeds += price;

    _mint(msg.sender, ++$prevTokenID, epochID, ++count);

    // refund overpaid
    SafeTransferLib.safeTransferETH(msg.sender, msg.value - price);
}
```

- main entry point to game
- minting an Ocmeme gives you a constant emission of $GOO, which is then used to mint and vote on $PAGES
- when event concludes tokenURI becomes top-voted page
- any funds paid > price are auto-refunded
- minting is open until events logistic asymptote is hit (500)

### Submission

```solidity
function submit(
    uint256 _pageID,
    uint256 _royalty,
    NFTMeta.TypeURI _typeUri,
    string calldata _description,
    string calldata _duri
) external {
    ...
    address pointer = SSTORE2.write(
        NFTMeta.constructTokenURI(...)
    );
    $pages.setMetadata(_pageID, _royalty, pointer);
    $submissions[eventID].push(_pageID);
    ...
}
```
* contract technically supports any data-uri. frontend currently only supports image/text/html.

- an unused $PAGES token is required to make a submission
- max 100 submissions per event
- top 3 submissions ranked by votes are crowned winners at conclusion of event
- Ocmeme tokenURI & royalty are inherited from top-voted submission

- _duri: any valid [data-uri](https://developer.mozilla.org/en-US/docs/Web/HTTP/Basics_of_HTTP/Data_URLs)
- _typeURI (image or animation) - used to decide data key in tokenURI json. {name: "", description: "", **image**: ""} vs {name: "", description: "", **animation_url**: ""}

### Vote

- use $GOO to vote on $PAGES
- voting burns $GOO
- to avoid gas in the vote function, there are no safeguards, voting for an invalid pageID is allowed

### Claim

- once event is concluded the owners of top-voted $PAGES can claim their winnings.
- Gold: 85%
- Silver: 8%
- Bronze: 4%
- Protocol: 3%

## Disclaimer
This is dangerous unaudited code.
there is only memes i love you ❣
