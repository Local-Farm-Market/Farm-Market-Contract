// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Farm.sol";

contract FarmEscrowTest is Test {
    FarmEscrow public farmEscrow;

    // Test accounts
    address public owner = address(1);
    address public developerWallet = address(2);
    address public seller = address(3);
    address public buyer = address(4);
    address public anotherBuyer = address(5);
    address public anotherSeller = address(6);

    // Test data
    uint256 public constant INITIAL_BALANCE = 100 ether;
    uint256 public constant PRODUCT_PRICE = 1 ether;
    uint256 public constant PRODUCT_QUANTITY = 10;
    uint256 public constant STANDARD_SHIPPING_FEE = 5 ether;

    // Events to test - declare ALL events from the contract that we'll be testing
    event UserProfileCreated(address indexed user, string name, bool isSeller, string farmName);
    event UserProfileUpdated(address indexed user);
    event ProductAdded(uint256 indexed productId, address indexed seller, string name);
    event ProductUpdated(uint256 indexed productId);
    event OrderCreated(uint256 indexed orderId, address indexed buyer, address indexed seller);
    event OrderStatusUpdated(uint256 indexed orderId, FarmEscrow.OrderStatus status);
    event EscrowCreated(uint256 indexed orderId, uint256 amount, uint256 developerFee);
    event EscrowClaimable(uint256 indexed orderId, address indexed seller, uint256 amount);
    event EscrowClaimed(uint256 indexed orderId, address indexed seller, uint256 amount);
    event CartItemAdded(address indexed user, uint256 productId, uint256 quantity);
    event CartItemRemoved(address indexed user, uint256 productId);
    event CartItemQuantityUpdated(address indexed user, uint256 productId, uint256 quantity);
    event CartCleared(address indexed user);
    event DeveloperFeePaid(uint256 indexed orderId, uint256 amount);
    event EscrowRefunded(uint256 indexed orderId, address indexed buyer, uint256 amount);
    event PaymentReleased(uint256 indexed orderId, uint256 amount);
    event WithdrawalMade(address indexed seller, uint256 amount);
    event FundsDeposited(address indexed user, uint256 amount);
    event EscrowReleased(uint256 indexed orderId, address indexed seller, uint256 amount);
    event ProductDeleted(uint256 indexed productId);

    function setUp() public {
        // Deploy contract with developer wallet
        vm.prank(owner);
        farmEscrow = new FarmEscrow(developerWallet);

        // Fund test accounts
        vm.deal(seller, INITIAL_BALANCE);
        vm.deal(buyer, INITIAL_BALANCE);
        vm.deal(anotherBuyer, INITIAL_BALANCE);
        vm.deal(anotherSeller, INITIAL_BALANCE);

        // Create seller profile
        vm.startPrank(seller);
        farmEscrow.createUserProfile(
            "Farmer John",
            "john@example.com",
            "Farm County",
            "Organic farmer since 2010",
            true,
            "John's Organic Farm",
            "We grow the best organic produce"
        );
        vm.stopPrank();

        // Create buyer profile
        vm.startPrank(buyer);
        farmEscrow.createUserProfile(
            "Consumer Alice", "alice@example.com", "City Center", "Health enthusiast", false, "", ""
        );
        vm.stopPrank();

        // Create another seller profile
        vm.startPrank(anotherSeller);
        farmEscrow.createUserProfile(
            "Farmer Jane",
            "jane@example.com",
            "Countryside",
            "Family farm since 1950",
            true,
            "Jane's Family Farm",
            "Traditional farming methods"
        );
        vm.stopPrank();

        // Create another buyer profile
        vm.startPrank(anotherBuyer);
        farmEscrow.createUserProfile("Consumer Bob", "bob@example.com", "Suburb", "Cooking enthusiast", false, "", "");
        vm.stopPrank();
    }

    // ==================== User Profile Tests ====================

    function testCreateUserProfile() public {
        address newUser = address(7);
        vm.deal(newUser, INITIAL_BALANCE);

        vm.startPrank(newUser);

        vm.expectEmit(true, false, false, true);
        emit UserProfileCreated(newUser, "New Farmer", true, "New Farm");

        farmEscrow.createUserProfile(
            "New Farmer", "new@example.com", "New Location", "New bio", true, "New Farm", "New farm description"
        );

        // Verify profile was created correctly
        (
            string memory name,
            string memory contactInfo,
            string memory location,
            string memory bio,
            bool isVerified,
            uint256 rating,
            uint256 reviewCount,
            bool isSeller,
            string memory farmName,
            string memory farmDescription
        ) = farmEscrow.userProfiles(newUser);

        assertEq(name, "New Farmer");
        assertEq(contactInfo, "new@example.com");
        assertEq(location, "New Location");
        assertEq(bio, "New bio");
        assertEq(isVerified, false);
        assertEq(rating, 5); // Default rating
        assertEq(reviewCount, 0);
        assertEq(isSeller, true);
        assertEq(farmName, "New Farm");
        assertEq(farmDescription, "New farm description");

        vm.stopPrank();
    }

    function testCreateUserProfileEmptyName() public {
        address newUser = address(7);
        vm.deal(newUser, INITIAL_BALANCE);

        vm.startPrank(newUser);

        vm.expectRevert("Name cannot be empty");

        farmEscrow.createUserProfile(
            "", "new@example.com", "New Location", "New bio", true, "New Farm", "New farm description"
        );

        vm.stopPrank();
    }

    function testUpdateUserProfile() public {
        vm.startPrank(seller);

        vm.expectEmit(true, false, false, false);
        emit UserProfileUpdated(seller);

        farmEscrow.updateUserProfile(
            "Updated Farmer John",
            "updated-john@example.com",
            "Updated Farm County",
            "Updated bio",
            "Updated Farm Name",
            "Updated farm description"
        );

        // Verify profile was updated correctly
        (
            string memory name,
            string memory contactInfo,
            string memory location,
            string memory bio,
            ,
            ,
            ,
            ,
            string memory farmName,
            string memory farmDescription
        ) = farmEscrow.userProfiles(seller);

        assertEq(name, "Updated Farmer John");
        assertEq(contactInfo, "updated-john@example.com");
        assertEq(location, "Updated Farm County");
        assertEq(bio, "Updated bio");
        assertEq(farmName, "Updated Farm Name");
        assertEq(farmDescription, "Updated farm description");

        vm.stopPrank();
    }

    function testUpdateNonExistentProfile() public {
        address nonExistentUser = address(99);
        vm.deal(nonExistentUser, INITIAL_BALANCE);

        vm.startPrank(nonExistentUser);

        vm.expectRevert("Profile does not exist");

        farmEscrow.updateUserProfile("Name", "contact", "location", "bio", "farm", "description");

        vm.stopPrank();
    }

    // ==================== Product Management Tests ====================

    function testAddProduct() public {
        vm.startPrank(seller);

        string[] memory testImageUrls = new string[](2);
        testImageUrls[0] = "https://example.com/image1.jpg";
        testImageUrls[1] = "https://example.com/image2.jpg";

        vm.expectEmit(true, true, false, true);
        emit ProductAdded(1, seller, "Organic Apples");

        farmEscrow.addProduct(
            "Organic Apples",
            "Fruits",
            PRODUCT_PRICE,
            PRODUCT_QUANTITY,
            "kg",
            "Fresh organic apples",
            testImageUrls,
            true
        );

        // Get product details and verify
        FarmEscrow.Product memory product = getProductDetails(1);

        assertEq(product.id, 1);
        assertEq(product.seller, seller);
        assertEq(product.name, "Organic Apples");
        assertEq(product.category, "Fruits");
        assertEq(product.price, PRODUCT_PRICE);
        assertEq(product.stockQuantity, PRODUCT_QUANTITY);
        assertEq(product.unit, "kg");
        assertEq(product.description, "Fresh organic apples");
        assertEq(product.isAvailable, true);
        assertEq(product.isOrganic, true);
        assertEq(product.soldCount, 0);

        // Verify seller products mapping
        uint256[] memory sellerProductIds = farmEscrow.getUserProducts(seller);
        assertEq(sellerProductIds.length, 1);
        assertEq(sellerProductIds[0], 1);

        // Verify category mapping
        uint256[] memory categoryProducts = farmEscrow.getProductsByCategory("Fruits");
        assertEq(categoryProducts.length, 1);
        assertEq(categoryProducts[0], 1);

        vm.stopPrank();
    }

    function testAddProductNonSeller() public {
        vm.startPrank(buyer);

        string[] memory testImageUrls = new string[](1);
        testImageUrls[0] = "https://example.com/image.jpg";

        vm.expectRevert("Only sellers can perform this action");

        farmEscrow.addProduct(
            "Organic Apples",
            "Fruits",
            PRODUCT_PRICE,
            PRODUCT_QUANTITY,
            "kg",
            "Fresh organic apples",
            testImageUrls,
            true
        );

        vm.stopPrank();
    }

    function testAddProductEmptyName() public {
        vm.startPrank(seller);

        string[] memory testImageUrls = new string[](1);
        testImageUrls[0] = "https://example.com/image.jpg";

        vm.expectRevert("Name cannot be empty");

        farmEscrow.addProduct(
            "", "Fruits", PRODUCT_PRICE, PRODUCT_QUANTITY, "kg", "Fresh organic apples", testImageUrls, true
        );

        vm.stopPrank();
    }

    function testAddProductZeroPrice() public {
        vm.startPrank(seller);

        string[] memory testImageUrls = new string[](1);
        testImageUrls[0] = "https://example.com/image.jpg";

        vm.expectRevert("Price must be greater than zero");

        farmEscrow.addProduct(
            "Organic Apples", "Fruits", 0, PRODUCT_QUANTITY, "kg", "Fresh organic apples", testImageUrls, true
        );

        vm.stopPrank();
    }

    function testAddProductZeroQuantity() public {
        vm.startPrank(seller);

        string[] memory testImageUrls = new string[](1);
        testImageUrls[0] = "https://example.com/image.jpg";

        vm.expectRevert("Stock quantity must be greater than zero");

        farmEscrow.addProduct(
            "Organic Apples", "Fruits", PRODUCT_PRICE, 0, "kg", "Fresh organic apples", testImageUrls, true
        );

        vm.stopPrank();
    }

    function testUpdateProduct() public {
        // First add a product
        vm.startPrank(seller);

        string[] memory testImageUrls = new string[](1);
        testImageUrls[0] = "https://example.com/image1.jpg";

        farmEscrow.addProduct(
            "Organic Apples",
            "Fruits",
            PRODUCT_PRICE,
            PRODUCT_QUANTITY,
            "kg",
            "Fresh organic apples",
            testImageUrls,
            true
        );

        // Now update the product
        string[] memory updatedImageUrls = new string[](2);
        updatedImageUrls[0] = "https://example.com/updated1.jpg";
        updatedImageUrls[1] = "https://example.com/updated2.jpg";

        vm.expectEmit(true, false, false, false);
        emit ProductUpdated(1);

        farmEscrow.updateProduct(
            1,
            "Updated Organic Apples",
            "Updated Category",
            PRODUCT_PRICE * 2,
            PRODUCT_QUANTITY * 2,
            "lb",
            "Updated description",
            updatedImageUrls,
            true,
            false
        );

        // Get product details and verify
        FarmEscrow.Product memory product = getProductDetails(1);

        assertEq(product.name, "Updated Organic Apples");
        assertEq(product.category, "Updated Category");
        assertEq(product.price, PRODUCT_PRICE * 2);
        assertEq(product.stockQuantity, PRODUCT_QUANTITY * 2);
        assertEq(product.unit, "lb");
        assertEq(product.description, "Updated description");
        assertEq(product.isAvailable, true);
        assertEq(product.isOrganic, false);

        // Verify category mapping was updated
        uint256[] memory oldCategoryProducts = farmEscrow.getProductsByCategory("Fruits");
        assertEq(oldCategoryProducts.length, 0);

        uint256[] memory newCategoryProducts = farmEscrow.getProductsByCategory("Updated Category");
        assertEq(newCategoryProducts.length, 1);
        assertEq(newCategoryProducts[0], 1);

        vm.stopPrank();
    }

    function testUpdateProductNonExistent() public {
        vm.startPrank(seller);

        string[] memory testImageUrls = new string[](1);
        testImageUrls[0] = "https://example.com/image.jpg";

        vm.expectRevert("Product does not exist");

        farmEscrow.updateProduct(
            999, // Non-existent product ID
            "Updated Product",
            "Updated Category",
            PRODUCT_PRICE,
            PRODUCT_QUANTITY,
            "kg",
            "Updated description",
            testImageUrls,
            true,
            true
        );

        vm.stopPrank();
    }

    function testUpdateProductNotSeller() public {
        // First add a product as seller
        vm.startPrank(seller);

        string[] memory testImageUrls = new string[](1);
        testImageUrls[0] = "https://example.com/image.jpg";

        farmEscrow.addProduct(
            "Organic Apples",
            "Fruits",
            PRODUCT_PRICE,
            PRODUCT_QUANTITY,
            "kg",
            "Fresh organic apples",
            testImageUrls,
            true
        );

        vm.stopPrank();

        // Try to update as another seller
        vm.startPrank(anotherSeller);

        vm.expectRevert("Only seller can update");

        farmEscrow.updateProduct(
            1,
            "Updated Product",
            "Updated Category",
            PRODUCT_PRICE,
            PRODUCT_QUANTITY,
            "kg",
            "Updated description",
            testImageUrls,
            true,
            true
        );

        vm.stopPrank();
    }

    // ==================== Cart Management Tests ====================

    function testAddToCart() public {
        // First add a product as seller
        vm.startPrank(seller);

        string[] memory testImageUrls = new string[](1);
        testImageUrls[0] = "https://example.com/image.jpg";

        farmEscrow.addProduct(
            "Organic Apples",
            "Fruits",
            PRODUCT_PRICE,
            PRODUCT_QUANTITY,
            "kg",
            "Fresh organic apples",
            testImageUrls,
            true
        );

        vm.stopPrank();

        // Add product to cart as buyer
        vm.startPrank(buyer);

        vm.expectEmit(true, true, false, true);
        emit CartItemAdded(buyer, 1, 2);

        farmEscrow.addToCart(1, 2);

        // Verify cart item was added
        FarmEscrow.CartItem[] memory cartItems = farmEscrow.getCartItems();
        assertEq(cartItems.length, 1);
        assertEq(cartItems[0].productId, 1);
        assertEq(cartItems[0].quantity, 2);

        vm.stopPrank();
    }

    function testAddToCartNonExistentProduct() public {
        vm.startPrank(buyer);

        vm.expectRevert("Product does not exist");

        farmEscrow.addToCart(999, 1);

        vm.stopPrank();
    }

    function testAddToCartInsufficientStock() public {
        // First add a product as seller
        vm.startPrank(seller);

        string[] memory testImageUrls = new string[](1);
        testImageUrls[0] = "https://example.com/image.jpg";

        farmEscrow.addProduct(
            "Organic Apples",
            "Fruits",
            PRODUCT_PRICE,
            PRODUCT_QUANTITY,
            "kg",
            "Fresh organic apples",
            testImageUrls,
            true
        );

        vm.stopPrank();

        // Try to add more than available stock
        vm.startPrank(buyer);

        vm.expectRevert("Insufficient stock");

        farmEscrow.addToCart(1, PRODUCT_QUANTITY + 1);

        vm.stopPrank();
    }

    function testAddToCartZeroQuantity() public {
        // First add a product as seller
        vm.startPrank(seller);

        string[] memory testImageUrls = new string[](1);
        testImageUrls[0] = "https://example.com/image.jpg";

        farmEscrow.addProduct(
            "Organic Apples",
            "Fruits",
            PRODUCT_PRICE,
            PRODUCT_QUANTITY,
            "kg",
            "Fresh organic apples",
            testImageUrls,
            true
        );

        vm.stopPrank();

        // Try to add zero quantity
        vm.startPrank(buyer);

        vm.expectRevert("Quantity must be greater than zero");

        farmEscrow.addToCart(1, 0);

        vm.stopPrank();
    }

    function testAddToCartExistingItem() public {
        // First add a product as seller
        vm.startPrank(seller);

        string[] memory testImageUrls = new string[](1);
        testImageUrls[0] = "https://example.com/image.jpg";

        farmEscrow.addProduct(
            "Organic Apples",
            "Fruits",
            PRODUCT_PRICE,
            PRODUCT_QUANTITY,
            "kg",
            "Fresh organic apples",
            testImageUrls,
            true
        );

        vm.stopPrank();

        // Add product to cart as buyer
        vm.startPrank(buyer);

        farmEscrow.addToCart(1, 2);

        // Add same product again
        vm.expectEmit(true, true, false, true);
        emit CartItemQuantityUpdated(buyer, 1, 5);

        farmEscrow.addToCart(1, 3);

        // Verify cart item was updated
        FarmEscrow.CartItem[] memory cartItems = farmEscrow.getCartItems();
        assertEq(cartItems.length, 1);
        assertEq(cartItems[0].productId, 1);
        assertEq(cartItems[0].quantity, 5);

        vm.stopPrank();
    }

    function testUpdateCartItemQuantity() public {
        // First add a product as seller
        vm.startPrank(seller);

        string[] memory testImageUrls = new string[](1);
        testImageUrls[0] = "https://example.com/image.jpg";

        farmEscrow.addProduct(
            "Organic Apples",
            "Fruits",
            PRODUCT_PRICE,
            PRODUCT_QUANTITY,
            "kg",
            "Fresh organic apples",
            testImageUrls,
            true
        );

        vm.stopPrank();

        // Add product to cart as buyer
        vm.startPrank(buyer);

        farmEscrow.addToCart(1, 2);

        // Update quantity
        vm.expectEmit(true, true, false, true);
        emit CartItemQuantityUpdated(buyer, 1, 4);

        farmEscrow.updateCartItemQuantity(1, 4);

        // Verify cart item was updated
        FarmEscrow.CartItem[] memory cartItems = farmEscrow.getCartItems();
        assertEq(cartItems.length, 1);
        assertEq(cartItems[0].productId, 1);
        assertEq(cartItems[0].quantity, 4);

        vm.stopPrank();
    }

    function testUpdateCartItemQuantityProductNotInCart() public {
        // First add a product as seller
        vm.startPrank(seller);

        string[] memory testImageUrls = new string[](1);
        testImageUrls[0] = "https://example.com/image.jpg";

        farmEscrow.addProduct(
            "Organic Apples",
            "Fruits",
            PRODUCT_PRICE,
            PRODUCT_QUANTITY,
            "kg",
            "Fresh organic apples",
            testImageUrls,
            true
        );

        vm.stopPrank();

        // Try to update quantity of product not in cart
        vm.startPrank(buyer);

        vm.expectRevert("Product not in cart");

        farmEscrow.updateCartItemQuantity(1, 4);

        vm.stopPrank();
    }

    function testRemoveFromCart() public {
        // First add a product as seller
        vm.startPrank(seller);

        string[] memory testImageUrls = new string[](1);
        testImageUrls[0] = "https://example.com/image.jpg";

        farmEscrow.addProduct(
            "Organic Apples",
            "Fruits",
            PRODUCT_PRICE,
            PRODUCT_QUANTITY,
            "kg",
            "Fresh organic apples",
            testImageUrls,
            true
        );

        vm.stopPrank();

        // Add product to cart as buyer
        vm.startPrank(buyer);

        farmEscrow.addToCart(1, 2);

        // Remove from cart
        vm.expectEmit(true, true, false, false);
        emit CartItemRemoved(buyer, 1);

        farmEscrow.removeFromCart(1);

        // Verify cart is empty
        FarmEscrow.CartItem[] memory cartItems = farmEscrow.getCartItems();
        assertEq(cartItems.length, 0);

        vm.stopPrank();
    }

    function testRemoveFromCartProductNotInCart() public {
        vm.startPrank(buyer);

        vm.expectRevert("Product not in cart");

        farmEscrow.removeFromCart(1);

        vm.stopPrank();
    }

    function testClearCart() public {
        // First add a product as seller
        vm.startPrank(seller);

        string[] memory testImageUrls = new string[](1);
        testImageUrls[0] = "https://example.com/image.jpg";

        farmEscrow.addProduct(
            "Organic Apples",
            "Fruits",
            PRODUCT_PRICE,
            PRODUCT_QUANTITY,
            "kg",
            "Fresh organic apples",
            testImageUrls,
            true
        );

        farmEscrow.addProduct(
            "Organic Bananas",
            "Fruits",
            PRODUCT_PRICE,
            PRODUCT_QUANTITY,
            "kg",
            "Fresh organic bananas",
            testImageUrls,
            true
        );

        vm.stopPrank();

        // Add products to cart as buyer
        vm.startPrank(buyer);

        farmEscrow.addToCart(1, 2);
        farmEscrow.addToCart(2, 3);

        // Clear cart
        vm.expectEmit(true, false, false, false);
        emit CartCleared(buyer);

        farmEscrow.clearCart();

        // Verify cart is empty
        FarmEscrow.CartItem[] memory cartItems = farmEscrow.getCartItems();
        assertEq(cartItems.length, 0);

        vm.stopPrank();
    }

    function testGetCartTotal() public {
        // First add products as seller
        vm.startPrank(seller);

        string[] memory testImageUrls = new string[](1);
        testImageUrls[0] = "https://example.com/image.jpg";

        farmEscrow.addProduct(
            "Organic Apples",
            "Fruits",
            PRODUCT_PRICE,
            PRODUCT_QUANTITY,
            "kg",
            "Fresh organic apples",
            testImageUrls,
            true
        );

        farmEscrow.addProduct(
            "Organic Bananas",
            "Fruits",
            PRODUCT_PRICE * 2,
            PRODUCT_QUANTITY,
            "kg",
            "Fresh organic bananas",
            testImageUrls,
            true
        );

        vm.stopPrank();

        // Add products to cart as buyer
        vm.startPrank(buyer);

        farmEscrow.addToCart(1, 2); // 2 * PRODUCT_PRICE
        farmEscrow.addToCart(2, 3); // 3 * PRODUCT_PRICE * 2

        // Get cart total
        uint256 total = farmEscrow.getCartTotal();

        // Verify total
        uint256 expectedTotal = (2 * PRODUCT_PRICE) + (3 * PRODUCT_PRICE * 2);
        assertEq(total, expectedTotal);

        vm.stopPrank();
    }

    // ==================== Order Management Tests ====================

    function testCreateOrderFromCart() public {
        // First add a product as seller
        vm.startPrank(seller);

        string[] memory testImageUrls = new string[](1);
        testImageUrls[0] = "https://example.com/image.jpg";

        farmEscrow.addProduct(
            "Organic Apples",
            "Fruits",
            PRODUCT_PRICE,
            PRODUCT_QUANTITY,
            "kg",
            "Fresh organic apples",
            testImageUrls,
            true
        );

        vm.stopPrank();

        // Add product to cart as buyer
        vm.startPrank(buyer);

        farmEscrow.addToCart(1, 2);

        // Calculate expected total
        uint256 productTotal = 2 * PRODUCT_PRICE;
        uint256 totalWithShipping = productTotal + STANDARD_SHIPPING_FEE;

        // Create order from cart
        vm.expectEmit(true, true, true, false);
        emit OrderCreated(1, buyer, seller);

        vm.expectEmit(true, false, false, false);
        emit EscrowCreated(1, productTotal, productTotal / 100); // 1% developer fee

        vm.expectEmit(true, false, false, false);
        emit CartCleared(buyer);

        farmEscrow.createOrderFromCart{value: totalWithShipping}("123 Buyer Street, City");

        // Verify order was created
        (
            uint256 id,
            address orderBuyer,
            address orderSeller,
            uint256[] memory productIds,
            uint256[] memory quantities,
            uint256 totalPrice,
            uint256 shippingFee,
            FarmEscrow.OrderStatus status,
            string memory shippingAddress,
            string memory trackingInfo
        ) = farmEscrow.getOrderDetails(1);

        assertEq(id, 1);
        assertEq(orderBuyer, buyer);
        assertEq(orderSeller, seller);
        assertEq(productIds.length, 1);
        assertEq(productIds[0], 1);
        assertEq(quantities.length, 1);
        assertEq(quantities[0], 2);
        assertEq(totalPrice, productTotal);
        assertEq(shippingFee, STANDARD_SHIPPING_FEE);
        assertEq(uint256(status), uint256(FarmEscrow.OrderStatus.PAID));
        assertEq(shippingAddress, "123 Buyer Street, City");
        assertEq(trackingInfo, "");

        // Verify escrow was created
        (
            uint256 amount,
            uint256 developerFee,
            uint256 sellerAmount,
            bool isReleased,
            bool isRefunded,
            bool isClaimable,
            bool isClaimed,
            uint256 releasedAt
        ) = farmEscrow.getEscrowDetails(1);

        assertEq(amount, productTotal);
        assertEq(developerFee, productTotal / 100); // 1% developer fee
        assertEq(sellerAmount, productTotal - (productTotal / 100));
        assertEq(isReleased, false);
        assertEq(isRefunded, false);
        assertEq(isClaimable, false);
        assertEq(isClaimed, false);
        assertEq(releasedAt, 0);

        // Verify product stock was updated
        FarmEscrow.Product memory product = getProductDetails(1);

        assertEq(product.stockQuantity, PRODUCT_QUANTITY - 2);
        assertEq(product.soldCount, 2);

        // Verify cart is empty
        FarmEscrow.CartItem[] memory cartItems = farmEscrow.getCartItems();
        assertEq(cartItems.length, 0);

        vm.stopPrank();
    }

    function testCreateOrderFromEmptyCart() public {
        vm.startPrank(buyer);

        vm.expectRevert("Cart is empty");

        farmEscrow.createOrderFromCart{value: STANDARD_SHIPPING_FEE}("123 Buyer Street, City");

        vm.stopPrank();
    }

    function testCreateOrderFromCartIncorrectPayment() public {
        // First add a product as seller
        vm.startPrank(seller);

        string[] memory testImageUrls = new string[](1);
        testImageUrls[0] = "https://example.com/image.jpg";

        farmEscrow.addProduct(
            "Organic Apples",
            "Fruits",
            PRODUCT_PRICE,
            PRODUCT_QUANTITY,
            "kg",
            "Fresh organic apples",
            testImageUrls,
            true
        );

        vm.stopPrank();

        // Add product to cart as buyer
        vm.startPrank(buyer);

        farmEscrow.addToCart(1, 2);

        // Try to create order with incorrect payment
        vm.expectRevert("Incorrect payment");

        farmEscrow.createOrderFromCart{value: PRODUCT_PRICE}("123 Buyer Street, City");

        vm.stopPrank();
    }

    function testAddShippingInfo() public {
        // First create an order
        vm.startPrank(seller);

        string[] memory testImageUrls = new string[](1);
        testImageUrls[0] = "https://example.com/image.jpg";

        farmEscrow.addProduct(
            "Organic Apples",
            "Fruits",
            PRODUCT_PRICE,
            PRODUCT_QUANTITY,
            "kg",
            "Fresh organic apples",
            testImageUrls,
            true
        );

        vm.stopPrank();

        vm.startPrank(buyer);

        farmEscrow.addToCart(1, 2);

        uint256 productTotal = 2 * PRODUCT_PRICE;
        uint256 totalWithShipping = productTotal + STANDARD_SHIPPING_FEE;

        farmEscrow.createOrderFromCart{value: totalWithShipping}("123 Buyer Street, City");

        vm.stopPrank();

        // Add shipping info as seller
        vm.startPrank(seller);

        vm.expectEmit(true, false, false, false);
        emit OrderStatusUpdated(1, FarmEscrow.OrderStatus.SHIPPED);

        farmEscrow.addShippingInfo(1, "Tracking123");

        // Verify shipping info was added
        (
            , // id
            , // buyer
            , // seller
            , // productIds
            , // quantities
            , // totalPrice
            , // shippingFee
            FarmEscrow.OrderStatus status,
            , // shippingAddress
            string memory trackingInfo
        ) = farmEscrow.getOrderDetails(1);

        assertEq(uint256(status), uint256(FarmEscrow.OrderStatus.SHIPPED));
        assertEq(trackingInfo, "Tracking123");

        vm.stopPrank();
    }

    function testAddShippingInfoNonSeller() public {
        // First create an order
        vm.startPrank(seller);

        string[] memory testImageUrls = new string[](1);
        testImageUrls[0] = "https://example.com/image.jpg";

        farmEscrow.addProduct(
            "Organic Apples",
            "Fruits",
            PRODUCT_PRICE,
            PRODUCT_QUANTITY,
            "kg",
            "Fresh organic apples",
            testImageUrls,
            true
        );

        vm.stopPrank();

        vm.startPrank(buyer);

        farmEscrow.addToCart(1, 2);

        uint256 productTotal = 2 * PRODUCT_PRICE;
        uint256 totalWithShipping = productTotal + STANDARD_SHIPPING_FEE;

        farmEscrow.createOrderFromCart{value: totalWithShipping}("123 Buyer Street, City");

        // Try to add shipping info as buyer
        vm.expectRevert("Only seller can update shipping info");

        farmEscrow.addShippingInfo(1, "Tracking123");

        vm.stopPrank();
    }

    function testUpdateOrderStatus() public {
        // First create an order
        vm.startPrank(seller);

        string[] memory testImageUrls = new string[](1);
        testImageUrls[0] = "https://example.com/image.jpg";

        farmEscrow.addProduct(
            "Organic Apples",
            "Fruits",
            PRODUCT_PRICE,
            PRODUCT_QUANTITY,
            "kg",
            "Fresh organic apples",
            testImageUrls,
            true
        );

        vm.stopPrank();

        vm.startPrank(buyer);

        farmEscrow.addToCart(1, 2);

        uint256 productTotal = 2 * PRODUCT_PRICE;
        uint256 totalWithShipping = productTotal + STANDARD_SHIPPING_FEE;

        farmEscrow.createOrderFromCart{value: totalWithShipping}("123 Buyer Street, City");

        vm.stopPrank();

        // Update order status as seller
        vm.startPrank(seller);

        // Add shipping info first
        farmEscrow.addShippingInfo(1, "Tracking123");

        // Update to IN_DELIVERY
        vm.expectEmit(true, false, false, false);
        emit OrderStatusUpdated(1, FarmEscrow.OrderStatus.IN_DELIVERY);

        farmEscrow.updateOrderStatus(1, FarmEscrow.OrderStatus.IN_DELIVERY);

        // Verify status was updated
        (,,,,,,, FarmEscrow.OrderStatus status,,) = farmEscrow.getOrderDetails(1);

        assertEq(uint256(status), uint256(FarmEscrow.OrderStatus.IN_DELIVERY));

        // Update to DELIVERED
        vm.expectEmit(true, false, false, false);
        emit OrderStatusUpdated(1, FarmEscrow.OrderStatus.DELIVERED);

        farmEscrow.updateOrderStatus(1, FarmEscrow.OrderStatus.DELIVERED);

        // Verify status was updated
        (,,,,,,, status,,) = farmEscrow.getOrderDetails(1);

        assertEq(uint256(status), uint256(FarmEscrow.OrderStatus.DELIVERED));

        vm.stopPrank();

        // Update to COMPLETED as buyer
        vm.startPrank(buyer);

        vm.expectEmit(true, false, false, false);
        emit OrderStatusUpdated(1, FarmEscrow.OrderStatus.COMPLETED);

        vm.expectEmit(true, true, false, false);
        emit EscrowClaimable(1, seller, productTotal - (productTotal / 100));

        vm.expectEmit(true, false, false, false);
        emit DeveloperFeePaid(1, productTotal / 100);

        farmEscrow.updateOrderStatus(1, FarmEscrow.OrderStatus.COMPLETED);

        // Verify status was updated
        (
            , // id
            , // buyer
            , // seller
            , // productIds
            , // quantities
            , // totalPrice
            , // shippingFee
            status,
            , // shippingAddress
                // trackingInfo
        ) = farmEscrow.getOrderDetails(1);

        assertEq(uint256(status), uint256(FarmEscrow.OrderStatus.COMPLETED));

        // Verify escrow is claimable
        (,,, bool isReleased, bool isRefunded, bool isClaimable, bool isClaimed,) = farmEscrow.getEscrowDetails(1);

        assertEq(isReleased, false);
        assertEq(isRefunded, false);
        assertEq(isClaimable, true);
        assertEq(isClaimed, false);

        vm.stopPrank();
    }

    function testUpdateOrderStatusInvalidTransition() public {
        // First create an order
        vm.startPrank(seller);

        string[] memory testImageUrls = new string[](1);
        testImageUrls[0] = "https://example.com/image.jpg";

        farmEscrow.addProduct(
            "Organic Apples",
            "Fruits",
            PRODUCT_PRICE,
            PRODUCT_QUANTITY,
            "kg",
            "Fresh organic apples",
            testImageUrls,
            true
        );

        vm.stopPrank();

        vm.startPrank(buyer);

        farmEscrow.addToCart(1, 2);

        uint256 productTotal = 2 * PRODUCT_PRICE;
        uint256 totalWithShipping = productTotal + STANDARD_SHIPPING_FEE;

        farmEscrow.createOrderFromCart{value: totalWithShipping}("123 Buyer Street, City");

        // Try to mark as COMPLETED directly
        vm.expectRevert("Order must be delivered first");

        farmEscrow.updateOrderStatus(1, FarmEscrow.OrderStatus.COMPLETED);

        vm.stopPrank();
    }

    // ==================== Escrow Management Tests ====================

    function testClaimEscrow() public {
        // First create an order and complete it
        vm.startPrank(seller);

        string[] memory testImageUrls = new string[](1);
        testImageUrls[0] = "https://example.com/image.jpg";

        farmEscrow.addProduct(
            "Organic Apples",
            "Fruits",
            PRODUCT_PRICE,
            PRODUCT_QUANTITY,
            "kg",
            "Fresh organic apples",
            testImageUrls,
            true
        );

        vm.stopPrank();

        vm.startPrank(buyer);

        farmEscrow.addToCart(1, 2);

        uint256 productTotal = 2 * PRODUCT_PRICE;
        uint256 totalWithShipping = productTotal + STANDARD_SHIPPING_FEE;

        farmEscrow.createOrderFromCart{value: totalWithShipping}("123 Buyer Street, City");

        vm.stopPrank();

        // Update order status to DELIVERED
        vm.startPrank(seller);
        farmEscrow.addShippingInfo(1, "Tracking123");
        farmEscrow.updateOrderStatus(1, FarmEscrow.OrderStatus.IN_DELIVERY);
        farmEscrow.updateOrderStatus(1, FarmEscrow.OrderStatus.DELIVERED);
        vm.stopPrank();

        // Mark as COMPLETED as buyer
        vm.startPrank(buyer);
        farmEscrow.updateOrderStatus(1, FarmEscrow.OrderStatus.COMPLETED);
        vm.stopPrank();

        // Get seller balance before claim
        uint256 sellerBalanceBefore = address(seller).balance;

        // Claim escrow as seller
        vm.startPrank(seller);

        uint256 sellerAmount = productTotal - (productTotal / 100);

        vm.expectEmit(true, true, false, false);
        emit EscrowClaimed(1, seller, sellerAmount);

        farmEscrow.claimEscrow(1);

        // Verify escrow was claimed
        (,,, bool isReleased, bool isRefunded, bool isClaimable, bool isClaimed, uint256 releasedAt) =
            farmEscrow.getEscrowDetails(1);

        assertEq(isReleased, true);
        assertEq(isRefunded, false);
        assertEq(isClaimable, true);
        assertEq(isClaimed, true);
        assertGt(releasedAt, 0);

        // Verify seller received payment
        uint256 sellerBalanceAfter = address(seller).balance;
        assertEq(sellerBalanceAfter, sellerBalanceBefore + sellerAmount);

        vm.stopPrank();
    }

    function testClaimEscrowNotClaimable() public {
        // First create an order
        vm.startPrank(seller);

        string[] memory testImageUrls = new string[](1);
        testImageUrls[0] = "https://example.com/image.jpg";

        farmEscrow.addProduct(
            "Organic Apples",
            "Fruits",
            PRODUCT_PRICE,
            PRODUCT_QUANTITY,
            "kg",
            "Fresh organic apples",
            testImageUrls,
            true
        );

        vm.stopPrank();

        vm.startPrank(buyer);

        farmEscrow.addToCart(1, 2);

        uint256 productTotal = 2 * PRODUCT_PRICE;
        uint256 totalWithShipping = productTotal + STANDARD_SHIPPING_FEE;

        farmEscrow.createOrderFromCart{value: totalWithShipping}("123 Buyer Street, City");

        vm.stopPrank();

        // Try to claim escrow before it's claimable
        vm.startPrank(seller);

        vm.expectRevert("Escrow not claimable or already claimed");

        farmEscrow.claimEscrow(1);

        vm.stopPrank();
    }

    function testClaimEscrowNonSeller() public {
        // First create an order and complete it
        vm.startPrank(seller);

        string[] memory testImageUrls = new string[](1);
        testImageUrls[0] = "https://example.com/image.jpg";

        farmEscrow.addProduct(
            "Organic Apples",
            "Fruits",
            PRODUCT_PRICE,
            PRODUCT_QUANTITY,
            "kg",
            "Fresh organic apples",
            testImageUrls,
            true
        );

        vm.stopPrank();

        vm.startPrank(buyer);

        farmEscrow.addToCart(1, 2);

        uint256 productTotal = 2 * PRODUCT_PRICE;
        uint256 totalWithShipping = productTotal + STANDARD_SHIPPING_FEE;

        farmEscrow.createOrderFromCart{value: totalWithShipping}("123 Buyer Street, City");

        vm.stopPrank();

        // Update order status to DELIVERED
        vm.startPrank(seller);
        farmEscrow.addShippingInfo(1, "Tracking123");
        farmEscrow.updateOrderStatus(1, FarmEscrow.OrderStatus.IN_DELIVERY);
        farmEscrow.updateOrderStatus(1, FarmEscrow.OrderStatus.DELIVERED);
        vm.stopPrank();

        // Mark as COMPLETED as buyer
        vm.startPrank(buyer);
        farmEscrow.updateOrderStatus(1, FarmEscrow.OrderStatus.COMPLETED);

        // Try to claim escrow as buyer
        vm.expectRevert("Only seller can claim escrow");

        farmEscrow.claimEscrow(1);

        vm.stopPrank();
    }

    function testRefundEscrow() public {
        // First create an order
        vm.startPrank(seller);

        string[] memory testImageUrls = new string[](1);
        testImageUrls[0] = "https://example.com/image.jpg";

        farmEscrow.addProduct(
            "Organic Apples",
            "Fruits",
            PRODUCT_PRICE,
            PRODUCT_QUANTITY,
            "kg",
            "Fresh organic apples",
            testImageUrls,
            true
        );

        vm.stopPrank();

        vm.startPrank(buyer);

        farmEscrow.addToCart(1, 2);

        uint256 productTotal = 2 * PRODUCT_PRICE;
        uint256 totalWithShipping = productTotal + STANDARD_SHIPPING_FEE;

        farmEscrow.createOrderFromCart{value: totalWithShipping}("123 Buyer Street, City");

        vm.stopPrank();

        // Get buyer balance before refund
        uint256 buyerBalanceBefore = address(buyer).balance;

        // Refund escrow as admin
        vm.startPrank(owner);

        vm.expectEmit(true, true, false, false);
        emit EscrowRefunded(1, buyer, totalWithShipping);

        farmEscrow.refundEscrow(1);

        // Verify escrow was refunded
        (,,, bool isReleased, bool isRefunded, bool isClaimable, bool isClaimed, uint256 releasedAt) =
            farmEscrow.getEscrowDetails(1);

        assertEq(isReleased, false);
        assertEq(isRefunded, true);
        assertEq(isClaimable, false);
        assertEq(isClaimed, false);
        assertGt(releasedAt, 0);

        // Verify buyer received refund
        uint256 buyerBalanceAfter = address(buyer).balance;
        assertEq(buyerBalanceAfter, buyerBalanceBefore + totalWithShipping);

        // Verify product stock was restored
        FarmEscrow.Product memory product = getProductDetails(1);

        assertEq(product.stockQuantity, PRODUCT_QUANTITY);
        assertEq(product.soldCount, 0);

        vm.stopPrank();
    }

    function testRefundEscrowNonAdmin() public {
        // First create an order
        vm.startPrank(seller);

        string[] memory testImageUrls = new string[](1);
        testImageUrls[0] = "https://example.com/image.jpg";

        farmEscrow.addProduct(
            "Organic Apples",
            "Fruits",
            PRODUCT_PRICE,
            PRODUCT_QUANTITY,
            "kg",
            "Fresh organic apples",
            testImageUrls,
            true
        );

        vm.stopPrank();

        vm.startPrank(buyer);

        farmEscrow.addToCart(1, 2);

        uint256 productTotal = 2 * PRODUCT_PRICE;
        uint256 totalWithShipping = productTotal + STANDARD_SHIPPING_FEE;

        farmEscrow.createOrderFromCart{value: totalWithShipping}("123 Buyer Street, City");

        // Try to refund escrow as buyer
        vm.expectRevert("Only admin can perform this action");

        farmEscrow.refundEscrow(1);

        vm.stopPrank();
    }

    function testAutoNotifyEscrowClaimable() public {
        // First create an order
        vm.startPrank(seller);

        string[] memory testImageUrls = new string[](1);
        testImageUrls[0] = "https://example.com/image.jpg";

        farmEscrow.addProduct(
            "Organic Apples",
            "Fruits",
            PRODUCT_PRICE,
            PRODUCT_QUANTITY,
            "kg",
            "Fresh organic apples",
            testImageUrls,
            true
        );

        vm.stopPrank();

        vm.startPrank(buyer);

        farmEscrow.addToCart(1, 2);

        uint256 productTotal = 2 * PRODUCT_PRICE;
        uint256 totalWithShipping = productTotal + STANDARD_SHIPPING_FEE;

        farmEscrow.createOrderFromCart{value: totalWithShipping}("123 Buyer Street, City");

        vm.stopPrank();

        // Update order status to DELIVERED
        vm.startPrank(seller);
        farmEscrow.addShippingInfo(1, "Tracking123");
        farmEscrow.updateOrderStatus(1, FarmEscrow.OrderStatus.IN_DELIVERY);
        farmEscrow.updateOrderStatus(1, FarmEscrow.OrderStatus.DELIVERED);
        vm.stopPrank();

        // Fast forward 14 days
        vm.warp(block.timestamp + 14 days + 1);

        // Auto notify escrow claimable
        vm.startPrank(buyer);

        vm.expectEmit(true, true, false, false);
        emit EscrowClaimable(1, seller, productTotal - (productTotal / 100));

        vm.expectEmit(true, false, false, false);
        emit DeveloperFeePaid(1, productTotal / 100);

        vm.expectEmit(true, false, false, false);
        emit OrderStatusUpdated(1, FarmEscrow.OrderStatus.COMPLETED);

        farmEscrow.autoNotifyEscrowClaimable(1);

        // Verify escrow is claimable
        (,,, bool isReleased, bool isRefunded, bool isClaimable, bool isClaimed,) = farmEscrow.getEscrowDetails(1);

        assertEq(isReleased, false);
        assertEq(isRefunded, false);
        assertEq(isClaimable, true);
        assertEq(isClaimed, false);

        // Verify order status is COMPLETED
        (,,,,,,, FarmEscrow.OrderStatus status,,) = farmEscrow.getOrderDetails(1);

        assertEq(uint256(status), uint256(FarmEscrow.OrderStatus.COMPLETED));

        vm.stopPrank();
    }

    function testAutoNotifyEscrowClaimableTooEarly() public {
        // First create an order
        vm.startPrank(seller);

        string[] memory testImageUrls = new string[](1);
        testImageUrls[0] = "https://example.com/image.jpg";

        farmEscrow.addProduct(
            "Organic Apples",
            "Fruits",
            PRODUCT_PRICE,
            PRODUCT_QUANTITY,
            "kg",
            "Fresh organic apples",
            testImageUrls,
            true
        );

        vm.stopPrank();

        vm.startPrank(buyer);

        farmEscrow.addToCart(1, 2);

        uint256 productTotal = 2 * PRODUCT_PRICE;
        uint256 totalWithShipping = productTotal + STANDARD_SHIPPING_FEE;

        farmEscrow.createOrderFromCart{value: totalWithShipping}("123 Buyer Street, City");

        vm.stopPrank();

        // Update order status to DELIVERED
        vm.startPrank(seller);
        farmEscrow.addShippingInfo(1, "Tracking123");
        farmEscrow.updateOrderStatus(1, FarmEscrow.OrderStatus.IN_DELIVERY);
        farmEscrow.updateOrderStatus(1, FarmEscrow.OrderStatus.DELIVERED);
        vm.stopPrank();

        // Fast forward only 7 days (not enough time)
        vm.warp(block.timestamp + 7 days);

        // Try to auto notify escrow claimable
        vm.startPrank(buyer);

        vm.expectRevert("Auto-notification time not reached");

        farmEscrow.autoNotifyEscrowClaimable(1);

        vm.stopPrank();
    }

    // ==================== Platform Stats Tests ====================

    function testGetPlatformStats() public {
        // First create an order
        vm.startPrank(seller);

        string[] memory testImageUrls = new string[](1);
        testImageUrls[0] = "https://example.com/image.jpg";

        farmEscrow.addProduct(
            "Organic Apples",
            "Fruits",
            PRODUCT_PRICE,
            PRODUCT_QUANTITY,
            "kg",
            "Fresh organic apples",
            testImageUrls,
            true
        );

        vm.stopPrank();

        vm.startPrank(buyer);

        farmEscrow.addToCart(1, 2);

        uint256 productTotal = 2 * PRODUCT_PRICE;
        uint256 totalWithShipping = productTotal + STANDARD_SHIPPING_FEE;

        farmEscrow.createOrderFromCart{value: totalWithShipping}("123 Buyer Street, City");

        vm.stopPrank();

        // Get platform stats
        (uint256 totalVolume, uint256 totalOrders, uint256 developerFees, uint256 activeProducts, uint256 activeUsers) =
            farmEscrow.getPlatformStats();

        assertEq(totalVolume, productTotal);
        assertEq(totalOrders, 1);
        assertEq(developerFees, 0); // Developer fees are only collected when escrow is claimed
        assertEq(activeProducts, 1);
        // activeUsers is a simplified placeholder in the contract
    }

    // ==================== Emergency Functions Tests ====================

    function testEmergencyWithdraw() public {
        // First create an order to have funds in the contract
        vm.startPrank(seller);

        string[] memory testImageUrls = new string[](1);
        testImageUrls[0] = "https://example.com/image.jpg";

        farmEscrow.addProduct(
            "Organic Apples",
            "Fruits",
            PRODUCT_PRICE,
            PRODUCT_QUANTITY,
            "kg",
            "Fresh organic apples",
            testImageUrls,
            true
        );

        vm.stopPrank();

        vm.startPrank(buyer);

        farmEscrow.addToCart(1, 2);

        uint256 productTotal = 2 * PRODUCT_PRICE;
        uint256 totalWithShipping = productTotal + STANDARD_SHIPPING_FEE;

        farmEscrow.createOrderFromCart{value: totalWithShipping}("123 Buyer Street, City");

        vm.stopPrank();

        // Get owner balance before withdraw
        uint256 ownerBalanceBefore = address(owner).balance;

        // Emergency withdraw as owner
        vm.startPrank(owner);

        farmEscrow.emergencyWithdraw();

        // Verify owner received funds
        uint256 ownerBalanceAfter = address(owner).balance;
        assertEq(ownerBalanceAfter, ownerBalanceBefore + totalWithShipping);

        vm.stopPrank();
    }

    function testEmergencyWithdrawNonAdmin() public {
        vm.startPrank(buyer);

        vm.expectRevert("Only admin can perform this action");

        farmEscrow.emergencyWithdraw();

        vm.stopPrank();
    }

    // Helper function to get product details
    function getProductDetails(uint256 productId) internal view returns (FarmEscrow.Product memory) {
        FarmEscrow.Product memory product;
        // (
        //     uint256 id,
        //     address productSeller,
        //     string memory name,
        //     string memory category,
        //     uint256 price,
        //     uint256 stockQuantity,
        //     string memory unit,
        //     string memory description,
        //     string[] memory imageUrls,
        //     bool isAvailable,
        //     bool isOrganic,
        //     uint256 soldCount
        // ) = farmEscrow.products(productId);

        // FarmEscrow.Product memory product;
        // product.id = id;
        // product.seller = productSeller;
        // product.name = name;
        // product.category = category;
        // product.price = price;
        // product.stockQuantity = stockQuantity;
        // product.unit = unit;
        // product.description = description;
        // product.imageUrls = imageUrls;
        // product.isAvailable = isAvailable;
        // product.isOrganic = isOrganic;
        // product.soldCount = soldCount;

        // return product;
        return farmEscrow.getProduct(productId);
    }
}
