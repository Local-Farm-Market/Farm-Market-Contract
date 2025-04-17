 // SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract FarmEscrow is Ownable, ReentrancyGuard {
    // Structs
    struct UserProfile {
        string name;
        string contactInfo;
        string location;
        string bio;
        bool isVerified;
        uint256 rating;
        uint256 reviewCount;
        bool isSeller;
        string farmName;
        string farmDescription;
    }

    struct Product {
        uint256 id;
        address seller;
        string name;
        string category;
        uint256 price;
        uint256 stockQuantity;
        string unit;
        string description;
        string[] imageUrls;
        bool isAvailable;
        bool isOrganic;
        uint256 soldCount;
    }

    struct Order {
        uint256 id;
        address buyer;
        address seller;
        uint256[] productIds; // Changed to array to handle cart functionalities.
        uint256[] quantities; // Changed to array to handle cart functionalities.
        uint256 totalPrice;
        uint256 shippingFee;
        OrderStatus status;
        string shippingAddress;
        string trackingInfo;
        uint256 updatedAt; // ✅ Add this line
    }

    // Cart item structure
    struct CartItem {
        uint256 productId;
        uint256 quantity;
    }

    // Escrow structure to track funds
    struct Escrow {
        uint256 orderId;
        uint256 amount;
        uint256 developerFee;
        uint256 sellerAmount;
        uint256 createdAt;
        uint256 releasedAt;
        bool isReleased;
        bool isRefunded;
        bool isClaimable;         // Added for the new escrow claim functionality (wether the funds is claimable)
        bool isClaimed;           // Added to track if seller has claimed funds
    }

    //Enums
    enum OrderStatus {
        NEW,
        PAID,
        PROCESSING,
        SHIPPED,
        IN_DELIVERY,              // Added new status to keep track if the status is in delivery
        DELIVERED,
        COMPLETED
    }

    // Events
    event UserProfileCreated(address indexed user, string name, bool isSeller, string farmName);
    event UserProfileUpdated(address indexed user);
    event ProductAdded(uint256 indexed productId, address indexed seller, string name);
    event ProductUpdated(uint256 indexed productId);
    event ProductDeleted(uint256 indexed productId);
    event OrderCreated(uint256 indexed orderId, address indexed buyer, address indexed seller);
    event OrderStatusUpdated(uint256 indexed orderId, OrderStatus status);
    event PaymentReleased(uint256 indexed orderId, uint256 amount);
    event WithdrawalMade(address indexed seller, uint256 amount);
    event FundsDeposited(address indexed user, uint256 amount);
    event EscrowCreated(uint256 indexed orderId, uint256 amount, uint256 developerFee);
    event EscrowReleased(uint256 indexed orderId, address indexed seller, uint256 amount);
    event EscrowRefunded(uint256 indexed orderId, address indexed buyer, uint256 amount);
    event DeveloperFeePaid(uint256 indexed orderId, uint256 amount);
    event EscrowClaimable(uint256 indexed orderId, address indexed seller, uint256 amount); // Newly added events
    event EscrowClaimed(uint256 indexed orderId, address indexed seller, uint256 amount); // Newly added events
    event CartItemAdded(address indexed user, uint256 productId, uint256 quantity); // Newly added events
    event CartItemRemoved(address indexed user, uint256 productId); // Newly added events
    event CartItemQuantityUpdated(address indexed user, uint256 productId, uint256 quantity); // Newly added events
    event CartCleared(address indexed user); // Newly added events

    // State Variables
    mapping(address => UserProfile) public userProfiles;
    mapping(uint256 => Product) public products;
    mapping(uint256 => Order) public orders;
    mapping(address => uint256[]) public sellerProducts;
    mapping(address => uint256[]) public buyerOrders;
    mapping(address => uint256[]) public sellerOrders;
    mapping(address => uint256) public sellerBalances;
    mapping(address => uint256) public userBalances;
    mapping(address => uint256) public pendingWithdrawals;
    mapping(uint256 => Escrow) public escrows; // Map orderId to escrow
    mapping(string => uint256[]) public productsByCategory;
    mapping(address => mapping(uint256 => bool)) public favoriteProducts;
    mapping(address => uint256[]) public userFavorites;
    mapping(address => CartItem[]) public userCarts; // Added to track user carts 

    // Replace Counters with native uint256 tracking
    uint256 private _productIds;
    uint256 private _orderIds;
    uint256 private constant DEVELOPER_FEE_PERCENT = 1;
    uint256 private constant STANDARD_SHIPPING_FEE = 5 ether; // 5 USD in wei
    address private _developerWallet;
    uint256 private _platformTotalVolume;
    uint256 private _platformTotalOrders;
    uint256 private _developerTotalFees;

    // Constructor
    constructor(address developerWallet) Ownable(msg.sender) {
        _developerWallet = developerWallet;
    }

    // Modifiers
    modifier onlySeller() {
        require(userProfiles[msg.sender].isSeller, "Only sellers can perform this action");
        _;
    }

    modifier onlyBuyer() {
        require(!userProfiles[msg.sender].isSeller, "Only buyers can perform this action");
        _;
    }

    modifier productExists(uint256 productId) {
        require(products[productId].id == productId, "Product does not exist");
        _;
    }

    modifier orderExists(uint256 orderId) {
        require(orders[orderId].id == orderId, "Order does not exist");
        _;
    }

    modifier onlyOrderParticipant(uint256 orderId) {
        require(
            msg.sender == orders[orderId].buyer || msg.sender == orders[orderId].seller,
            "Only order participants can perform this action"
        );
        _;
    }

    modifier onlyAdmin() {
        require(msg.sender == owner() || msg.sender == _developerWallet, "Only admin can perform this action");
        _;
    }

    // Increment function for product IDs
    function _incrementProductId() private returns (uint256) {
        _productIds++;
        return _productIds;
    }

    // Increment function for order IDs
    function _incrementOrderId() private returns (uint256) {
        _orderIds++;
        return _orderIds;
    }

    // User Profile Functions
    function createUserProfile(
        string memory name,
        string memory contactInfo,
        string memory location,
        string memory bio,
        bool isSeller,
        string memory farmName,
        string memory farmDescription
    ) external {
        require(bytes(name).length > 0, "Name cannot be empty");

        UserProfile storage profile = userProfiles[msg.sender];
        profile.name = name;
        profile.contactInfo = contactInfo;
        profile.location = location;
        profile.bio = bio;
        profile.isVerified = false;
        profile.rating = 5; // Default rating
        profile.reviewCount = 0;
        profile.isSeller = isSeller;
        profile.farmName = farmName;
        profile.farmDescription = farmDescription;

        emit UserProfileCreated(msg.sender, name, isSeller, farmName);
    }
    
    // Function to update user profile
    function updateUserProfile(
        string memory name,
        string memory contactInfo,
        string memory location,
        string memory bio,
        string memory farmName,
        string memory farmDescription
    ) external {
        require(bytes(userProfiles[msg.sender].name).length > 0, "Profile does not exist");

        UserProfile storage profile = userProfiles[msg.sender];
        profile.name = name;
        profile.contactInfo = contactInfo;
        profile.location = location;
        profile.bio = bio;
        profile.farmName = farmName;
        profile.farmDescription = farmDescription;

        emit UserProfileUpdated(msg.sender);
    }

    // Product Management Functions
    function addProduct(
        string memory name,
        string memory category,
        uint256 price,
        uint256 stockQuantity,
        string memory unit,
        string memory description,
        string[] memory imageUrls,
        bool isOrganic
    ) external onlySeller {
        require(bytes(name).length > 0, "Name cannot be empty");
        require(price > 0, "Price must be greater than zero");
        require(stockQuantity > 0, "Stock quantity must be greater than zero");

        uint256 newProductId = _incrementProductId();

        products[newProductId] = Product({
            id: newProductId,
            seller: msg.sender,
            name: name,
            category: category,
            price: price,
            stockQuantity: stockQuantity,
            unit: unit,
            description: description,
            imageUrls: imageUrls,
            isAvailable: true,
            isOrganic: isOrganic,
            soldCount: 0
        });

        sellerProducts[msg.sender].push(newProductId);
        productsByCategory[category].push(newProductId);

        emit ProductAdded(newProductId, msg.sender, name);
    }

    // Function to update product
    function updateProduct(
        uint256 productId,
        string memory name,
        string memory category,
        uint256 price,
        uint256 stockQuantity,
        string memory unit,
        string memory description,
        string[] memory imageUrls,
        bool isAvailable,
        bool isOrganic
    ) external onlySeller productExists(productId) {
        require(products[productId].seller == msg.sender, "Only seller can update");

        Product storage product = products[productId];

        // If category changed, update the category mapping
        if (keccak256(bytes(product.category)) != keccak256(bytes(category))) {

            // Remove from old category
            uint256[] storage oldCategoryProducts = productsByCategory[product.category];

            for (uint256 i = 0; i < oldCategoryProducts.length; i++) {
                if (oldCategoryProducts[i] == productId) {
                    oldCategoryProducts[i] = oldCategoryProducts[oldCategoryProducts.length - 1];
                    oldCategoryProducts.pop();
                    break;
                }
            }

            // Add to new category
            productsByCategory[category].push(productId);
        }

        product.name = name;
        product.category = category;
        product.price = price;
        product.stockQuantity = stockQuantity;
        product.unit = unit;
        product.description = description;
        product.imageUrls = imageUrls;
        product.isAvailable = isAvailable;
        product.isOrganic = isOrganic;

        emit ProductUpdated(productId);
    }

    //************* */ Cart Management Functions ********************//

    //Function to add a product to a cart
    function addToCart(uint256 productId, uint256 quantity) external {
        require(products[productId].id == productId, "Product does not exist");
        require(products[productId].isAvailable, "Product not available");
        require(products[productId].stockQuantity >= quantity, "Insufficient stock");
        require(quantity > 0, "Quantity must be greater than zero");

        CartItem[] storage cart = userCarts[msg.sender];
        bool found = false;

        // Check if product already in cart
        for (uint256 i = 0; i < cart.length; i++) {
            if (cart[i].productId == productId) {
                cart[i].quantity += quantity;
                found = true;
                emit CartItemQuantityUpdated(msg.sender, productId, cart[i].quantity);
                break;
            }
        }

        // If not found, add new item
        if (!found) {
            cart.push(CartItem({
                productId: productId,
                quantity: quantity
            }));
            emit CartItemAdded(msg.sender, productId, quantity);
        }
    }

    //Function to update cart item quantity
    function updateCartItemQuantity(uint256 productId, uint256 newQuantity) external {
        require(products[productId].id == productId, "Product does not exist");
        require(products[productId].isAvailable, "Product not available");
        require(products[productId].stockQuantity >= newQuantity, "Insufficient stock");
        require(newQuantity > 0, "Quantity must be greater than zero");

        CartItem[] storage cart = userCarts[msg.sender];
        bool found = false;

        for (uint256 i = 0; i < cart.length; i++) {
            if (cart[i].productId == productId) {
                cart[i].quantity = newQuantity;
                found = true;
                emit CartItemQuantityUpdated(msg.sender, productId, newQuantity);
                break;
            }
        }

        require(found, "Product not in cart");
    }

    //Function to remove a product from cart
    function removeFromCart(uint256 productId) external {
        CartItem[] storage cart = userCarts[msg.sender];
        bool found = false;
        uint256 indexToRemove;

        for (uint256 i = 0; i < cart.length; i++) {
            if (cart[i].productId == productId) {
                indexToRemove = i;
                found = true;
                break;
            }
        }

        require(found, "Product not in cart");

        // Remove item by replacing with last item and popping
        if (indexToRemove < cart.length - 1) {
            cart[indexToRemove] = cart[cart.length - 1];
        }
        cart.pop();

        emit CartItemRemoved(msg.sender, productId);
    }

    // Function to clear the cart
    function clearCart() external {
        delete userCarts[msg.sender];
        emit CartCleared(msg.sender);
    }


    //******************* Cart getter functions  ****************/

    //Function to get all cart items 
    function getCartItems() external view returns (CartItem[] memory) {
        return userCarts[msg.sender];
    }

    //Function to get the card total
    function getCartTotal() external view returns (uint256 total) {
        CartItem[] storage cart = userCarts[msg.sender];
        
        for (uint256 i = 0; i < cart.length; i++) {
            uint256 productId = cart[i].productId;
            uint256 quantity = cart[i].quantity;
            
            if (products[productId].id == productId && products[productId].isAvailable) {
                total += products[productId].price * quantity;
            }
        }
        
        return total;
    }

    // Order Management Functions with Escrow (create a new order from an existing cart, validate and check if the products in the cart are still available.)
    function createOrderFromCart(string memory shippingAddress) external payable {
        CartItem[] storage cart = userCarts[msg.sender];
        require(cart.length > 0, "Cart is empty");
        
        uint256 totalAmount = 0;
        uint256[] memory productIds = new uint256[](cart.length);
        uint256[] memory quantities = new uint256[](cart.length);
        address seller;
        
        // Validate all products and calculate total
        for (uint256 i = 0; i < cart.length; i++) {
            uint256 productId = cart[i].productId;
            uint256 quantity = cart[i].quantity;
            
            require(products[productId].id == productId, "Product does not exist");
            require(products[productId].isAvailable, "Product not available");
            require(products[productId].stockQuantity >= quantity, "Insufficient stock");
            
            // For simplicity, we're assuming all products are from the same seller
            if (i == 0) {
                seller = products[productId].seller;
            } else {
                require(seller == products[productId].seller, "All products must be from the same seller");
            }
            
            totalAmount += products[productId].price * quantity;
            productIds[i] = productId;
            quantities[i] = quantity;
        }
        
        require(msg.value == totalAmount + STANDARD_SHIPPING_FEE, "Incorrect payment");
        
        uint256 newOrderId = _incrementOrderId();
        
        // Calculate fees
        uint256 developerFee = (totalAmount * DEVELOPER_FEE_PERCENT) / 100;
        uint256 sellerAmount = totalAmount - developerFee;
        
        // Create order
        orders[newOrderId] = Order({
            id: newOrderId,
            buyer: msg.sender,
            seller: seller,
            productIds: productIds,
            quantities: quantities,
            totalPrice: totalAmount,
            shippingFee: STANDARD_SHIPPING_FEE,
            status: OrderStatus.PAID,
            shippingAddress: shippingAddress,
            trackingInfo: "",
            updatedAt: block.timestamp
        });
        
        // Create escrow to hold funds
        escrows[newOrderId] = Escrow({
            orderId: newOrderId,
            amount: totalAmount,
            developerFee: developerFee,
            sellerAmount: sellerAmount,
            createdAt: block.timestamp, // ✅ Include this
            releasedAt: 0,
            isReleased: false,
            isRefunded: false,
            isClaimable: false,
            isClaimed: false
        });
        
        // Update product stock
        for (uint256 i = 0; i < productIds.length; i++) {
            Product storage product = products[productIds[i]];
            product.stockQuantity -= quantities[i];
            product.soldCount += quantities[i];
        }
        
        // Track orders for buyer and seller
        buyerOrders[msg.sender].push(newOrderId);
        sellerOrders[seller].push(newOrderId);
        
        // Update platform stats
        _platformTotalVolume += totalAmount;
        _platformTotalOrders++;
        
        // Clear the cart
        delete userCarts[msg.sender];
        
        emit OrderCreated(newOrderId, msg.sender, seller);
        emit EscrowCreated(newOrderId, totalAmount, developerFee);
        emit CartCleared(msg.sender);
    }


    // Function to update order shipping info (by seller)
    function addShippingInfo(uint256 orderId, string memory trackingInfo) external orderExists(orderId) {
        Order storage order = orders[orderId];
        require(msg.sender == order.seller, "Only seller can update shipping info");
        require(order.status == OrderStatus.PAID || order.status == OrderStatus.PROCESSING, "Order not in correct state");

        order.trackingInfo = trackingInfo;
        order.status = OrderStatus.SHIPPED;
        order.updatedAt = block.timestamp;

        emit OrderStatusUpdated(orderId, OrderStatus.SHIPPED);
    }

    // Update order status function
    function updateOrderStatus(uint256 orderId, OrderStatus newStatus) external onlyOrderParticipant(orderId) orderExists(orderId) {
        Order storage order = orders[orderId];
        
        // Specific validation for order status transitions
        if (newStatus == OrderStatus.COMPLETED) {
            require(msg.sender == order.buyer, "Only buyer can mark as completed");
            require(order.status == OrderStatus.DELIVERED, "Order must be delivered first");
            
            // Make escrow claimable when order is completed
            makeEscrowClaimable(orderId);
        } else if (newStatus == OrderStatus.DELIVERED) {
            require(msg.sender == order.seller, "Only seller can mark as delivered");
            require(order.status == OrderStatus.IN_DELIVERY, "Order must be in delivery first");
        } else if (newStatus == OrderStatus.IN_DELIVERY) {
            require(msg.sender == order.seller, "Only seller can mark as in delivery");
            require(order.status == OrderStatus.SHIPPED, "Order must be shipped first");
        }

        order.status = newStatus;
        order.updatedAt = block.timestamp;

        emit OrderStatusUpdated(orderId, newStatus);
    }

    //**************** Escrow Management Functions ***********************/ 

    // Function to make escrow claimable and immediately send the developer fee
    function makeEscrowClaimable(uint256 orderId) internal orderExists(orderId) {
        Order storage order = orders[orderId];
        Escrow storage escrow = escrows[orderId];
        
        // Check escrow can be made claimable
        require(!escrow.isReleased && !escrow.isRefunded && !escrow.isClaimable, "Escrow already processed");
        
        escrow.isClaimable = true;
        
        // Pay developer fee immediately
        (bool devSuccess,) = payable(_developerWallet).call{value: escrow.developerFee}("");
        require(devSuccess, "Developer fee payment failed");
        
        _developerTotalFees += escrow.developerFee;
        
        emit EscrowClaimable(orderId, order.seller, escrow.sellerAmount);
        emit DeveloperFeePaid(orderId, escrow.developerFee);
    }

    // Function to allow sellers claim their funds from the escrow 
    function claimEscrow(uint256 orderId) external nonReentrant orderExists(orderId) {
        Order storage order = orders[orderId];
        Escrow storage escrow = escrows[orderId];
        
        require(msg.sender == order.seller, "Only seller can claim escrow");
        require(escrow.isClaimable && !escrow.isClaimed, "Escrow not claimable or already claimed");
        
        escrow.isClaimed = true;
        escrow.isReleased = true;
        escrow.releasedAt = block.timestamp;
        
        // Pay seller
        (bool sellerSuccess,) = payable(order.seller).call{value: escrow.sellerAmount}("");
        require(sellerSuccess, "Seller payment failed");
        
        emit EscrowClaimed(orderId, order.seller, escrow.sellerAmount);
    }

    //Function to release escrow
    // function releaseEscrow(uint256 orderId) public nonReentrant orderExists(orderId) {
    //     Order storage order = orders[orderId];
    //     Escrow storage escrow = escrows[orderId];
        
    //     // Check escrow can be released
    //     require(!escrow.isReleased && !escrow.isRefunded, "Escrow already processed");
    //     require(
    //         msg.sender == order.buyer || 
    //         msg.sender == owner() || 
    //         (order.status == OrderStatus.COMPLETED && msg.sender == order.seller),
    //         "Unauthorized to release escrow"
    //     );

    //     escrow.isReleased = true;
    //     escrow.releasedAt = block.timestamp;

    //     // Pay seller
    //     (bool sellerSuccess,) = payable(order.seller).call{value: escrow.sellerAmount}("");
    //     require(sellerSuccess, "Seller payment failed");

    //     // Pay developer fee
    //     (bool devSuccess,) = payable(_developerWallet).call{value: escrow.developerFee}("");
    //     require(devSuccess, "Developer fee payment failed");

    //     _developerTotalFees += escrow.developerFee;

    //     // Update status if needed
    //     if (order.status != OrderStatus.COMPLETED) {
    //         order.status = OrderStatus.COMPLETED;
    //         order.updatedAt = block.timestamp;
    //         emit OrderStatusUpdated(orderId, OrderStatus.COMPLETED);
    //     }

    //     emit EscrowReleased(orderId, order.seller, escrow.sellerAmount);
    //     emit DeveloperFeePaid(orderId, escrow.developerFee);
    // }

    // Function to refund buyer (cancel order)
    function refundEscrow(uint256 orderId) public nonReentrant orderExists(orderId) onlyAdmin {
        Order storage order = orders[orderId];
        Escrow storage escrow = escrows[orderId];
        
        // Check escrow can be refunded
        require(!escrow.isReleased && !escrow.isRefunded, "Escrow already processed");
        
        escrow.isRefunded = true;
        escrow.releasedAt = block.timestamp;

        // Refund full amount to buyer including shipping fee
        uint256 refundAmount = escrow.amount + STANDARD_SHIPPING_FEE;
        (bool success,) = payable(order.buyer).call{value: refundAmount}("");
        require(success, "Refund payment failed");

        // Update product stock
        for (uint256 i = 0; i < order.productIds.length; i++) {
            uint256 productId = order.productIds[i];
            uint256 quantity = order.quantities[i];
            
            if (products[productId].id == productId) {
                products[productId].stockQuantity += quantity;
                products[productId].soldCount -= quantity;
            }
        }

        emit EscrowRefunded(orderId, order.buyer, refundAmount);
    }

    // Automatic escrow notification and release funds after time period (can be called by anyone after 14 days of delivery)
    function autoNotifyEscrowClaimable(uint256 orderId) external orderExists(orderId) {
        Order storage order = orders[orderId];
        Escrow storage escrow = escrows[orderId];
        
        require(order.status == OrderStatus.DELIVERED, "Order not delivered");
        require(!escrow.isReleased && !escrow.isRefunded && !escrow.isClaimable, "Escrow already processed");
        require(block.timestamp >= order.updatedAt + 14 days, "Auto-notification time not reached");
        
        // Make escrow claimable
        makeEscrowClaimable(orderId);
        
        // Update order status to completed
        order.status = OrderStatus.COMPLETED;
        order.updatedAt = block.timestamp;
        
        emit OrderStatusUpdated(orderId, OrderStatus.COMPLETED);
    }

    //**************** Additional getter functions for escrow status *******************/ 

    //Function to get all the details of a specific order 
    function getOrderDetails(uint256 orderId) external view returns (
        uint256 id,
        address buyer,
        address seller,
        uint256[] memory productIds,
        uint256[] memory quantities,
        uint256 totalPrice,
        uint256 shippingFee,
        OrderStatus status,
        string memory shippingAddress,
        string memory trackingInfo
    ) {
        Order storage order = orders[orderId];
        return (
            order.id,
            order.buyer,
            order.seller,
            order.productIds,
            order.quantities,
            order.totalPrice,
            order.shippingFee,
            order.status,
            order.shippingAddress,
            order.trackingInfo
        );
    }

    function getEscrowDetails(uint256 orderId) external view returns (
        uint256 amount,
        uint256 developerFee,
        uint256 sellerAmount,
        bool isReleased,
        bool isRefunded,
        bool isClaimable,
        bool isClaimed,
        uint256 releasedAt
    ) {
        Escrow storage escrow = escrows[orderId];
        return (
            escrow.amount,
            escrow.developerFee,
            escrow.sellerAmount,
            escrow.isReleased,
            escrow.isRefunded,
            escrow.isClaimable,
            escrow.isClaimed,
            escrow.releasedAt
        );
    }

    // Function to get user products 
     function getUserProducts(address seller) external view returns (uint256[] memory) {
        return sellerProducts[seller];
    }

    //Function to get user orders
    function getUserOrders(address user) external view returns (uint256[] memory) {
        return buyerOrders[user];
    }

    // Function to get all the orders that have been placed with a particular seller
    function getSellerOrders(address seller) external view returns (uint256[] memory) {
        return sellerOrders[seller];
    }

    // Function to get a list of product that belong to a particular category
    function getProductsByCategory(string memory category) external view returns (uint256[] memory) {
        return productsByCategory[category];
    }

    // Platform statistics
    function getPlatformStats() external view returns (
        uint256 totalVolume,
        uint256 totalOrders,
        uint256 developerFees,
        uint256 activeProducts,
        uint256 activeUsers
    ) {
        uint256 productCount = 0;
        for (uint256 i = 1; i <= _productIds; i++) {
            if (products[i].isAvailable && products[i].stockQuantity > 0) {
                productCount++;
            }
        }
        
        // For active users, we'll count any address with a profile
        // A more sophisticated implementation could track active users within a time period
        uint256 userCount = 0; // This is a simplified placeholder
        
        return (
            _platformTotalVolume,
            _platformTotalOrders,
            _developerTotalFees,
            productCount,
            userCount
        );
    }

    // Emergency functions
    function emergencyWithdraw() external onlyAdmin nonReentrant {
        uint256 balance = address(this).balance;
        (bool success,) = payable(owner()).call{value: balance}("");
        require(success, "Emergency withdraw failed");
    }

    // Fallback function to receive Ether
    receive() external payable {
        emit FundsDeposited(msg.sender, msg.value);
    }
}
