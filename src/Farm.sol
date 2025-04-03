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
        string[] certifications;
        uint256 createdAt;
        bool isSeller;
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
        string harvestDate;
        uint256 createdAt;
        uint256 soldCount;
        NutritionFacts nutritionFacts;
    }

    struct NutritionFacts {
        uint256 calories;
        string protein;
        string carbs;
        string fat;
        string fiber;
    }

    struct Order {
        uint256 id;
        address buyer;
        address seller;
        uint256 productId;
        uint256 quantity;
        uint256 totalPrice;
        uint256 shippingFee;
        OrderStatus status;
        string shippingAddress;
        string trackingInfo;
        uint256 createdAt;
        uint256 updatedAt;
        bool isDisputed;
        string disputeReason;
    }

    struct Review {
        uint256 id;
        address reviewer;
        address reviewee;
        uint256 productId;
        uint256 orderId;
        uint256 rating;
        string comment;
        uint256 timestamp;
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
    }

    //Enums
    enum OrderStatus {
        NEW,
        PAID,
        PROCESSING,
        SHIPPED,
        DELIVERED,
        CANCELLED,
        COMPLETED,
        DISPUTED
    }

    enum DisputeResolution {
        NONE,
        REFUND_BUYER,
        RELEASE_TO_SELLER,
        PARTIAL_REFUND
    }

    // Events
    event UserProfileCreated(address indexed user, string name, bool isSeller);
    event UserProfileUpdated(address indexed user);
    event ProductAdded(uint256 indexed productId, address indexed seller, string name);
    event ProductUpdated(uint256 indexed productId);
    event ProductDeleted(uint256 indexed productId);
    event OrderCreated(uint256 indexed orderId, address indexed buyer, address indexed seller);
    event OrderStatusUpdated(uint256 indexed orderId, OrderStatus status);
    event PaymentReleased(uint256 indexed orderId, uint256 amount);
    event WithdrawalMade(address indexed seller, uint256 amount);
    event ReviewSubmitted(uint256 indexed reviewId, address indexed reviewer, address indexed reviewee);
    event DisputeCreated(uint256 indexed orderId, address indexed initiator);
    event DisputeResolved(uint256 indexed orderId, DisputeResolution resolution);
    event FundsDeposited(address indexed user, uint256 amount);
    event EscrowCreated(uint256 indexed orderId, uint256 amount, uint256 developerFee);
    event EscrowReleased(uint256 indexed orderId, address indexed seller, uint256 amount);
    event EscrowRefunded(uint256 indexed orderId, address indexed buyer, uint256 amount);
    event DeveloperFeePaid(uint256 indexed orderId, uint256 amount);

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
    mapping(uint256 => Review[]) public productReviews;
    mapping(address => Review[]) public userReviews;
    mapping(uint256 => Escrow) public escrows; // Map orderId to escrow

    struct Dispute {
        uint256 id;
        uint256 orderId;
        address initiator;
        string reason;
        DisputeResolution resolution;
        uint256 createdAt;
        uint256 resolvedAt;
    }

    mapping(uint256 => Dispute) public disputes;
    mapping(string => uint256[]) public productsByCategory;
    mapping(address => mapping(uint256 => bool)) public favoriteProducts;
    mapping(address => uint256[]) public userFavorites;

    // Replace Counters with native uint256 tracking
    uint256 private _productIds;
    uint256 private _orderIds;
    uint256 private _reviewIds;
    uint256 private _disputeIds;

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

    //Function to increment review IDs
    function _incrementReviewId() private returns (uint256) {
        _reviewIds++;
        return _reviewIds;
    }

    // Function to increment dispute IDs
    function _incrementDisputeId() private returns (uint256) {
        _disputeIds++;
        return _disputeIds;
    }

    // User Profile Functions
    function createUserProfile(
        string memory name,
        string memory contactInfo,
        string memory location,
        string memory bio,
        bool isSeller,
        string memory certifications
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
        profile.certifications = new string[](1);
        profile.certifications[0] = certifications;
        profile.createdAt = block.timestamp;
        profile.isSeller = isSeller;

        emit UserProfileCreated(msg.sender, name, isSeller);
    }
    
    // Function to update user profile
    function updateUserProfile(
        string memory name,
        string memory contactInfo,
        string memory location,
        string memory bio,
        string[] memory certifications
    ) external {
        require(bytes(userProfiles[msg.sender].name).length > 0, "Profile does not exist");

        UserProfile storage profile = userProfiles[msg.sender];
        profile.name = name;
        profile.contactInfo = contactInfo;
        profile.location = location;
        profile.bio = bio;
        profile.certifications = certifications;

        emit UserProfileUpdated(msg.sender);
    }

    //Function to toggle seller status
    function toggleSellerStatus() external {
        require(bytes(userProfiles[msg.sender].name).length > 0, "Profile does not exist");

        userProfiles[msg.sender].isSeller = !userProfiles[msg.sender].isSeller;

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
        bool isOrganic,
        string memory harvestDate,
        NutritionFacts memory nutritionFacts
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
            harvestDate: harvestDate,
            createdAt: block.timestamp,
            soldCount: 0,
            nutritionFacts: nutritionFacts
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
        bool isOrganic,
        string memory harvestDate,
        NutritionFacts memory nutritionFacts
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
        product.harvestDate = harvestDate;
        product.nutritionFacts = nutritionFacts;

        emit ProductUpdated(productId);
    }

    // Order Management Functions with Escrow
    function createOrder(uint256 productId, uint256 quantity, string memory shippingAddress) external payable {
        Product storage product = products[productId];
        require(product.isAvailable, "Product not available");
        require(product.stockQuantity >= quantity, "Insufficient stock");
        require(msg.value == product.price * quantity + STANDARD_SHIPPING_FEE, "Incorrect payment");

        uint256 newOrderId = _incrementOrderId();
        uint256 productTotal = product.price * quantity;
        
        // Calculate fees
        uint256 developerFee = (productTotal * DEVELOPER_FEE_PERCENT) / 100;
        uint256 sellerAmount = productTotal - developerFee;

        // Create order
        orders[newOrderId] = Order({
            id: newOrderId,
            buyer: msg.sender,
            seller: product.seller,
            productId: productId,
            quantity: quantity,
            totalPrice: productTotal,
            shippingFee: STANDARD_SHIPPING_FEE,
            status: OrderStatus.PAID, // Changed from NEW to PAID since payment is made
            shippingAddress: shippingAddress,
            trackingInfo: "",
            createdAt: block.timestamp,
            updatedAt: block.timestamp,
            isDisputed: false,
            disputeReason: ""
        });

        // Create escrow to hold funds
        escrows[newOrderId] = Escrow({
            orderId: newOrderId,
            amount: productTotal,
            developerFee: developerFee,
            sellerAmount: sellerAmount,
            createdAt: block.timestamp,
            releasedAt: 0,
            isReleased: false,
            isRefunded: false
        });

        // Update product stock
        product.stockQuantity -= quantity;
        product.soldCount += quantity;

        // Track orders for buyer and seller
        buyerOrders[msg.sender].push(newOrderId);
        sellerOrders[product.seller].push(newOrderId);

        // Update platform stats
        _platformTotalVolume += productTotal;
        _platformTotalOrders++;

        emit OrderCreated(newOrderId, msg.sender, product.seller);
        emit EscrowCreated(newOrderId, productTotal, developerFee);
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
            
            // Release escrow to seller when order is completed
            releaseEscrow(orderId);
        } else if (newStatus == OrderStatus.DELIVERED) {
            require(msg.sender == order.seller, "Only seller can mark as delivered");
            require(order.status == OrderStatus.SHIPPED, "Order must be shipped first");
        } else if (newStatus == OrderStatus.CANCELLED) {
            require(
                (msg.sender == order.buyer && order.status == OrderStatus.PAID) || 
                (msg.sender == order.seller && (order.status == OrderStatus.PAID || order.status == OrderStatus.PROCESSING)),
                "Cannot cancel at current state"
            );
            
            if (msg.sender == order.buyer) {
                // Refund escrow to buyer
                refundEscrow(orderId);
            }
        }

        order.status = newStatus;
        order.updatedAt = block.timestamp;

        emit OrderStatusUpdated(orderId, newStatus);
    }

    // Escrow Management Functions
    function releaseEscrow(uint256 orderId) public nonReentrant orderExists(orderId) {
        Order storage order = orders[orderId];
        Escrow storage escrow = escrows[orderId];
        
        // Check escrow can be released
        require(!escrow.isReleased && !escrow.isRefunded, "Escrow already processed");
        require(
            msg.sender == order.buyer || 
            msg.sender == owner() || 
            (order.status == OrderStatus.COMPLETED && msg.sender == order.seller),
            "Unauthorized to release escrow"
        );

        escrow.isReleased = true;
        escrow.releasedAt = block.timestamp;

        // Pay seller
        (bool sellerSuccess,) = payable(order.seller).call{value: escrow.sellerAmount}("");
        require(sellerSuccess, "Seller payment failed");

        // Pay developer fee
        (bool devSuccess,) = payable(_developerWallet).call{value: escrow.developerFee}("");
        require(devSuccess, "Developer fee payment failed");

        _developerTotalFees += escrow.developerFee;

        // Update status if needed
        if (order.status != OrderStatus.COMPLETED) {
            order.status = OrderStatus.COMPLETED;
            order.updatedAt = block.timestamp;
            emit OrderStatusUpdated(orderId, OrderStatus.COMPLETED);
        }

        emit EscrowReleased(orderId, order.seller, escrow.sellerAmount);
        emit DeveloperFeePaid(orderId, escrow.developerFee);
    }

    // Function to refund buyer (cancel order)
    function refundEscrow(uint256 orderId) public nonReentrant orderExists(orderId) {
        Order storage order = orders[orderId];
        Escrow storage escrow = escrows[orderId];
        
        // Check escrow can be refunded
        require(!escrow.isReleased && !escrow.isRefunded, "Escrow already processed");
        require(
            msg.sender == order.seller || 
            msg.sender == owner() || 
            (order.status != OrderStatus.DELIVERED && order.status != OrderStatus.COMPLETED && msg.sender == order.buyer),
            "Unauthorized to refund escrow"
        );

        escrow.isRefunded = true;
        escrow.releasedAt = block.timestamp;

        // Refund full amount to buyer including shipping fee
        uint256 refundAmount = escrow.amount + STANDARD_SHIPPING_FEE;
        (bool success,) = payable(order.buyer).call{value: refundAmount}("");
        require(success, "Refund payment failed");

        // Update product stock if needed
        if (products[order.productId].id == order.productId) {
            products[order.productId].stockQuantity += order.quantity;
            products[order.productId].soldCount -= order.quantity;
        }

        // Update status if needed
        if (order.status != OrderStatus.CANCELLED) {
            order.status = OrderStatus.CANCELLED;
            order.updatedAt = block.timestamp;
            emit OrderStatusUpdated(orderId, OrderStatus.CANCELLED);
        }

        emit EscrowRefunded(orderId, order.buyer, refundAmount);
    }

    // Function to handle disputes
    function createDispute(uint256 orderId, string memory reason) external onlyOrderParticipant(orderId) orderExists(orderId) {
        Order storage order = orders[orderId];
        require(!order.isDisputed, "Dispute already exists");
        require(
            order.status == OrderStatus.PAID || 
            order.status == OrderStatus.PROCESSING || 
            order.status == OrderStatus.SHIPPED || 
            order.status == OrderStatus.DELIVERED,
            "Order not in disputable state"
        );

        uint256 disputeId = _incrementDisputeId();
        
        disputes[disputeId] = Dispute({
            id: disputeId,
            orderId: orderId,
            initiator: msg.sender,
            reason: reason,
            resolution: DisputeResolution.NONE,
            createdAt: block.timestamp,
            resolvedAt: 0
        });
        
        order.isDisputed = true;
        order.disputeReason = reason;
        order.status = OrderStatus.DISPUTED;
        order.updatedAt = block.timestamp;
        
        emit DisputeCreated(orderId, msg.sender);
        emit OrderStatusUpdated(orderId, OrderStatus.DISPUTED);
    }

    // Function to resolve disputes (admin only)
    function resolveDispute(
        uint256 disputeId, 
        DisputeResolution resolution
    ) external onlyAdmin nonReentrant {
        Dispute storage dispute = disputes[disputeId];
        require(dispute.id == disputeId, "Dispute does not exist");
        require(dispute.resolution == DisputeResolution.NONE, "Dispute already resolved");
        
        uint256 orderId = dispute.orderId;
        Order storage order = orders[orderId];
        Escrow storage escrow = escrows[orderId];
        
        require(order.isDisputed, "Order not disputed");
        require(!escrow.isReleased && !escrow.isRefunded, "Escrow already processed");
        
        dispute.resolution = resolution;
        dispute.resolvedAt = block.timestamp;
        
        if (resolution == DisputeResolution.REFUND_BUYER) {
            // Refund to buyer
            refundEscrow(orderId);
        } else if (resolution == DisputeResolution.RELEASE_TO_SELLER) {
            // Release to seller
            releaseEscrow(orderId);
        } else if (resolution == DisputeResolution.PARTIAL_REFUND) {
            // Partial refund (50-50 split)
            escrow.isReleased = true;
            escrow.isRefunded = true;
            escrow.releasedAt = block.timestamp;
            
            uint256 halfAmount = escrow.sellerAmount / 2;
            uint256 buyerRefund = halfAmount + STANDARD_SHIPPING_FEE;
            uint256 sellerPayout = escrow.sellerAmount - halfAmount;
            
            // Pay seller half
            (bool sellerSuccess,) = payable(order.seller).call{value: sellerPayout}("");
            require(sellerSuccess, "Seller partial payment failed");
            
            // Refund buyer half + shipping
            (bool buyerSuccess,) = payable(order.buyer).call{value: buyerRefund}("");
            require(buyerSuccess, "Buyer partial refund failed");
            
            // Pay developer fee
            (bool devSuccess,) = payable(_developerWallet).call{value: escrow.developerFee}("");
            require(devSuccess, "Developer fee payment failed");
            
            _developerTotalFees += escrow.developerFee;
        }
        
        order.isDisputed = false;
        order.updatedAt = block.timestamp;
        
        emit DisputeResolved(orderId, resolution);
    }

    // Automatic escrow release after time period (can be called by anyone after 14 days of delivery)
    function autoReleaseEscrow(uint256 orderId) external orderExists(orderId) {
        Order storage order = orders[orderId];
        Escrow storage escrow = escrows[orderId];
        
        require(order.status == OrderStatus.DELIVERED, "Order not delivered");
        require(!escrow.isReleased && !escrow.isRefunded, "Escrow already processed");
        require(block.timestamp >= order.updatedAt + 14 days, "Auto-release time not reached");
        
        // Auto-release escrow to seller
        releaseEscrow(orderId);
    }

    // Additional getter functions for escrow status
    function getEscrowDetails(uint256 orderId) external view returns (
        uint256 amount,
        uint256 developerFee,
        uint256 sellerAmount,
        bool isReleased,
        bool isRefunded,
        uint256 createdAt,
        uint256 releasedAt
    ) {
        Escrow storage escrow = escrows[orderId];
        return (
            escrow.amount,
            escrow.developerFee,
            escrow.sellerAmount,
            escrow.isReleased,
            escrow.isRefunded,
            escrow.createdAt,
            escrow.releasedAt
        );
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
// pragma solidity ^0.8.20;

// import "@openzeppelin/contracts/access/Ownable.sol";
// import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// contract Farm is Ownable, ReentrancyGuard {
//     using Counters for Counters.Counter;

//     // Structs
//     struct UserProfile {
//         string name;
//         string contactInfo;
//         string location;
//         bool isVerified;
//         uint256 rating;
//     }

//     struct Product {
//         uint256 id;
//         address seller;
//         string name;
//         string category;
//         uint256 price;
//         uint256 stockQuantity;
//         string unit; // kg/size
//         string description;
//         string[] imageUrls;
//         bool isAvailable;
//         uint256 createdAt;
//     }

//     struct Order {
//         uint256 id;
//         address buyer;
//         address seller;
//         uint256 productId;
//         uint256 quantity;
//         uint256 totalPrice;
//         OrderStatus status;
//         uint256 createdAt;
//         uint256 updatedAt;
//     }

//     enum OrderStatus {
//         NEW,
//         PAID,
//         PROCESSING,
//         SHIPPED,
//         DELIVERED,
//         CANCELLED
//     }

//     // Events
//     event UserProfileCreated(address indexed user, string name);
//     event ProductAdded(uint256 indexed productId, address indexed seller, string name);
//     event ProductUpdated(uint256 indexed productId);
//     event OrderCreated(uint256 indexed orderId, address indexed buyer, address indexed seller);
//     event OrderStatusUpdated(uint256 indexed orderId, OrderStatus status);
//     event PaymentReleased(uint256 indexed orderId, uint256 amount);
//     event WithdrawalMade(address indexed seller, uint256 amount);

//     // State Variables
//     mapping(address => UserProfile) public userProfiles;
//     mapping(uint256 => Product) public products;
//     mapping(uint256 => Order) public orders;
//     mapping(address => uint256[]) public sellerProducts;
//     mapping(address => uint256[]) public buyerOrders;
//     mapping(address => uint256) public sellerBalances;
//     mapping(address => uint256) public pendingWithdrawals;

//     Counters.Counter private _productIds;
//     Counters.Counter private _orderIds;

//     uint256 private constant DEVELOPER_FEE_PERCENT = 1;
//     address private _developerWallet;

//     // Constructor
//     constructor(address developerWallet) {
//         _developerWallet = developerWallet;
//     }

//     // User Profile Functions
//     function createUserProfile(string memory name, string memory contactInfo, string memory location) external {
//         require(bytes(name).length > 0, "Name cannot be empty");

//         UserProfile storage profile = userProfiles[msg.sender];
//         profile.name = name;
//         profile.contactInfo = contactInfo;
//         profile.location = location;
//         profile.isVerified = false;
//         profile.rating = 5; // Default rating

//         emit UserProfileCreated(msg.sender, name);
//     }

//     function updateUserProfile(string memory name, string memory contactInfo, string memory location) external {
//         UserProfile storage profile = userProfiles[msg.sender];
//         profile.name = name;
//         profile.contactInfo = contactInfo;
//         profile.location = location;
//     }

//     // Product Management Functions
//     function addProduct(
//         string memory name,
//         string memory category,
//         uint256 price,
//         uint256 stockQuantity,
//         string memory unit,
//         string memory description,
//         string[] memory imageUrls
//     ) external {
//         _productIds.increment();
//         uint256 newProductId = _productIds.current();

//         products[newProductId] = Product({
//             id: newProductId,
//             seller: msg.sender,
//             name: name,
//             category: category,
//             price: price,
//             stockQuantity: stockQuantity,
//             unit: unit,
//             description: description,
//             imageUrls: imageUrls,
//             isAvailable: true,
//             createdAt: block.timestamp
//         });

//         sellerProducts[msg.sender].push(newProductId);

//         emit ProductAdded(newProductId, msg.sender, name);
//     }

//     function updateProduct(
//         uint256 productId,
//         string memory name,
//         string memory category,
//         uint256 price,
//         uint256 stockQuantity,
//         string memory unit,
//         string memory description,
//         string[] memory imageUrls,
//         bool isAvailable
//     ) external {
//         require(products[productId].seller == msg.sender, "Only seller can update");

//         Product storage product = products[productId];
//         product.name = name;
//         product.category = category;
//         product.price = price;
//         product.stockQuantity = stockQuantity;
//         product.unit = unit;
//         product.description = description;
//         product.imageUrls = imageUrls;
//         product.isAvailable = isAvailable;

//         emit ProductUpdated(productId);
//     }

//     function deleteProduct(uint256 productId) external {
//         require(products[productId].seller == msg.sender, "Only seller can delete");
//         delete products[productId];
//     }

//     // Order Management Functions
//     function createOrder(uint256 productId, uint256 quantity) external payable {
//         Product storage product = products[productId];
//         require(product.isAvailable, "Product not available");
//         require(product.stockQuantity >= quantity, "Insufficient stock");
//         require(msg.value == product.price * quantity, "Incorrect payment");

//         _orderIds.increment();
//         uint256 newOrderId = _orderIds.current();

//         // Calculate fees
//         uint256 developerFee = (msg.value * DEVELOPER_FEE_PERCENT) / 100;
//         uint256 sellerAmount = msg.value - developerFee;

//         orders[newOrderId] = Order({
//             id: newOrderId,
//             buyer: msg.sender,
//             seller: product.seller,
//             productId: productId,
//             quantity: quantity,
//             totalPrice: msg.value,
//             status: OrderStatus.NEW,
//             createdAt: block.timestamp,
//             updatedAt: block.timestamp
//         });

//         // Update product stock
//         product.stockQuantity -= quantity;

//         // Track orders for buyer and seller
//         buyerOrders[msg.sender].push(newOrderId);

//         // Add to seller's pending balance
//         pendingWithdrawals[product.seller] += sellerAmount;

//         // Track developer fee
//         pendingWithdrawals[_developerWallet] += developerFee;

//         emit OrderCreated(newOrderId, msg.sender, product.seller);
//     }

//     function updateOrderStatus(uint256 orderId, OrderStatus newStatus) external {
//         Order storage order = orders[orderId];
//         require(msg.sender == order.seller || msg.sender == order.buyer, "Unauthorized");

//         order.status = newStatus;
//         order.updatedAt = block.timestamp;

//         emit OrderStatusUpdated(orderId, newStatus);
//     }

//     // Withdrawal Functions
//     function withdrawSellerFunds() external nonReentrant {
//         uint256 amount = pendingWithdrawals[msg.sender];
//         require(amount > 0, "No funds to withdraw");

//         pendingWithdrawals[msg.sender] = 0;
//         sellerBalances[msg.sender] += amount;

//         (bool success,) = payable(msg.sender).call{value: amount}("");
//         require(success, "Transfer failed");

//         emit WithdrawalMade(msg.sender, amount);
//     }

//     // Getter Functions
//     function getSellerProducts(address seller) external view returns (Product[] memory) {
//         uint256[] memory productIds = sellerProducts[seller];
//         Product[] memory sellerProductList = new Product[](productIds.length);

//         for (uint256 i = 0; i < productIds.length; i++) {
//             sellerProductList[i] = products[productIds[i]];
//         }

//         return sellerProductList;
//     }

//     function getAvailableProducts() external view returns (Product[] memory) {
//         uint256 availableCount = 0;

//         // First count available products
//         for (uint256 i = 1; i <= _productIds.current(); i++) {
//             if (products[i].isAvailable && products[i].stockQuantity > 0) {
//                 availableCount++;
//             }
//         }

//         // Then populate the array
//         Product[] memory availableProducts = new Product[](availableCount);
//         uint256 index = 0;

//         for (uint256 i = 1; i <= _productIds.current(); i++) {
//             if (products[i].isAvailable && products[i].stockQuantity > 0) {
//                 availableProducts[index] = products[i];
//                 index++;
//             }
//         }

//         return availableProducts;
//     }

//     function getBuyerOrders(address buyer) external view returns (Order[] memory) {
//         uint256[] memory orderIds = buyerOrders[buyer];
//         Order[] memory buyerOrderList = new Order[](orderIds.length);

//         for (uint256 i = 0; i < orderIds.length; i++) {
//             buyerOrderList[i] = orders[orderIds[i]];
//         }

//         return buyerOrderList;
//     }

//     // Statistics and Tracking Functions
//     function getSellerStats(address seller)
//         external
//         view
//         returns (uint256 totalProducts, uint256 totalOrders, uint256 totalRevenue, uint256 availableBalance)
//     {
//         totalProducts = sellerProducts[seller].length;

//         uint256 completedOrders = 0;
//         uint256 revenue = 0;

//         for (uint256 i = 1; i <= _orderIds.current(); i++) {
//             if (orders[i].seller == seller && orders[i].status == OrderStatus.DELIVERED) {
//                 completedOrders++;
//                 revenue += orders[i].totalPrice;
//             }
//         }

//         totalOrders = completedOrders;
//         totalRevenue = revenue;
//         availableBalance = pendingWithdrawals[seller];
//     }

//     // Additional Utility Functions
//     function getOrderCountByStatus(OrderStatus status) external view returns (uint256) {
//         uint256 count = 0;
//         for (uint256 i = 1; i <= _orderIds.current(); i++) {
//             if (orders[i].status == status) {
//                 count++;
//             }
//         }
//         return count;
//     }

//     // Fallback function to receive Ether
//     receive() external payable {}
// }
