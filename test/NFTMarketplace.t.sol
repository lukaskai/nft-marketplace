// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "./mocks/MockedNFT.sol";
import "./mocks/MockedERC20.sol";
import "../src/NFTMarketplace.sol";

contract NFTMarketplaceTest is Test {
    address private immutable seller = vm.addr(0x1);
    address private immutable buyer = vm.addr(0x2);

    MockedNFT private nft;
    MockedERC20 private token;
    NFTMarketplace private nftMarketplace;
    address[] private supportedTokens;

    function setUp() public {
        nft = new MockedNFT();
        token = new MockedERC20();
        supportedTokens.push(address(token));

        nftMarketplace = new NFTMarketplace(supportedTokens);
    }

    function testConstructorWithoutSupportedAssetsReverts() public {
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    NFTMarketplace.NoSupportedAssetsProvided.selector
                )
            )
        );
        nftMarketplace = new NFTMarketplace(new address[](0));
    }

    function testListingAnNft(uint256 sellPrice) public {
        vm.assume(sellPrice > 0);

        uint256 tokenId = nft.mintTo(seller);

        vm.startPrank(address(seller));
        nft.approve(address(nftMarketplace), tokenId);
        nftMarketplace.listItem(
            address(nft),
            tokenId,
            sellPrice,
            address(token)
        );
        vm.stopPrank();

        NFTMarketplace.Listing memory storedListing = nftMarketplace.getListing(
            address(nft),
            tokenId
        );

        assertEq(storedListing.seller, seller);
        assertEq(storedListing.asset, address(token));
        assertEq(storedListing.tokenId, tokenId);
        assertEq(storedListing.price, sellPrice);
        assertEq(storedListing.nftAddress, address(nft));
    }

    function testListingAnWithAZeroPriceReverts() public {
        uint256 tokenId = nft.mintTo(seller);

        vm.startPrank(address(seller));
        nft.approve(address(nftMarketplace), tokenId);

        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    NFTMarketplace.PriceBelowOrEqZero.selector
                )
            )
        );
        nftMarketplace.listItem(address(nft), tokenId, 0, address(token));
        vm.stopPrank();
    }

    function testListingWithNotApprovedSpendingReverts() public {
        uint256 tokenId = nft.mintTo(seller);

        vm.startPrank(address(seller));
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    NFTMarketplace.NftNotApprovedForSpending.selector
                )
            )
        );
        nftMarketplace.listItem(address(nft), tokenId, 1, address(token));
        vm.stopPrank();
    }

    function testListingAlreadyListedItemReverts() public {
        uint256 tokenId = nft.mintTo(seller);

        vm.startPrank(address(seller));
        nft.approve(address(nftMarketplace), tokenId);
        nftMarketplace.listItem(address(nft), tokenId, 1, address(token));

        vm.expectRevert(
            bytes(abi.encodeWithSelector(NFTMarketplace.AlreadyListed.selector))
        );
        nftMarketplace.listItem(address(nft), tokenId, 1, address(token));
        vm.stopPrank();
    }

    function testListingWithUnsupportedAssetReverts() public {
        uint256 tokenId = nft.mintTo(seller);

        vm.startPrank(address(seller));
        nft.approve(address(nftMarketplace), tokenId);
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    NFTMarketplace.AssetNotSupported.selector
                )
            )
        );
        nftMarketplace.listItem(address(nft), tokenId, 1, address(0x1));
        vm.stopPrank();
    }

    function testListingWithNftWhichIsNotOwnedReverts() public {
        uint256 tokenId = nft.mintTo(buyer);

        vm.startPrank(address(buyer));
        nft.approve(address(nftMarketplace), tokenId);
        nft.safeTransferFrom(address(buyer), address(seller), tokenId);

        vm.expectRevert(
            bytes(abi.encodeWithSelector(NFTMarketplace.NotOwner.selector))
        );
        nftMarketplace.listItem(address(nft), tokenId, 1, address(0x1));
        vm.stopPrank();
    }

    function testBuyingAnNft(uint256 sellPrice) public {
        vm.assume(sellPrice > 0);

        uint256 tokenId = nft.mintTo(seller);
        token.mint(buyer, sellPrice);

        vm.startPrank(address(seller));
        nft.approve(address(nftMarketplace), tokenId);
        nftMarketplace.listItem(
            address(nft),
            tokenId,
            sellPrice,
            address(token)
        );
        vm.stopPrank();

        vm.startPrank(address(buyer));
        token.approve(address(nftMarketplace), sellPrice);
        nftMarketplace.buyItem(address(nft), tokenId);
        vm.stopPrank();

        NFTMarketplace.Listing memory storedListing = nftMarketplace.getListing(
            address(nft),
            tokenId
        );

        assertEq(token.balanceOf(buyer), 0);
        assertEq(nft.ownerOf(tokenId), address(buyer));
        assertEq(storedListing.seller, address(0));
    }

    function testBuyingAnNftWithoutProperTokenSpendingApprovalReverts() public {
        uint256 sellPrice = 1 ether;
        uint256 tokenId = nft.mintTo(seller);
        token.mint(buyer, sellPrice);

        vm.startPrank(address(seller));
        nft.approve(address(nftMarketplace), tokenId);
        nftMarketplace.listItem(
            address(nft),
            tokenId,
            sellPrice,
            address(token)
        );
        vm.stopPrank();

        vm.startPrank(address(buyer));
        token.approve(address(nftMarketplace), sellPrice - 1);

        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    NFTMarketplace.AllowanceNotMet.selector,
                    address(nft),
                    tokenId,
                    sellPrice,
                    address(token)
                )
            )
        );
        nftMarketplace.buyItem(address(nft), tokenId);
        vm.stopPrank();
    }

    function testBuyingAnNftWithoutProperBalanceReverts() public {
        uint256 sellPrice = 1 ether;
        uint256 tokenId = nft.mintTo(seller);
        token.mint(buyer, sellPrice - 1);

        vm.startPrank(address(seller));
        nft.approve(address(nftMarketplace), tokenId);
        nftMarketplace.listItem(
            address(nft),
            tokenId,
            sellPrice,
            address(token)
        );
        vm.stopPrank();

        vm.startPrank(address(buyer));
        token.approve(address(nftMarketplace), sellPrice);

        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    NFTMarketplace.PriceNotMet.selector,
                    address(nft),
                    tokenId,
                    sellPrice,
                    address(token)
                )
            )
        );
        nftMarketplace.buyItem(address(nft), tokenId);
        vm.stopPrank();
    }

    function testWithdrawingEarnings(uint256 sellPrice) public {
        vm.assume(sellPrice > 0);
        uint256 tokenId = nft.mintTo(seller);
        token.mint(buyer, sellPrice);

        vm.startPrank(address(seller));
        nft.approve(address(nftMarketplace), tokenId);
        nftMarketplace.listItem(
            address(nft),
            tokenId,
            sellPrice,
            address(token)
        );
        vm.stopPrank();

        vm.startPrank(address(buyer));
        token.approve(address(nftMarketplace), sellPrice);
        nftMarketplace.buyItem(address(nft), tokenId);
        vm.stopPrank();

        vm.startPrank(address(seller));
        nftMarketplace.withdrawEarnings(address(token));
        vm.stopPrank();

        assertEq(token.balanceOf(seller), sellPrice);
    }

    function testWithdrawingWhenThereIsNoEarningsRevert() public {
        vm.startPrank(address(seller));
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    NFTMarketplace.NoEarnings.selector,
                    address(token)
                )
            )
        );
        nftMarketplace.withdrawEarnings(address(token));
        vm.stopPrank();
    }

    function testWithdrawingEarningsForNotSupportedAsset() public {
        vm.startPrank(address(seller));
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    NFTMarketplace.AssetNotSupported.selector
                )
            )
        );
        nftMarketplace.withdrawEarnings(address(0));
        vm.stopPrank();
    }

    // TODO: test listing cancellation
}
