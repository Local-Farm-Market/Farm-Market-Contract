
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

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract Farm is Ownable, ReentrancyGuard {
    // Structs remain the same as in the original contract
    struct UserProfile {
        string name;
        string contactInfo;
        string location;
        bool isVerified;
        uint256 rating;
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
        uint256 createdAt;
    }

    struct Order {
        uint256 id;
        address buyer;
        address seller;
        uint256 productId;
        uint256 quantity;
        uint256 totalPrice;
        OrderStatus status;
        uint256 createdAt;
        uint256 updatedAt;
    }

    enum OrderStatus {
        NEW,
        PAID,
        PROCESSING,
        SHIPPED,
        DELIVERED,
        CANCELLED
    }

    // Events remain the same
    event UserProfileCreated(address indexed user, string name);
    event ProductAdded(uint256 indexed productId, address indexed seller, string name);
    event ProductUpdated(uint256 indexed productId);
    event OrderCreated(uint256 indexed orderId, address indexed buyer, address indexed seller);
    event OrderStatusUpdated(uint256 indexed orderId, OrderStatus status);
    event PaymentReleased(uint256 indexed orderId, uint256 amount);
    event WithdrawalMade(address indexed seller, uint256 amount);

    // State Variables
    mapping(address => UserProfile) public userProfiles;
    mapping(uint256 => Product) public products;
    mapping(uint256 => Order) public orders;
    mapping(address => uint256[]) public sellerProducts;
    mapping(address => uint256[]) public buyerOrders;
    mapping(address => uint256) public sellerBalances;
    mapping(address => uint256) public pendingWithdrawals;

    // Replace Counters with native uint256 tracking
    uint256 private _productIds;
    uint256 private _orderIds;

    uint256 private constant DEVELOPER_FEE_PERCENT = 1;
    address private _developerWallet;

    // Constructor
    constructor(address developerWallet) Ownable (){
        _developerWallet = developerWallet;
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
    function createUserProfile(string memory name, string memory contactInfo, string memory location) external {
        require(bytes(name).length > 0, "Name cannot be empty");

        UserProfile storage profile = userProfiles[msg.sender];
        profile.name = name;
        profile.contactInfo = contactInfo;
        profile.location = location;
        profile.isVerified = false;
        profile.rating = 5; // Default rating

        emit UserProfileCreated(msg.sender, name);
    }

    function updateUserProfile(string memory name, string memory contactInfo, string memory location) external {
        UserProfile storage profile = userProfiles[msg.sender];
        profile.name = name;
        profile.contactInfo = contactInfo;
        profile.location = location;
    }

    // Product Management Functions
    function addProduct(
        string memory name,
        string memory category,
        uint256 price,
        uint256 stockQuantity,
        string memory unit,
        string memory description,
        string[] memory imageUrls
    ) external {
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
            createdAt: block.timestamp
        });

        sellerProducts[msg.sender].push(newProductId);

        emit ProductAdded(newProductId, msg.sender, name);
    }

    function updateProduct(
        uint256 productId,
        string memory name,
        string memory category,
        uint256 price,
        uint256 stockQuantity,
        string memory unit,
        string memory description,
        string[] memory imageUrls,
        bool isAvailable
    ) external {
        require(products[productId].seller == msg.sender, "Only seller can update");

        Product storage product = products[productId];
        product.name = name;
        product.category = category;
        product.price = price;
        product.stockQuantity = stockQuantity;
        product.unit = unit;
        product.description = description;
        product.imageUrls = imageUrls;
        product.isAvailable = isAvailable;

        emit ProductUpdated(productId);
    }

    function deleteProduct(uint256 productId) external {
        require(products[productId].seller == msg.sender, "Only seller can delete");
        delete products[productId];
    }

    // Order Management Functions
    function createOrder(uint256 productId, uint256 quantity) external payable {
        Product storage product = products[productId];
        require(product.isAvailable, "Product not available");
        require(product.stockQuantity >= quantity, "Insufficient stock");
        require(msg.value == product.price * quantity, "Incorrect payment");

        uint256 newOrderId = _incrementOrderId();

        // Calculate fees
        uint256 developerFee = (msg.value * DEVELOPER_FEE_PERCENT) / 100;
        uint256 sellerAmount = msg.value - developerFee;

        orders[newOrderId] = Order({
            id: newOrderId,
            buyer: msg.sender,
            seller: product.seller,
            productId: productId,
            quantity: quantity,
            totalPrice: msg.value,
            status: OrderStatus.NEW,
            createdAt: block.timestamp,
            updatedAt: block.timestamp
        });

        // Update product stock
        product.stockQuantity -= quantity;

        // Track orders for buyer and seller
        buyerOrders[msg.sender].push(newOrderId);

        // Add to seller's pending balance
        pendingWithdrawals[product.seller] += sellerAmount;

        // Track developer fee
        pendingWithdrawals[_developerWallet] += developerFee;

        emit OrderCreated(newOrderId, msg.sender, product.seller);
    }

    // Remaining functions are identical to the original contract
    function updateOrderStatus(uint256 orderId, OrderStatus newStatus) external {
        Order storage order = orders[orderId];
        require(msg.sender == order.seller || msg.sender == order.buyer, "Unauthorized");

        order.status = newStatus;
        order.updatedAt = block.timestamp;

        emit OrderStatusUpdated(orderId, newStatus);
    }

    function withdrawSellerFunds() external nonReentrant {
        uint256 amount = pendingWithdrawals[msg.sender];
        require(amount > 0, "No funds to withdraw");

        pendingWithdrawals[msg.sender] = 0;
        sellerBalances[msg.sender] += amount;

        (bool success,) = payable(msg.sender).call{value: amount}("");
        require(success, "Transfer failed");

        emit WithdrawalMade(msg.sender, amount);
    }

    // Getter functions will need slight modifications to use _productIds and _orderIds
    function getSellerProducts(address seller) external view returns (Product[] memory) {
        uint256[] memory productIds = sellerProducts[seller];
        Product[] memory sellerProductList = new Product[](productIds.length);

        for (uint256 i = 0; i < productIds.length; i++) {
            sellerProductList[i] = products[productIds[i]];
        }

        return sellerProductList;
    }

    function getAvailableProducts() external view returns (Product[] memory) {
        uint256 availableCount = 0;

        // First count available products
        for (uint256 i = 1; i <= _productIds; i++) {
            if (products[i].isAvailable && products[i].stockQuantity > 0) {
                availableCount++;
            }
        }

        // Then populate the array
        Product[] memory availableProducts = new Product[](availableCount);
        uint256 index = 0;

        for (uint256 i = 1; i <= _productIds; i++) {
            if (products[i].isAvailable && products[i].stockQuantity > 0) {
                availableProducts[index] = products[i];
                index++;
            }
        }

        return availableProducts;
    }

    function getBuyerOrders(address buyer) external view returns (Order[] memory) {
        uint256[] memory orderIds = buyerOrders[buyer];
        Order[] memory buyerOrderList = new Order[](orderIds.length);

        for (uint256 i = 0; i < orderIds.length; i++) {
            buyerOrderList[i] = orders[orderIds[i]];
        }

        return buyerOrderList;
    }

    function getSellerStats(address seller)
        external
        view
        returns (uint256 totalProducts, uint256 totalOrders, uint256 totalRevenue, uint256 availableBalance)
    {
        totalProducts = sellerProducts[seller].length;

        uint256 completedOrders = 0;
        uint256 revenue = 0;

        for (uint256 i = 1; i <= _orderIds; i++) {
            if (orders[i].seller == seller && orders[i].status == OrderStatus.DELIVERED) {
                completedOrders++;
                revenue += orders[i].totalPrice;
            }
        }

        totalOrders = completedOrders;
        totalRevenue = revenue;
        availableBalance = pendingWithdrawals[seller];
    }

    function getOrderCountByStatus(OrderStatus status) external view returns (uint256) {
        uint256 count = 0;
        for (uint256 i = 1; i <= _orderIds; i++) {
            if (orders[i].status == status) {
                count++;
            }
        }
        return count;
    }

    // Fallback function to receive Ether
    receive() external payable {}
}