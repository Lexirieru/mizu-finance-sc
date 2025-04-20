// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IDLT {
    event Transfer(
        address indexed sender,
        address indexed recipient,
        uint256 indexed mainId,
        uint256 subId,
        uint256 amount
    );
    event TransferBatch(
        address indexed sender,
        address indexed recipient,
        uint256[] mainIds,
        uint256[] subIds,
        uint256[] amounts
    );
    event Approval(
        address indexed owner,
        address indexed operator,
        uint256 mainId,
        uint256 subId,
        uint256 amount
    );
    event ApprovalForAll(
        address indexed owner,
        address indexed operator,
        bool approved
    );
    event URI(string oldValue, string newValue, uint256 indexed mainId);

    function setApprovalForAll(address operator, bool approved) external;

    function safeTransferFrom(
        address sender,
        address recipient,
        uint256 mainId,
        uint256 subId,
        uint256 amount,
        bytes calldata data
    ) external returns (bool);

    function approve(
        address operator,
        uint256 mainId,
        uint256 subId,
        uint256 amount
    ) external returns (bool);

    function subBalanceOf(
        address account,
        uint256 mainId,
        uint256 subId
    ) external view returns (uint256);

    function balanceOfBatch(
        address[] calldata accounts,
        uint256[] calldata mainIds,
        uint256[] calldata subIds
    ) external view returns (uint256[] calldata);

    function allowance(
        address owner,
        address operator,
        uint256 mainId,
        uint256 subId
    ) external view returns (uint256);

    function isApprovedForAll(
        address owner,
        address operator
    ) external view returns (bool);

    function mint(
        address to,
        uint256 mainId,
        uint256 subId,
        uint256 amount
    ) external;
}

interface IDLTReceiver {
    function onDLTReceived(
        address operator,
        address from,
        uint256 mainId,
        uint256 subId,
        uint256 amount,
        bytes calldata data
    ) external returns (bytes4);

    function onDLTBatchReceived(
        address operator,
        address from,
        uint256[] calldata mainIds,
        uint256[] calldata subIds,
        uint256[] calldata amounts,
        bytes calldata data
    ) external returns (bytes4);
}

