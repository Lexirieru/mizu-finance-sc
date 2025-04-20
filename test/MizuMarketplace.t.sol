// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../src/MizuMarketplace.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../src/MockUSDC.sol";

contract DummyERC721 is IERC721 {
    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    mapping(uint256 => address) private _tokenApprovals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    function supportsInterface(
        bytes4 interfaceId
    ) external pure override returns (bool) {
        return interfaceId == type(IERC721).interfaceId;
    }

    function mint(address to, uint256 tokenId) external {
        _owners[tokenId] = to;
        _balances[to] += 1;
    }

    function balanceOf(address owner) external view override returns (uint256) {
        return _balances[owner];
    }

    function ownerOf(uint256 tokenId) external view override returns (address) {
        return _owners[tokenId];
    }

    function approve(address to, uint256 tokenId) external override {
        _tokenApprovals[tokenId] = to;
    }

    function setApprovalForAll(
        address operator,
        bool approved
    ) external override {
        _operatorApprovals[msg.sender][operator] = approved;
    }

    function getApproved(
        uint256 tokenId
    ) external view override returns (address) {
        return _tokenApprovals[tokenId];
    }

    function isApprovedForAll(
        address owner,
        address operator
    ) external view override returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    function _transfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual {
        require(_owners[tokenId] == from, "Not owner");
        _owners[tokenId] = to;
        _balances[from] -= 1;
        _balances[to] += 1;
    }

    function _checkOnERC721Received(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) private returns (bool) {
        if (to.code.length > 0) {
            try
                IERC721Receiver(to).onERC721Received(
                    msg.sender,
                    from,
                    tokenId,
                    data
                )
            returns (bytes4 retval) {
                return retval == IERC721Receiver.onERC721Received.selector;
            } catch (bytes memory reason) {
                if (reason.length == 0) {
                    revert(
                        "ERC721: transfer to non ERC721Receiver implementer"
                    );
                } else {
                    /// @solidity memory-safe-assembly
                    assembly {
                        revert(add(32, reason), mload(reason))
                    }
                }
            }
        } else {
            return true;
        }
    }

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external override {
        _transfer(from, to, tokenId);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes calldata data
    ) external override {
        _transfer(from, to, tokenId);
        require(
            _checkOnERC721Received(from, to, tokenId, data),
            "ERC721: transfer to non ERC721Receiver implementer"
        );
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external override {
        _transfer(from, to, tokenId);
        require(
            _checkOnERC721Received(from, to, tokenId, ""),
            "ERC721: transfer to non ERC721Receiver implementer"
        );
    }
}

contract DummyDLT is IDLT {
    mapping(address => mapping(uint256 => mapping(uint256 => uint256)))
        public balances;

    function setApprovalForAll(address, bool) external override {}

    function approve(
        address,
        uint256,
        uint256,
        uint256
    ) external pure override returns (bool) {
        return true;
    }

    function allowance(
        address,
        address,
        uint256,
        uint256
    ) external pure override returns (uint256) {
        return 0;
    }

    function isApprovedForAll(
        address,
        address
    ) external pure override returns (bool) {
        return true;
    }

    function subBalanceOf(
        address account,
        uint256 mainId,
        uint256 subId
    ) external view override returns (uint256) {
        return balances[account][mainId][subId];
    }

    function balanceOfBatch(
        address[] calldata,
        uint256[] calldata,
        uint256[] calldata
    ) external pure override returns (uint256[] calldata) {
        revert("not implemented");
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 mainId,
        uint256 subId,
        uint256 amount,
        bytes calldata
    ) external override returns (bool) {
        require(balances[from][mainId][subId] >= amount, "Insufficient");
        balances[from][mainId][subId] -= amount;
        balances[to][mainId][subId] += amount;
        return true;
    }

    function setBalance(
        address account,
        uint256 mainId,
        uint256 subId,
        uint256 amount
    ) external {
        balances[account][mainId][subId] = amount;
    }

    function mint(
        address to,
        uint256 mainId,
        uint256 subId,
        uint256 amount
    ) external {
        balances[to][mainId][subId] += amount;
    }
}

contract MizuMarketplaceTest is Test {
    MizuMarketplace public mizu;
    DummyDLT public dlt;
    DummyERC721 public nft;
    MockUSDC public usdc;

    address user = makeAddr("user");
    address buyer = makeAddr("buyer");
    address buyer1 = makeAddr("buyer1");

    function setUp() public {
        usdc = new MockUSDC();
        dlt = new DummyDLT();
        mizu = new MizuMarketplace(address(dlt), address(usdc));
        nft = new DummyERC721();

        vm.deal(user, 10 ether);
        vm.deal(buyer, 10 ether);
        vm.deal(buyer1, 10 ether);

        // Mint NFT to user
        nft.mint(user, 1);

        // Mint USDC to buyers
        usdc.mint(buyer, 10000e6); // 10,000 USDC
        usdc.mint(buyer1, 10000e6); // 10,000 USDC
    }

    function testCustomFragmentation() public {
        vm.startPrank(user);
        nft.approve(address(mizu), 1);
        mizu.wrapERC721(address(nft), 1, 1000);

        // List 500 fragments at 2 USDC each with min purchase 100 USDC
        mizu.listERC6960(1, 0, 500, 2e6, 100e6);
        vm.stopPrank();

        // Buyer approves and purchases fragments
        vm.startPrank(buyer);
        usdc.approve(address(mizu), 1000e6);
        mizu.buyERC6960(0, 500);
        vm.stopPrank();

        // Assert balances
        assertEq(dlt.subBalanceOf(buyer, 1, 0), 500);
        assertEq(dlt.subBalanceOf(user, 1, 0), 500);
        assertEq(nft.ownerOf(1), address(mizu));
        assertEq(usdc.balanceOf(buyer), 9000e6); // 10,000 - (500 * 2)
        assertEq(usdc.balanceOf(user), 1000e6); // Received 1,000 USDC
    }

    function testMinimumPurchase() public {
        vm.startPrank(user);
        nft.approve(address(mizu), 1);
        mizu.wrapERC721(address(nft), 1, 1000);

        // List with minimum purchase 100 USDC
        mizu.listERC6960(1, 0, 1000, 2e6, 100e6);
        vm.stopPrank();

        vm.startPrank(buyer);
        usdc.approve(address(mizu), 50e6);

        // Try to buy below minimum (25 fragments = 50 USDC)
        vm.expectRevert("Below minimum purchase amount");
        mizu.buyERC6960(0, 25);
        vm.stopPrank();
    }

    function testPartialPurchase() public {
        vm.startPrank(user);
        nft.approve(address(mizu), 1);
        mizu.wrapERC721(address(nft), 1, 1000);
        mizu.listERC6960(1, 0, 1000, 2e6, 100e6);
        vm.stopPrank();

        // First buyer buys 300 fragments
        vm.startPrank(buyer);
        usdc.approve(address(mizu), 600e6); // 300 * 2 USDC
        mizu.buyERC6960(0, 300);
        vm.stopPrank();

        // Second buyer buys 200 fragments
        vm.startPrank(buyer1);
        usdc.approve(address(mizu), 400e6); // 200 * 2 USDC
        mizu.buyERC6960(0, 200);
        vm.stopPrank();

        // Verify balances
        assertEq(dlt.subBalanceOf(buyer, 1, 0), 300);
        assertEq(dlt.subBalanceOf(buyer1, 1, 0), 200);
        assertEq(dlt.subBalanceOf(address(mizu), 1, 0), 500); // Remaining in marketplace
        assertEq(usdc.balanceOf(user), 1000e6); // Received 600 + 400 = 1000 USDC
    }

    function testWrapListAndRedeem() public {
        vm.startPrank(user);
        nft.approve(address(mizu), 1);
        mizu.wrapERC721(address(nft), 1, 100);
        mizu.listERC6960(1, 0, 100, 2e6, 100e6);
        vm.stopPrank();

        // Buyer buys all fragments
        vm.startPrank(buyer);
        usdc.approve(address(mizu), 200e6); // 100 fragments * 2 USDC
        mizu.buyERC6960(0, 100);

        // Buyer can now redeem the NFT
        mizu.redeemERC721(1);
        vm.stopPrank();

        // Assert final state
        assertEq(nft.ownerOf(1), buyer);
        assertEq(dlt.subBalanceOf(buyer, 1, 0), 0);
        assertEq(usdc.balanceOf(user), 200e6); // Received payment for all fragments
    }

    function testMakeOffer() public {
        vm.startPrank(user);
        nft.approve(address(mizu), 1);
        mizu.wrapERC721(address(nft), 1, 1000);
        mizu.listERC6960(1, 0, 1000, 2e6, 100e6);
        vm.stopPrank();

        vm.startPrank(buyer);
        uint256 offerAmount = 500;
        uint256 pricePerUnit = 1.5e6; // 1.5 USDC per fragment
        uint256 totalPrice = offerAmount * pricePerUnit;

        usdc.approve(address(mizu), totalPrice);
        mizu.makeOffer(0, offerAmount, pricePerUnit, 1 days);
        vm.stopPrank();

        (
            address offerBuyer,
            uint256 listingId,
            uint256 amount,
            uint256 price,
            uint256 expiration,
            bool active
        ) = mizu.offers(0);

        assertEq(offerBuyer, buyer);
        assertEq(listingId, 0);
        assertEq(amount, offerAmount);
        assertEq(price, pricePerUnit);
        assertTrue(active);
    }

    function testAcceptOffer() public {
        vm.startPrank(user);
        nft.approve(address(mizu), 1);
        mizu.wrapERC721(address(nft), 1, 1000);
        mizu.listERC6960(1, 0, 1000, 2e6, 100e6);
        vm.stopPrank();

        vm.startPrank(buyer);
        uint256 offerAmount = 500;
        uint256 pricePerUnit = 1.5e6;
        uint256 totalPrice = offerAmount * pricePerUnit;

        usdc.approve(address(mizu), totalPrice);
        mizu.makeOffer(0, offerAmount, pricePerUnit, 1 days);
        vm.stopPrank();

        uint256 sellerBalanceBefore = usdc.balanceOf(user);
        uint256 buyerFragmentsBefore = dlt.subBalanceOf(buyer, 1, 0);

        vm.prank(user);
        mizu.acceptOffer(0);

        assertEq(
            dlt.subBalanceOf(buyer, 1, 0),
            buyerFragmentsBefore + offerAmount
        );
        assertEq(usdc.balanceOf(user), sellerBalanceBefore + totalPrice);

        (, , , , , bool active) = mizu.offers(0);
        assertFalse(active);
    }

    function testExpiredOffer() public {
        vm.startPrank(user);
        nft.approve(address(mizu), 1);
        mizu.wrapERC721(address(nft), 1, 1000);
        mizu.listERC6960(1, 0, 1000, 2e6, 100e6);
        vm.stopPrank();

        vm.startPrank(buyer);
        uint256 offerAmount = 500;
        uint256 pricePerUnit = 1.5e6;
        uint256 totalPrice = offerAmount * pricePerUnit;

        usdc.approve(address(mizu), totalPrice);
        mizu.makeOffer(0, offerAmount, pricePerUnit, 1 days);
        vm.stopPrank();

        // Fast forward past expiration
        vm.warp(block.timestamp + 2 days);

        // Attempt to accept expired offer
        vm.prank(user);
        vm.expectRevert("Offer expired");
        mizu.acceptOffer(0);
    }

    function testMultipleOffersAndAcceptance() public {
        vm.startPrank(user);
        nft.approve(address(mizu), 1);
        mizu.wrapERC721(address(nft), 1, 1000);
        mizu.listERC6960(1, 0, 1000, 2e6, 100e6);
        vm.stopPrank();

        // First buyer makes an offer
        vm.startPrank(buyer);
        usdc.approve(address(mizu), 750e6); // 1.5 USDC * 500
        mizu.makeOffer(0, 500, 1.5e6, 1 days);
        vm.stopPrank();

        // Second buyer makes a higher offer
        vm.startPrank(buyer1);
        usdc.approve(address(mizu), 1000e6); // 2 USDC * 500
        mizu.makeOffer(0, 500, 2e6, 1 days);
        vm.stopPrank();

        // Verify both offers are listed
        uint256[] memory offers = mizu.getListingOffers(0);
        assertEq(offers.length, 2);

        // Seller accepts the higher offer
        vm.prank(user);
        mizu.acceptOffer(1);

        // Verify first buyer can still cancel their offer
        vm.prank(buyer);
        mizu.cancelOffer(0);

        // Verify balances
        assertEq(usdc.balanceOf(user), 1000e6); // Received 1000 USDC from second buyer
        assertEq(dlt.subBalanceOf(buyer1, 1, 0), 500); // Second buyer got fragments
    }

    function testGetActiveOffers() public {
        vm.startPrank(user);
        nft.approve(address(mizu), 1);
        mizu.wrapERC721(address(nft), 1, 1000);
        mizu.listERC6960(1, 0, 1000, 2e6, 100e6);
        vm.stopPrank();

        // Make multiple offers
        vm.startPrank(buyer);
        usdc.approve(address(mizu), 750e6);
        mizu.makeOffer(0, 500, 1.5e6, 1 days);
        vm.stopPrank();

        vm.startPrank(buyer1);
        usdc.approve(address(mizu), 1000e6);
        mizu.makeOffer(0, 500, 2e6, 2 days);
        vm.stopPrank();

        // Cancel first offer
        vm.prank(buyer);
        mizu.cancelOffer(0);

        // Fast forward 1.5 days
        vm.warp(block.timestamp + 1.5 days);

        // Get active offers
        uint256[] memory activeOffers = mizu.getActiveOffers(0);

        // Only the second offer should be active
        assertEq(activeOffers.length, 1);
        assertEq(activeOffers[0], 1);
    }

    function testMinimumPurchaseAmount() public {
        vm.startPrank(user);
        nft.approve(address(mizu), 1);
        mizu.wrapERC721(address(nft), 1, 1000);

        // Try to list with zero minimum purchase amount
        vm.expectRevert("Min purchase must be greater than 0");
        mizu.listERC6960(1, 0, 500, 2e6, 0);
        vm.stopPrank();
    }

    function testZeroPricePerUnit() public {
        vm.startPrank(user);
        nft.approve(address(mizu), 1);
        mizu.wrapERC721(address(nft), 1, 1000);

        // Try to list with zero price per unit
        vm.expectRevert("Price must be greater than 0");
        mizu.listERC6960(1, 0, 500, 0, 100e6);
        vm.stopPrank();
    }

    function testZeroAmount() public {
        vm.startPrank(user);
        nft.approve(address(mizu), 1);
        mizu.wrapERC721(address(nft), 1, 1000);

        // Try to list zero amount
        vm.expectRevert("Amount must be greater than 0");
        mizu.listERC6960(1, 0, 0, 2e6, 100e6);
        vm.stopPrank();
    }
}
