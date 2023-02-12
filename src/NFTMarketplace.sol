// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";

contract NFTMarketplace is ReentrancyGuard, Ownable {
    /**
     * @notice Types
     */
    struct Listing {
        uint256 price;
        address asset;
        address seller;
        address nftAddress;
        uint256 tokenId;
    }

    /**
     * @notice State variables
     */
    mapping(address => mapping(uint256 => Listing)) private listings;
    mapping(address => mapping(address => uint256)) private earnings;
    mapping(address => bool) public supportedAssets;
    uint8 public platformFeeBps;

    /**
     * @notice Events
     */
    event ItemListed(
        address indexed seller,
        address indexed nftAddress,
        uint256 indexed tokenId,
        uint256 price,
        address asset
    );

    event ItemBought(
        address indexed seller,
        address indexed nftAddress,
        uint256 indexed tokenId,
        uint256 price,
        address asset
    );

    event ListingCanceled(
        address indexed seller,
        address indexed nftAddress,
        uint256 indexed tokenId
    );

    event EarningsWithdrawn(
        address indexed seller,
        uint256 amount,
        address asset
    );

    /**
     * @notice Errors
     */
    error AlreadyListed();

    error NoEarnings(address asset);

    error NotListed();

    error NotOwner();

    error PriceBelowOrEqZero();

    error AllowanceNotMet(
        address nftAddress,
        uint256 tokenId,
        uint256 price,
        address asset
    );

    error PriceNotMet(
        address nftAddress,
        uint256 tokenId,
        uint256 price,
        address asset
    );

    error NoSupportedAssetsProvided();

    error AssetNotSupported();

    error NftNotApprovedForSpending();

    /**
     * @notice Modifiers
     */
    modifier notListed(
        address nftAddress,
        uint256 tokenId,
        address seller
    ) {
        Listing memory listing = listings[nftAddress][tokenId];
        if (listing.seller == seller) {
            revert AlreadyListed();
        }
        _;
    }

    modifier isListed(address nftAddress, uint256 tokenId) {
        Listing memory listing = listings[nftAddress][tokenId];
        if (listing.price <= 0) {
            revert NotListed();
        }
        _;
    }

    modifier isOwner(
        address nftAddress,
        uint256 tokenId,
        address seller
    ) {
        IERC721 nft = IERC721(nftAddress);
        if (nft.ownerOf(tokenId) != seller) {
            revert NotOwner();
        }
        _;
    }

    modifier isSupportedAsset(address asset) {
        if (!supportedAssets[asset]) {
            revert AssetNotSupported();
        }
        _;
    }

    /**
     * @notice Constructor
     */
    constructor(address[] memory _supportedAssets, uint8 _platformFeeBps) {
        if (_supportedAssets.length == 0) revert NoSupportedAssetsProvided();
        platformFeeBps = _platformFeeBps;

        for (uint256 i = 0; i < _supportedAssets.length; i++) {
            supportedAssets[_supportedAssets[i]] = true;
        }
    }

    /**
     * @notice Getters
     */
    function getListing(
        address nftAddress,
        uint256 tokenId
    ) external view returns (Listing memory) {
        return listings[nftAddress][tokenId];
    }

    function getEarnings(
        address seller,
        address asset
    ) external view returns (uint256) {
        return earnings[seller][asset];
    }

    /**
     * @notice Listing an NFT for sale.
     */
    function listItem(
        address nftAddress,
        uint256 tokenId,
        uint256 price,
        address asset
    )
        external
        notListed(nftAddress, tokenId, msg.sender)
        isOwner(nftAddress, tokenId, msg.sender)
        isSupportedAsset(asset)
    {
        if (price <= 0) revert PriceBelowOrEqZero();

        IERC721 nft = IERC721(nftAddress);

        if (nft.getApproved(tokenId) != address(this))
            revert NftNotApprovedForSpending();

        listings[nftAddress][tokenId] = Listing(
            price,
            asset,
            msg.sender,
            nftAddress,
            tokenId
        );
        emit ItemListed(msg.sender, nftAddress, tokenId, price, asset);
    }

    /**
     * @notice Cancel a listing.
     */
    function cancelListing(
        address nftAddress,
        uint256 tokenId
    )
        external
        isOwner(nftAddress, tokenId, msg.sender)
        isListed(nftAddress, tokenId)
    {
        delete (listings[nftAddress][tokenId]);
        emit ListingCanceled(msg.sender, nftAddress, tokenId);
    }

    /**
     * @notice Buy an NFT.
     */
    function buyItem(
        address nftAddress,
        uint256 tokenId
    ) external isListed(nftAddress, tokenId) nonReentrant {
        Listing memory listedItem = listings[nftAddress][tokenId];
        IERC20 asset = IERC20(listedItem.asset);

        uint256 allowance = asset.allowance(msg.sender, address(this));
        if (allowance < listedItem.price) {
            revert AllowanceNotMet(
                nftAddress,
                tokenId,
                listedItem.price,
                listedItem.asset
            );
        }

        uint256 balance = asset.balanceOf(msg.sender);
        if (balance < listedItem.price) {
            revert PriceNotMet(
                nftAddress,
                tokenId,
                listedItem.price,
                listedItem.asset
            );
        }

        asset.transferFrom(msg.sender, address(this), listedItem.price);
        uint platformFeeAmount = 0;
        if (listedItem.price > 100000000) {
            platformFeeAmount = listedItem.price * platformFeeBps / 10_000;
        }


        earnings[listedItem.seller][listedItem.asset] += listedItem.price - platformFeeAmount;
        earnings[address(this)][listedItem.asset] += platformFeeAmount;

        delete (listings[nftAddress][tokenId]);
        IERC721(nftAddress).safeTransferFrom(
            listedItem.seller,
            msg.sender,
            tokenId
        );
        emit ItemBought(
            msg.sender,
            nftAddress,
            tokenId,
            listedItem.price,
            listedItem.asset
        );
    }

    /**
     * @notice Withdraw earnings.
     */
    function withdrawEarnings(
        address assetAddress
    ) external isSupportedAsset(assetAddress) {
        uint256 sellerEarnings = earnings[msg.sender][assetAddress];
        if (sellerEarnings <= 0) revert NoEarnings(assetAddress);

        earnings[msg.sender][assetAddress] = 0;

        IERC20 asset = IERC20(assetAddress);
        asset.transfer(msg.sender, sellerEarnings);
    }

    /**
     * @notice Withdraw platform earnings.
     */
    function withdrawPlatformEarnings(
        address assetAddress
    ) external isSupportedAsset(assetAddress) onlyOwner {
        uint256 platformEarnings = earnings[address(this)][assetAddress];
        if (platformEarnings <= 0) revert NoEarnings(assetAddress);

        earnings[address(this)][assetAddress] = 0;

        IERC20 asset = IERC20(assetAddress);
        asset.transfer(msg.sender, platformEarnings);
    }
}