contract MizuMarketplace is Ownable {
    enum PaymentToken {
        USDC
    }

    // Events
    event NFTWrapped(
        address indexed nftContract,
        uint256 indexed tokenId,
        address indexed owner,
        uint256 fragments
    );

    event NFTRedeemed(
        address indexed nftContract,
        uint256 indexed tokenId,
        address indexed redeemer
    );

    event FragmentsListed(
        uint256 indexed listingId,
        address indexed seller,
        uint256 indexed mainId,
        uint256 subId,
        uint256 amount,
        uint256 pricePerUnit
    );

    event FragmentsPurchased(
        uint256 indexed listingId,
        address indexed buyer,
        address indexed seller,
        uint256 mainId,
        uint256 subId,
        uint256 amount,
        uint256 totalPrice
    );

    event ListingCancelled(uint256 indexed listingId, address indexed seller);

    event OfferCreated(
        uint256 indexed listingId,
        uint256 indexed offerId,
        address indexed buyer,
        uint256 amount,
        uint256 pricePerUnit,
        uint256 expirationTime
    );

    event OfferAccepted(
        uint256 indexed listingId,
        uint256 indexed offerId,
        address indexed seller,
        address buyer,
        uint256 amount,
        uint256 totalPrice
    );

    event OfferCancelled(
        uint256 indexed listingId,
        uint256 indexed offerId,
        address indexed buyer
    );

    struct ERC6960Listing {
        address seller;
        uint256 mainId;
        uint256 subId;
        uint256 amount;
        uint256 pricePerUnit;
        uint256 minPurchaseAmount;
        PaymentToken paymentToken;
        bool active;
    }

    struct WrappedNFT {
        address nftContract;
        uint256 tokenId;
        uint256 totalFragments;
        bool isWrapped;
    }

    struct Offer {
        address buyer;
        uint256 listingId;
        uint256 amount;
        uint256 pricePerUnit;
        uint256 expirationTime;
        bool active;
    }

    IDLT public dlt;
    IERC20 public immutable usdc;
    mapping(uint256 => ERC6960Listing) public erc6960Listings;
    uint256 public erc6960Count;
    mapping(uint256 => WrappedNFT) public wrappedNFTs;

    // Offer mappings
    mapping(uint256 => Offer) public offers;
    uint256 public offerCount;
    mapping(uint256 => uint256[]) public listingOffers; // listingId => offerIds

    constructor(address _dltAddress, address _usdcAddress) Ownable(msg.sender) {
        dlt = IDLT(_dltAddress);
        usdc = IERC20(_usdcAddress);
    }

    function wrapERC721(
        address nft,
        uint256 tokenId,
        uint256 fragments
    ) external {
        require(fragments > 0, "Invalid fragments amount");
        IERC721(nft).transferFrom(msg.sender, address(this), tokenId);

        wrappedNFTs[tokenId] = WrappedNFT({
            nftContract: nft,
            tokenId: tokenId,
            totalFragments: fragments,
            isWrapped: true
        });

        dlt.mint(msg.sender, tokenId, 0, fragments);

        emit NFTWrapped(nft, tokenId, msg.sender, fragments);
    }

    function redeemERC721(uint256 tokenId) external {
        WrappedNFT storage nft = wrappedNFTs[tokenId];
        require(nft.isWrapped, "Not wrapped");
        require(
            dlt.subBalanceOf(msg.sender, tokenId, 0) == nft.totalFragments,
            "Not full owner"
        );

        dlt.safeTransferFrom(
            msg.sender,
            address(this),
            tokenId,
            0,
            nft.totalFragments,
            ""
        );

        IERC721(nft.nftContract).transferFrom(
            address(this),
            msg.sender,
            tokenId
        );

        nft.isWrapped = false;

        emit NFTRedeemed(nft.nftContract, tokenId, msg.sender);
    }

    function listERC6960(
        uint256 mainId,
        uint256 subId,
        uint256 amount,
        uint256 pricePerUnit,
        uint256 minPurchaseAmount
    ) external returns (uint256) {
        require(amount > 0, "Amount must be greater than 0");
        require(pricePerUnit > 0, "Price must be greater than 0");
        require(minPurchaseAmount > 0, "Min purchase must be greater than 0");

        require(
            dlt.safeTransferFrom(
                msg.sender,
                address(this),
                mainId,
                subId,
                amount,
                ""
            ),
            "Transfer failed"
        );

        uint256 listingId = erc6960Count++;
        erc6960Listings[listingId] = ERC6960Listing({
            seller: msg.sender,
            mainId: mainId,
            subId: subId,
            amount: amount,
            pricePerUnit: pricePerUnit,
            minPurchaseAmount: minPurchaseAmount,
            paymentToken: PaymentToken.USDC,
            active: true
        });

        emit FragmentsListed(
            listingId,
            msg.sender,
            mainId,
            subId,
            amount,
            pricePerUnit
        );

        return listingId;
    }

    function buyERC6960(uint256 listingId, uint256 amount) external {
        ERC6960Listing storage listing = erc6960Listings[listingId];
        require(listing.active, "Listing not active");
        require(amount > 0, "Amount must be greater than 0");
        require(amount <= listing.amount, "Insufficient listed amount");

        uint256 totalPrice = amount * listing.pricePerUnit;
        require(
            totalPrice >= listing.minPurchaseAmount,
            "Below minimum purchase amount"
        );

        // Transfer USDC from buyer to seller
        require(
            usdc.transferFrom(msg.sender, listing.seller, totalPrice),
            "USDC transfer failed"
        );

        // Transfer fragments to buyer
        require(
            dlt.safeTransferFrom(
                address(this),
                msg.sender,
                listing.mainId,
                listing.subId,
                amount,
                ""
            ),
            "Fragment transfer failed"
        );

        listing.amount -= amount;
        if (listing.amount == 0) {
            listing.active = false;
        }

        emit FragmentsPurchased(
            listingId,
            msg.sender,
            listing.seller,
            listing.mainId,
            listing.subId,
            amount,
            totalPrice
        );
    }

    function cancelListing(uint256 listingId) external {
        ERC6960Listing storage listing = erc6960Listings[listingId];
        require(listing.active, "Not active");
        require(listing.seller == msg.sender, "Not seller");

        listing.active = false;

        emit ListingCancelled(listingId, msg.sender);
    }

    function makeOffer(
        uint256 listingId,
        uint256 amount,
        uint256 pricePerUnit,
        uint256 duration
    ) external {
        require(amount > 0, "Amount must be greater than 0");
        require(pricePerUnit > 0, "Price must be greater than 0");
        require(duration > 0, "Duration must be greater than 0");

        ERC6960Listing storage listing = erc6960Listings[listingId];
        require(listing.active, "Listing not active");
        require(amount <= listing.amount, "Amount exceeds listing");

        uint256 totalPrice = amount * pricePerUnit;
        require(
            usdc.transferFrom(msg.sender, address(this), totalPrice),
            "USDC transfer failed"
        );

        uint256 offerId = offerCount++;
        offers[offerId] = Offer({
            buyer: msg.sender,
            listingId: listingId,
            amount: amount,
            pricePerUnit: pricePerUnit,
            expirationTime: block.timestamp + duration,
            active: true
        });

        listingOffers[listingId].push(offerId);

        emit OfferCreated(
            listingId,
            offerId,
            msg.sender,
            amount,
            pricePerUnit,
            block.timestamp + duration
        );
    }

    function acceptOffer(uint256 offerId) external {
        Offer storage offer = offers[offerId];
        require(offer.active, "Offer not active");
        require(block.timestamp <= offer.expirationTime, "Offer expired");

        ERC6960Listing storage listing = erc6960Listings[offer.listingId];
        require(msg.sender == listing.seller, "Not seller");
        require(offer.amount <= listing.amount, "Insufficient listing amount");

        uint256 totalPrice = offer.amount * offer.pricePerUnit;

        // Transfer USDC from contract to seller
        require(usdc.transfer(msg.sender, totalPrice), "USDC transfer failed");

        // Transfer fragments to buyer
        require(
            dlt.safeTransferFrom(
                address(this),
                offer.buyer,
                listing.mainId,
                listing.subId,
                offer.amount,
                ""
            ),
            "Fragment transfer failed"
        );

        listing.amount -= offer.amount;
        if (listing.amount == 0) {
            listing.active = false;
        }

        offer.active = false;

        emit OfferAccepted(
            offer.listingId,
            offerId,
            msg.sender,
            offer.buyer,
            offer.amount,
            totalPrice
        );
    }

    function cancelOffer(uint256 offerId) external {
        Offer storage offer = offers[offerId];
        require(offer.active, "Offer not active");
        require(msg.sender == offer.buyer, "Not buyer");

        uint256 totalPrice = offer.amount * offer.pricePerUnit;

        // Refund USDC to buyer
        require(usdc.transfer(offer.buyer, totalPrice), "USDC refund failed");

        offer.active = false;

        emit OfferCancelled(offer.listingId, offerId, offer.buyer);
    }

    function getListingOffers(
        uint256 listingId
    ) external view returns (uint256[] memory) {
        return listingOffers[listingId];
    }

    // function to get active offers for a listing
    function getActiveOffers(
        uint256 listingId
    ) external view returns (uint256[] memory) {
        uint256[] memory allOffers = listingOffers[listingId];
        uint256[] memory activeOfferIds = new uint256[](allOffers.length);
        uint256 activeCount = 0;

        for (uint256 i = 0; i < allOffers.length; i++) {
            uint256 offerId = allOffers[i];
            Offer storage offer = offers[offerId];
            if (offer.active && block.timestamp <= offer.expirationTime) {
                activeOfferIds[activeCount] = offerId;
                activeCount++;
            }
        }

        // Resize array to actual number of active offers
        uint256[] memory result = new uint256[](activeCount);
        for (uint256 i = 0; i < activeCount; i++) {
            result[i] = activeOfferIds[i];
        }

        return result;
    }
}
