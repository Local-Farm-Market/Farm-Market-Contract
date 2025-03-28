// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Farm.sol"; // Adjust path as needed

contract FarmTest is Test {
    Farm farm;
    address owner;
    address developerWallet;
    address seller;
    address buyer;
    address anotherBuyer;

    // Test product data
    string productName = "Organic Apples";
    string productCategory = "Fruits";
    uint256 productPrice = 1 ether;
    uint256 productStock = 100;
    string productUnit = "kg";
    string productDescription = "Fresh organic apples from local farms";
    string[] productImages;
    bool isOrganic = true;
    string harvestDate = "2023-05-15";
    Farm.NutritionFacts nutritionFacts;

    // Events to test
    event UserProfileCreated(address indexed user, string name, bool isSeller);
    event UserProfileUpdated(address indexed user);
    event ProductAdded(uint256 indexed productId, address indexed seller, string name);
    event ProductUpdated(uint256 indexed productId);
    event ProductDeleted(uint256 indexed productId);
    event OrderCreated(uint256 indexed orderId, address indexed buyer, address indexed seller);
    event OrderStatusUpdated(uint256 indexed orderId, Farm.OrderStatus status);
    event PaymentReleased(uint256 indexed orderId, uint256 amount);
    event WithdrawalMade(address indexed seller, uint256 amount);
    event ReviewSubmitted(uint256 indexed reviewId, address indexed reviewer, address indexed reviewee);
    event DisputeCreated(uint256 indexed orderId, address indexed initiator);
    event DisputeResolved(uint256 indexed orderId, Farm.DisputeResolution resolution);

    function setUp() public {
        owner = address(this);
        developerWallet = makeAddr("developerWallet");
        seller = makeAddr("seller");
        buyer = makeAddr("buyer");
        anotherBuyer = makeAddr("anotherBuyer");
        
        // Deploy contract
        farm = new Farm(developerWallet);
        
        // Setup test data
        productImages = new string[](2);
        productImages[0] = "https://example.com/apple1.jpg";
        productImages[1] = "https://example.com/apple2.jpg";
        
        nutritionFacts = Farm.NutritionFacts({
            calories: 52,
            protein: "0.3g",
            carbs: "14g",
            fat: "0.2g",
            fiber: "2.4g"
        });
        
        // Fund accounts
        vm.deal(buyer, 100 ether);
        vm.deal(anotherBuyer, 100 ether);
        vm.deal(seller, 10 ether);
    }

    // ==================== User Profile Tests ====================

    function testCreateUserProfile() public {
        string[] memory certifications = new string[](1);
        certifications[0] = "Organic Farming Certified";
        
        vm.startPrank(seller);
        vm.expectEmit(true, false, false, true);
        emit UserProfileCreated(seller, "John Farmer", true);
        
        farm.createUserProfile(
            "John Farmer", 
            "john@farm.com", 
            "California", 
            "Organic farmer since 2010", 
            true, 
            certifications
        );
        vm.stopPrank();
        
        // Verify profile was created
        (
            string memory name,
            string memory contactInfo,
            string memory location,
            string memory bio,
            bool isVerified,
            uint256 rating,
            uint256 reviewCount,
            ,
            uint256 createdAt,
            bool isSeller
        ) = farm.getUserProfile(seller);
        
        assertEq(name, "John Farmer");
        assertEq(contactInfo, "john@farm.com");
        assertEq(location, "California");
        assertEq(bio, "Organic farmer since 2010");
        assertEq(isVerified, false);
        assertEq(rating, 5); // Default rating
        assertEq(reviewCount, 0);
        assertGt(createdAt, 0);
        assertEq(isSeller, true);
    }

    function testUpdateUserProfile() public {
        // First create a profile
        string[] memory certifications = new string[](1);
        certifications[0] = "Organic Farming Certified";
        
        vm.startPrank(seller);
        farm.createUserProfile(
            "John Farmer", 
            "john@farm.com", 
            "California", 
            "Organic farmer since 2010", 
            true, 
            certifications
        );
        
        // Now update it
        string[] memory newCertifications = new string[](2);
        newCertifications[0] = "Organic Farming Certified";
        newCertifications[1] = "Sustainable Agriculture";
        
        vm.expectEmit(true, false, false, false);
        emit UserProfileUpdated(seller);
        
        farm.updateUserProfile(
            "John Smith", 
            "john.smith@farm.com", 
            "New York", 
            "Updated bio", 
            newCertifications
        );
        vm.stopPrank();
        
        // Verify profile was updated
        (
            string memory name,
            string memory contactInfo,
            string memory location,
            string memory bio,
            ,,,
            string[] memory updatedCerts,
            ,
        ) = farm.getUserProfile(seller);
        
        assertEq(name, "John Smith");
        assertEq(contactInfo, "john.smith@farm.com");
        assertEq(location, "New York");
        assertEq(bio, "Updated bio");
        assertEq(updatedCerts.length, 2);
        assertEq(updatedCerts[1], "Sustainable Agriculture");
    }

    function testToggleSellerStatus() public {
        // First create a profile
        string[] memory certifications = new string[](0);
        
        vm.startPrank(buyer);
        farm.createUserProfile(
            "Alice Buyer", 
            "alice@example.com", 
            "Texas", 
            "Regular buyer", 
            false, 
            certifications
        );
        
        // Verify initial status
        (,,,,,,,,,bool isSeller) = farm.getUserProfile(buyer);
        assertEq(isSeller, false);
        
        // Toggle status
        vm.expectEmit(true, false, false, false);
        emit UserProfileUpdated(buyer);
        farm.toggleSellerStatus();
        vm.stopPrank();
        
        // Verify status changed
        (,,,,,,,,,bool isSellerAfterToggle) = farm.getUserProfile(buyer);
        assertEq(isSellerAfterToggle, true);
    }

    // ==================== Product Management Tests ====================

    function testAddProduct() public {
        // Setup seller profile
        setupSellerProfile();
        
        vm.startPrank(seller);
        vm.expectEmit(true, true, false, true);
        emit ProductAdded(1, seller, productName);
        
        farm.addProduct(
            productName,
            productCategory,
            productPrice,
            productStock,
            productUnit,
            productDescription,
            productImages,
            isOrganic,
            harvestDate,
            nutritionFacts
        );
        vm.stopPrank();
        
        // Get products using the getter function
        Farm.Product[] memory sellerProducts = farm.getSellerProducts(seller);
        assertEq(sellerProducts.length, 1);
        assertEq(sellerProducts[0].id, 1);
        assertEq(sellerProducts[0].name, productName);
        assertEq(sellerProducts[0].price, productPrice);
        assertEq(sellerProducts[0].stockQuantity, productStock);
        assertEq(sellerProducts[0].isOrganic, isOrganic);
    }

    function testUpdateProduct() public {
        // Add a product first
        setupSellerWithProduct();
        
        // Update product
        string memory newName = "Premium Organic Apples";
        uint256 newPrice = 1.5 ether;
        
        vm.startPrank(seller);
        vm.expectEmit(true, false, false, false);
        emit ProductUpdated(1);
        
        farm.updateProduct(
            1,
            newName,
            productCategory,
            newPrice,
            productStock,
            productUnit,
            productDescription,
            productImages,
            true,
            isOrganic,
            harvestDate,
            nutritionFacts
        );
        vm.stopPrank();
        
        // Get updated product
        Farm.Product[] memory sellerProducts = farm.getSellerProducts(seller);
        assertEq(sellerProducts[0].name, newName);
        assertEq(sellerProducts[0].price, newPrice);
    }

    function testUpdateProductStock() public {
        // Add a product first
        setupSellerWithProduct();
        
        uint256 newStock = 50;
        
        vm.startPrank(seller);
        vm.expectEmit(true, false, false, false);
        emit ProductUpdated(1);
        
        farm.updateProductStock(1, newStock);
        vm.stopPrank();
        
        // Get updated product
        Farm.Product[] memory sellerProducts = farm.getSellerProducts(seller);
        assertEq(sellerProducts[0].stockQuantity, newStock);
    }

    function testToggleProductAvailability() public {
        // Add a product first
        setupSellerWithProduct();
        
        vm.startPrank(seller);
        vm.expectEmit(true, false, false, false);
        emit ProductUpdated(1);
        
        farm.toggleProductAvailability(1);
        vm.stopPrank();
        
        // Get updated product
        Farm.Product[] memory sellerProducts = farm.getSellerProducts(seller);
        assertEq(sellerProducts[0].isAvailable, false);
    }

    function testDeleteProduct() public {
        // Add a product first
        setupSellerWithProduct();
        
        vm.startPrank(seller);
        vm.expectEmit(true, false, false, false);
        emit ProductDeleted(1);
        
        farm.deleteProduct(1);
        vm.stopPrank();
        
        // Check seller products
        Farm.Product[] memory sellerProducts = farm.getSellerProducts(seller);
        assertEq(sellerProducts.length, 0);
    }

    // ==================== Order Management Tests ====================

    function testCreateOrder() public {
        // Add a product first
        setupSellerWithProduct();
        
        // Setup buyer profile
        setupBuyerProfile();
        
        uint256[] memory productIds = new uint256[](1);
        productIds[0] = 1;
        
        uint256[] memory quantities = new uint256[](1);
        quantities[0] = 5;
        
        string memory shippingAddress = "123 Main St, Anytown, USA";
        
        // Calculate total price (product price * quantity + shipping fee)
        uint256 totalPrice = (productPrice * quantities[0]) + 5 ether; // 5 ether is STANDARD_SHIPPING_FEE
        
        vm.startPrank(buyer);
        vm.expectEmit(true, true, true, false);
        emit OrderCreated(1, buyer, seller);
        
        farm.createOrder{value: totalPrice}(
            productIds,
            quantities,
            shippingAddress
        );
        vm.stopPrank();
        
        // Get buyer orders
        Farm.Order[] memory buyerOrders = farm.getBuyerOrders(buyer);
        assertEq(buyerOrders.length, 1);
        assertEq(buyerOrders[0].id, 1);
        assertEq(buyerOrders[0].buyer, buyer);
        assertEq(buyerOrders[0].seller, seller);
        assertEq(buyerOrders[0].totalPrice, totalPrice);
        assertEq(uint(buyerOrders[0].status), uint(Farm.OrderStatus.PAYMENT_ESCROWED));
        
        // Verify product stock was updated
        Farm.Product[] memory sellerProducts = farm.getSellerProducts(seller);
        assertEq(sellerProducts[0].stockQuantity, productStock - quantities[0]);
        assertEq(sellerProducts[0].soldCount, quantities[0]);
    }

    function testUpdateOrderStatus() public {
        // Create an order first
        setupOrderWithPayment();
        
        // Seller updates order to PROCESSING
        vm.startPrank(seller);
        vm.expectEmit(true, false, false, true);
        emit OrderStatusUpdated(1, Farm.OrderStatus.PROCESSING);
        
        farm.updateOrderStatus(1, Farm.OrderStatus.PROCESSING);
        vm.stopPrank();
        
        // Get updated order
        Farm.Order[] memory buyerOrders = farm.getBuyerOrders(buyer);
        assertEq(uint(buyerOrders[0].status), uint(Farm.OrderStatus.PROCESSING));
        
        // Seller updates order to IN_DELIVERY
        vm.startPrank(seller);
        farm.updateOrderStatus(1, Farm.OrderStatus.IN_DELIVERY);
        vm.stopPrank();
        
        // Get updated order
        buyerOrders = farm.getBuyerOrders(buyer);
        assertEq(uint(buyerOrders[0].status), uint(Farm.OrderStatus.IN_DELIVERY));
        
        // Seller updates order to DELIVERED
        vm.startPrank(seller);
        farm.updateOrderStatus(1, Farm.OrderStatus.DELIVERED);
        vm.stopPrank();
        
        // Get updated order
        buyerOrders = farm.getBuyerOrders(buyer);
        assertEq(uint(buyerOrders[0].status), uint(Farm.OrderStatus.DELIVERED));
        
        // Buyer completes the order
        vm.startPrank(buyer);
        vm.expectEmit(true, false, false, true);
        emit OrderStatusUpdated(1, Farm.OrderStatus.COMPLETED);
        vm.expectEmit(true, false, false, false);
        emit PaymentReleased(1, buyerOrders[0].totalPrice);
        
        farm.updateOrderStatus(1, Farm.OrderStatus.COMPLETED);
        vm.stopPrank();
        
        // Get updated order
        buyerOrders = farm.getBuyerOrders(buyer);
        assertEq(uint(buyerOrders[0].status), uint(Farm.OrderStatus.COMPLETED));
    }

    function testAddTrackingInfo() public {
        // Create an order and update to PROCESSING
        setupOrderInProcessing();
        
        string memory trackingInfo = "USPS123456789";
        
        vm.startPrank(seller);
        vm.expectEmit(true, false, false, false);
        emit OrderStatusUpdated(1, Farm.OrderStatus.PROCESSING);
        
        farm.addTrackingInfo(1, trackingInfo);
        vm.stopPrank();
        
        // Get updated order
        Farm.Order[] memory buyerOrders = farm.getBuyerOrders(buyer);
        assertEq(buyerOrders[0].trackingInfo, trackingInfo);
    }

    function testCreateDispute() public {
        // Create an order first
        setupOrderWithPayment();
        
        string memory reason = "Product not as described";
        
        vm.startPrank(buyer);
        vm.expectEmit(true, true, false, false);
        emit DisputeCreated(1, buyer);
        vm.expectEmit(true, false, false, true);
        emit OrderStatusUpdated(1, Farm.OrderStatus.DISPUTED);
        
        farm.createDispute(1, reason);
        vm.stopPrank();
        
        // Get updated order
        Farm.Order[] memory buyerOrders = farm.getBuyerOrders(buyer);
        assertEq(buyerOrders[0].isDisputed, true);
        assertEq(buyerOrders[0].disputeReason, reason);
        assertEq(uint(buyerOrders[0].status), uint(Farm.OrderStatus.DISPUTED));
    }

    function testResolveDisputeRefundBuyer() public {
        // Create a dispute first
        setupDisputedOrder();
        
        uint256 buyerBalanceBefore = buyer.balance;
        
        vm.expectEmit(true, false, false, true);
        emit DisputeResolved(1, Farm.DisputeResolution.REFUND_BUYER);
        vm.expectEmit(true, false, false, true);
        emit OrderStatusUpdated(1, Farm.OrderStatus.CANCELLED);
        
        farm.resolveDispute(1, Farm.DisputeResolution.REFUND_BUYER);
        
        // Get updated order
        Farm.Order[] memory buyerOrders = farm.getBuyerOrders(buyer);
        assertEq(uint(buyerOrders[0].status), uint(Farm.OrderStatus.CANCELLED));
        
        // Verify buyer was refunded (minus developer fee)
        uint256 buyerBalanceAfter = buyer.balance;
        uint256 expectedRefund = buyerOrders[0].totalPrice - (buyerOrders[0].totalPrice * 1 / 100); // 1% developer fee
        assertEq(buyerBalanceAfter, buyerBalanceBefore + expectedRefund);
    }

    function testResolveDisputeReleaseToSeller() public {
        // Create a dispute first
        setupDisputedOrder();
        
        uint256 sellerPendingBefore = farm.pendingWithdrawals(seller);
        
        vm.expectEmit(true, false, false, true);
        emit DisputeResolved(1, Farm.DisputeResolution.RELEASE_TO_SELLER);
        vm.expectEmit(true, false, false, true);
        emit OrderStatusUpdated(1, Farm.OrderStatus.COMPLETED);
        
        farm.resolveDispute(1, Farm.DisputeResolution.RELEASE_TO_SELLER);
        
        // Get updated order
        Farm.Order[] memory buyerOrders = farm.getBuyerOrders(buyer);
        assertEq(uint(buyerOrders[0].status), uint(Farm.OrderStatus.COMPLETED));
        
        // Verify seller's pending withdrawals remain the same (funds were already escrowed)
        uint256 sellerPendingAfter = farm.pendingWithdrawals(seller);
        assertEq(sellerPendingAfter, sellerPendingBefore);
    }

    function testWithdrawFunds() public {
        // Create and complete an order first
        setupCompletedOrder();
        
        uint256 sellerBalanceBefore = seller.balance;
        uint256 pendingAmount = farm.pendingWithdrawals(seller);
        
        vm.startPrank(seller);
        vm.expectEmit(true, false, false, false);
        emit WithdrawalMade(seller, pendingAmount);
        
        farm.withdrawFunds();
        vm.stopPrank();
        
        // Verify funds were withdrawn
        uint256 sellerBalanceAfter = seller.balance;
        assertEq(sellerBalanceAfter, sellerBalanceBefore + pendingAmount);
        assertEq(farm.pendingWithdrawals(seller), 0);
        assertEq(farm.sellerBalances(seller), pendingAmount);
    }

    // ==================== Review System Tests ====================

    function testSubmitReview() public {
        // Complete an order first
        setupCompletedOrder();
        
        uint256 rating = 4;
        string memory comment = "Great product, fast shipping!";
        
        vm.startPrank(buyer);
        vm.expectEmit(true, true, true, false);
        emit ReviewSubmitted(1, buyer, seller);
        
        farm.submitReview(
            seller,
            1, // productId
            1, // orderId
            rating,
            comment
        );
        vm.stopPrank();
        
        // Verify review was submitted
        Farm.Review[] memory productReviews = farm.getProductReviews(1);
        assertEq(productReviews.length, 1);
        assertEq(productReviews[0].reviewer, buyer);
        assertEq(productReviews[0].reviewee, seller);
        assertEq(productReviews[0].rating, rating);
        assertEq(productReviews[0].comment, comment);
        
        // Verify seller's rating was updated
        (,,,,, uint256 sellerRating, uint256 reviewCount,,,) = farm.getUserProfile(seller);
        assertEq(sellerRating, rating);
        assertEq(reviewCount, 1);
    }

    function testToggleFavoriteProduct() public {
        // Add a product first
        setupSellerWithProduct();
        setupBuyerProfile();
        
        vm.startPrank(buyer);
        farm.toggleFavoriteProduct(1);
        vm.stopPrank();
        
        // Verify product was added to favorites
        Farm.Product[] memory favorites = farm.getUserFavorites(buyer);
        assertEq(favorites.length, 1);
        assertEq(favorites[0].id, 1);
        
        // Toggle again to remove from favorites
        vm.startPrank(buyer);
        farm.toggleFavoriteProduct(1);
        vm.stopPrank();
        
        // Verify product was removed from favorites
        favorites = farm.getUserFavorites(buyer);
        assertEq(favorites.length, 0);
    }

    // ==================== Admin Functions Tests ====================

    function testPauseAndUnpause() public {
        // Pause the contract
        farm.pause();
        
        // Try to add a product while paused (should revert)
        setupSellerProfile();
        
        vm.startPrank(seller);
        vm.expectRevert("EnforcedPause()");
        farm.addProduct(
            productName,
            productCategory,
            productPrice,
            productStock,
            productUnit,
            productDescription,
            productImages,
            isOrganic,
            harvestDate,
            nutritionFacts
        );
        vm.stopPrank();
        
        // Unpause the contract
        farm.unpause();
        
        // Now adding a product should work
        vm.startPrank(seller);
        farm.addProduct(
            productName,
            productCategory,
            productPrice,
            productStock,
            productUnit,
            productDescription,
            productImages,
            isOrganic,
            harvestDate,
            nutritionFacts
        );
        vm.stopPrank();
        
        // Verify product was added
        Farm.Product[] memory sellerProducts = farm.getSellerProducts(seller);
        assertEq(sellerProducts.length, 1);
        assertEq(sellerProducts[0].id, 1);
    }

    function testSetDeveloperWallet() public {
        address newDeveloperWallet = makeAddr("newDeveloperWallet");
        
        farm.setDeveloperWallet(newDeveloperWallet);
        
        // Create an order to verify the new developer wallet receives fees
        setupSellerWithProduct();
        setupBuyerProfile();
        
        uint256[] memory productIds = new uint256[](1);
        productIds[0] = 1;
        
        uint256[] memory quantities = new uint256[](1);
        quantities[0] = 5;
        
        string memory shippingAddress = "123 Main St, Anytown, USA";
        
        uint256 totalPrice = (productPrice * quantities[0]) + 5 ether;
        
        vm.startPrank(buyer);
        farm.createOrder{value: totalPrice}(
            productIds,
            quantities,
            shippingAddress
        );
        vm.stopPrank();
        
        // Verify developer fee went to new wallet
        uint256 developerFee = (totalPrice * 1) / 100; // 1% fee
        assertEq(farm.pendingWithdrawals(newDeveloperWallet), developerFee);
    }

    function testVerifyUser() public {
        // Create a user profile
        setupSellerProfile();
        
        // Verify the user
        farm.verifyUser(seller);
        
        // Check if user is verified
        (,,,,bool isVerified,,,,,) = farm.getUserProfile(seller);
        assertEq(isVerified, true);
    }

    // ==================== Getter Functions Tests ====================

    function testGetSellerProducts() public {
        // Add multiple products
        setupSellerWithMultipleProducts();
        
        // Get seller products
        Farm.Product[] memory products = farm.getSellerProducts(seller);
        
        // Verify products
        assertEq(products.length, 2);
        assertEq(products[0].id, 1);
        assertEq(products[1].id, 2);
    }

    function testGetAvailableProducts() public {
        // Add multiple products with different availability
        setupSellerWithMultipleProducts();
        
        // Make one product unavailable
        vm.startPrank(seller);
        farm.toggleProductAvailability(1);
        vm.stopPrank();
        
        // Get available products
        Farm.Product[] memory availableProducts = farm.getAvailableProducts();
        
        // Verify only available products are returned
        assertEq(availableProducts.length, 1);
        assertEq(availableProducts[0].id, 2);
    }

    function testGetProductsByCategory() public {
        // Add products in different categories
        setupSellerWithMultipleCategories();
        
        // Get products by category
        Farm.Product[] memory fruitProducts = farm.getProductsByCategory("Fruits");
        Farm.Product[] memory vegProducts = farm.getProductsByCategory("Vegetables");
        
        // Verify products by category
        assertEq(fruitProducts.length, 1);
        assertEq(fruitProducts[0].id, 1);
        
        assertEq(vegProducts.length, 1);
        assertEq(vegProducts[0].id, 2);
    }

    function testGetBuyerOrders() public {
        // Create multiple orders
        setupMultipleOrders();
        
        // Get buyer orders
        Farm.Order[] memory buyerOrdersList = farm.getBuyerOrders(buyer);
        
        // Verify buyer orders
        assertEq(buyerOrdersList.length, 2);
        assertEq(buyerOrdersList[0].id, 1);
        assertEq(buyerOrdersList[1].id, 2);
    }

    function testGetSellerStats() public {
        // Complete an order
        setupCompletedOrder();
        
        // Get seller stats
        (
            uint256 totalProducts,
            uint256 totalOrders,
            uint256 totalRevenue,
            uint256 availableBalance
        ) = farm.getSellerStats(seller);
        
        // Verify stats
        assertEq(totalProducts, 1);
        assertEq(totalOrders, 1);
        assertGt(totalRevenue, 0);
        assertGt(availableBalance, 0);
    }

    function testGetBuyerStats() public {
        // Complete an order
        setupCompletedOrder();
        
        // Get buyer stats
        (
            uint256 totalOrders,
            uint256 totalSpent,
            uint256 availableBalance
        ) = farm.getBuyerStats(buyer);
        
        // Verify stats
        assertEq(totalOrders, 1);
        assertGt(totalSpent, 0);
        assertEq(availableBalance, 0);
    }

    function testGetPlatformStats() public {
        // Create an order
        setupOrderWithPayment();
        
        // Get platform stats
        (
            uint256 totalVolume,
            uint256 totalOrders,
            uint256 totalProducts
        ) = farm.getPlatformStats();
        
        // Verify stats
        assertGt(totalVolume, 0);
        assertEq(totalOrders, 1);
        assertEq(totalProducts, 1);
    }

    function testGetOrderCountByStatus() public {
        // Create orders with different statuses
        setupOrdersWithDifferentStatuses();
        
        // Get order counts by status
        uint256 newOrdersCount = farm.getOrderCountByStatus(Farm.OrderStatus.PAYMENT_ESCROWED);
        uint256 processingOrdersCount = farm.getOrderCountByStatus(Farm.OrderStatus.PROCESSING);
        uint256 completedOrdersCount = farm.getOrderCountByStatus(Farm.OrderStatus.COMPLETED);
        
        // Verify counts
        assertEq(newOrdersCount, 1);
        assertEq(processingOrdersCount, 1);
        assertEq(completedOrdersCount, 1);
    }

    // ==================== Helper Functions ====================

    function setupSellerProfile() internal {
        string[] memory certifications = new string[](1);
        certifications[0] = "Organic Farming Certified";
        
        vm.startPrank(seller);
        farm.createUserProfile(
            "John Farmer", 
            "john@farm.com", 
            "California", 
            "Organic farmer since 2010", 
            true, 
            certifications
        );
        vm.stopPrank();
    }

    function setupBuyerProfile() internal {
        string[] memory certifications = new string[](0);
        
        vm.startPrank(buyer);
        farm.createUserProfile(
            "Alice Buyer", 
            "alice@example.com", 
            "Texas", 
            "Regular buyer", 
            false, 
            certifications
        );
        vm.stopPrank();
    }

    function setupSellerWithProduct() internal {
        setupSellerProfile();
        
        vm.startPrank(seller);
        farm.addProduct(
            productName,
            productCategory,
            productPrice,
            productStock,
            productUnit,
            productDescription,
            productImages,
            isOrganic,
            harvestDate,
            nutritionFacts
        );
        vm.stopPrank();
    }

    function setupOrderWithPayment() internal {
        setupSellerWithProduct();
        setupBuyerProfile();
        
        uint256[] memory productIds = new uint256[](1);
        productIds[0] = 1;
        
        uint256[] memory quantities = new uint256[](1);
        quantities[0] = 5;
        
        string memory shippingAddress = "123 Main St, Anytown, USA";
        
        uint256 totalPrice = (productPrice * quantities[0]) + 5 ether;
        
        vm.startPrank(buyer);
        farm.createOrder{value: totalPrice}(
            productIds,
            quantities,
            shippingAddress
        );
        vm.stopPrank();
    }

    function setupOrderInProcessing() internal {
        setupOrderWithPayment();
        
        vm.startPrank(seller);
        farm.updateOrderStatus(1, Farm.OrderStatus.PROCESSING);
        vm.stopPrank();
    }

    function setupCompletedOrder() internal {
        setupOrderWithPayment();
        
        vm.startPrank(seller);
        farm.updateOrderStatus(1, Farm.OrderStatus.PROCESSING);
        farm.updateOrderStatus(1, Farm.OrderStatus.IN_DELIVERY);
        farm.updateOrderStatus(1, Farm.OrderStatus.DELIVERED);
        vm.stopPrank();
        
        vm.startPrank(buyer);
        farm.updateOrderStatus(1, Farm.OrderStatus.COMPLETED);
        vm.stopPrank();
    }

    function setupDisputedOrder() internal {
        setupOrderWithPayment();
        
        vm.startPrank(buyer);
        farm.createDispute(1, "Product not as described");
        vm.stopPrank();
    }

    function setupSellerWithMultipleProducts() internal {
        setupSellerProfile();
        
        vm.startPrank(seller);
        // Add first product
        farm.addProduct(
            productName,
            productCategory,
            productPrice,
            productStock,
            productUnit,
            productDescription,
            productImages,
            isOrganic,
            harvestDate,
            nutritionFacts
        );
        
        // Add second product
        farm.addProduct(
            "Organic Oranges",
            productCategory,
            0.5 ether,
            200,
            productUnit,
            "Fresh organic oranges",
            productImages,
            isOrganic,
            harvestDate,
            nutritionFacts
        );
        vm.stopPrank();
    }

    function setupSellerWithMultipleCategories() internal {
        setupSellerProfile();
        
        vm.startPrank(seller);
        // Add fruit product
        farm.addProduct(
            productName,
            "Fruits",
            productPrice,
            productStock,
            productUnit,
            productDescription,
            productImages,
            isOrganic,
            harvestDate,
            nutritionFacts
        );
        
        // Add vegetable product
        farm.addProduct(
            "Organic Carrots",
            "Vegetables",
            0.5 ether,
            200,
            productUnit,
            "Fresh organic carrots",
            productImages,
            isOrganic,
            harvestDate,
            nutritionFacts
        );
        vm.stopPrank();
    }

    function setupMultipleOrders() internal {
        setupSellerWithMultipleProducts();
        setupBuyerProfile();
        
        // First order
        uint256[] memory productIds1 = new uint256[](1);
        productIds1[0] = 1;
        
        uint256[] memory quantities1 = new uint256[](1);
        quantities1[0] = 5;
        
        string memory shippingAddress = "123 Main St, Anytown, USA";
        
        uint256 totalPrice1 = (productPrice * quantities1[0]) + 5 ether;
        
        vm.startPrank(buyer);
        farm.createOrder{value: totalPrice1}(
            productIds1,
            quantities1,
            shippingAddress
        );
        
        // Second order
        uint256[] memory productIds2 = new uint256[](1);
        productIds2[0] = 2;
        
        uint256[] memory quantities2 = new uint256[](1);
        quantities2[0] = 3;
        
        uint256 totalPrice2 = (0.5 ether * quantities2[0]) + 5 ether;
        
        farm.createOrder{value: totalPrice2}(
            productIds2,
            quantities2,
            shippingAddress
        );
        vm.stopPrank();
    }

    function setupOrdersWithDifferentStatuses() internal {
        setupSellerWithMultipleProducts();
        setupBuyerProfile();
        
        // Order 1 - PAYMENT_ESCROWED
        uint256[] memory productIds1 = new uint256[](1);
        productIds1[0] = 1;
        
        uint256[] memory quantities1 = new uint256[](1);
        quantities1[0] = 5;
        
        string memory shippingAddress = "123 Main St, Anytown, USA";
        
        uint256 totalPrice1 = (productPrice * quantities1[0]) + 5 ether;
        
        vm.startPrank(buyer);
        farm.createOrder{value: totalPrice1}(
            productIds1,
            quantities1,
            shippingAddress
        );
        vm.stopPrank();
        
        // Order 2 - PROCESSING
        uint256[] memory productIds2 = new uint256[](1);
        productIds2[0] = 2;
        
        uint256[] memory quantities2 = new uint256[](1);
        quantities2[0] = 3;
        
        uint256 totalPrice2 = (0.5 ether * quantities2[0]) + 5 ether;
        
        vm.startPrank(buyer);
        farm.createOrder{value: totalPrice2}(
            productIds2,
            quantities2,
            shippingAddress
        );
        vm.stopPrank();
        
        vm.startPrank(seller);
        farm.updateOrderStatus(2, Farm.OrderStatus.PROCESSING);
        vm.stopPrank();
        
        // Order 3 - COMPLETED
        vm.deal(anotherBuyer, 100 ether);
        
        string[] memory certifications = new string[](0);
        vm.startPrank(anotherBuyer);
        farm.createUserProfile(
            "Bob Buyer", 
            "bob@example.com", 
            "Florida", 
            "Another buyer", 
            false, 
            certifications
        );
        
        uint256[] memory productIds3 = new uint256[](1);
        productIds3[0] = 1;
        
        uint256[] memory quantities3 = new uint256[](1);
        quantities3[0] = 2;
        
        uint256 totalPrice3 = (productPrice * quantities3[0]) + 5 ether;
        
        farm.createOrder{value: totalPrice3}(
            productIds3,
            quantities3,
            shippingAddress
        );
        vm.stopPrank();
        
        vm.startPrank(seller);
        farm.updateOrderStatus(3, Farm.OrderStatus.PROCESSING);
        farm.updateOrderStatus(3, Farm.OrderStatus.IN_DELIVERY);
        farm.updateOrderStatus(3, Farm.OrderStatus.DELIVERED);
        vm.stopPrank();
        
        vm.startPrank(anotherBuyer);
        farm.updateOrderStatus(3, Farm.OrderStatus.COMPLETED);
        vm.stopPrank();
    }
}