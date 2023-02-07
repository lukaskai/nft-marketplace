// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";

contract MockedNFT is ERC721 {
    string public constant TOKEN_URI = "";
    uint256 public tokenCount;

    event NftMinted(uint256 indexed tokenId);

    constructor() ERC721("Demo", "DEM") {
        tokenCount = 0;
    }

    function mintTo(address to) public returns (uint256) {
        uint256 tokenId = tokenCount;
        _safeMint(to, tokenId);
        emit NftMinted(tokenId);
        tokenCount = tokenCount + 1;

        return tokenId;
    }

    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        require(
            _exists(tokenId),
            "ERC721Metadata: URI query for nonexistent token"
        );
        return TOKEN_URI;
    }
}
