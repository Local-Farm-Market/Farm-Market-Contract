    // SPDX-License-Identifier: MIT
    pragma solidity ^0.8.20;

    import "@openzeppelin/contracts/access/Ownable.sol";
    import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
    import "@openzeppelin/contracts/utils/Pausable.sol";

    contract Farm is Ownable, ReentrancyGuard, Pausable {

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
            uint256[] productIds;
            uint256[] quantities;
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

        struct Dispute {
            uint256 orderId;
            address initiator;
            string reason;
            bool resolved;
            DisputeResolution resolution;
            uint256 createdAt;
            uint256 resolvedAt;
        }

        //Enums
        enum OrderStatus {
            NEW,
            PAYMENT_ESCROWED,
            PROCESSING,
            IN_DELIVERY,
            DELIVERED,
            COMPLETED,
            CANCELLED,
            DISPUTED
        }

        enum DisputeResolution {
            NONE,
            REFUND_BUYER,
            RELEASE_TO_SELLER,
            PARTIAL_REFUND
        }

        // Events remain the same
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
        uint256 private constant STANDARD_SHIPPING_FEE = 5 ether;  // 5 USD in wei
        address private _developerWallet;
        uint256 private _platformTotalVolume;
        uint256 private _platformTotalOrders;

        // Constructor
        constructor(address developerWallet) Ownable (msg.sender){
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
        function createUserProfile(string memory name, string memory contactInfo, string memory location, string memory bio, bool isSeller, string[] memory certifications ) external {
            require(bytes(name).length > 0, "Name cannot be empty");

            UserProfile storage profile = userProfiles[msg.sender];
            profile.name = name;
            profile.contactInfo = contactInfo;
            profile.location = location;
            profile.bio = bio;
            profile.isVerified = false;
            profile.rating = 5; // Default rating
            profile.reviewCount = 0;
            profile.certifications = certifications;
            profile.createdAt = block.timestamp;
            profile.isSeller = isSeller;

            emit UserProfileCreated(msg.sender, name, isSeller);
        }

        //++++++++++++ Function to update user profile ++++++++++++//
        function updateUserProfile(string memory name, string memory contactInfo, string memory location, string memory bio, string[] memory certifications) external {
            require(bytes(userProfiles[msg.sender].name).length > 0, "Profile does not exist");

            UserProfile storage profile = userProfiles[msg.sender];
            profile.name = name;
            profile.contactInfo = contactInfo;
            profile.location = location;
            profile.bio = bio;
            profile.certifications = certifications;

            emit UserProfileUpdated(msg.sender);
        }

        //++++++++++++ Function to toggle seller status ++++++++++++//
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
        ) external onlySeller whenNotPaused{
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
        ) external onlySeller productExists(productId) whenNotPaused{
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

        //Function to delete product
        function deleteProduct(uint256 productId) external onlySeller productExists(productId) whenNotPaused{
            require(products[productId].seller == msg.sender, "Only seller can delete");

            // Remove from category mapping
            uint256[] storage categoryProducts = productsByCategory[products[productId].category];
            for (uint256 i = 0; i < categoryProducts.length; i++) {
                if (categoryProducts[i] == productId) {
                    categoryProducts[i] = categoryProducts[categoryProducts.length - 1];
                    categoryProducts.pop();
                    break;
                }
            }
            
            // Remove from seller products
            uint256[] storage sellerProductsList = sellerProducts[msg.sender];
            for (uint256 i = 0; i < sellerProductsList.length; i++) {
                if (sellerProductsList[i] == productId) {
                    sellerProductsList[i] = sellerProductsList[sellerProductsList.length - 1];
                    sellerProductsList.pop();
                    break;
                }
            }

            delete products[productId];

            emit ProductDeleted(productId);
        }

        //++++++++++++ Function to update product stock +++++++++++++//
        function updateProductStock(uint256 productId, uint256 newStockQuantity) external onlySeller productExists(productId) whenNotPaused {
            require(products[productId].seller == msg.sender, "Only seller can update");
            
            products[productId].stockQuantity = newStockQuantity;
            
            // If stock is 0, set availability to false
            if (newStockQuantity == 0) {
                products[productId].isAvailable = false;
            }
            
            emit ProductUpdated(productId);
        }

        //++++++++++++ Function to toggle product availability ++++++++++++//
        function toggleProductAvailability(uint256 productId) external onlySeller productExists(productId) whenNotPaused {
            require(products[productId].seller == msg.sender, "Only seller can update");
            
            products[productId].isAvailable = !products[productId].isAvailable;
            
            emit ProductUpdated(productId);
        }

        // Order Management Functions
        function createOrder(uint256[] memory productIds, uint256[] memory quantities, string memory shippingAddress) external payable whenNotPaused{
            require(productIds.length > 0, "No products specified");
            require(productIds.length == quantities.length, "Product and quantity arrays must match");
            require(bytes(shippingAddress).length > 0, "Shipping address required");
            
            uint256 totalAmount = STANDARD_SHIPPING_FEE; // Start with shipping fee
            address seller;
            
            // Verify all products have the same seller and calculate total price
            for (uint256 i = 0; i < productIds.length; i++) {
                uint256 productId = productIds[i];
                uint256 quantity = quantities[i];
                
                require(products[productId].id == productId, "Product does not exist");
                require(products[productId].isAvailable, "Product not available");
                require(products[productId].stockQuantity >= quantity, "Insufficient stock");
                
                if (i == 0) {
                    seller = products[productId].seller;
                } else {
                    require(products[productId].seller == seller, "All products must be from the same seller");
                }
                
                totalAmount += products[productId].price * quantity;
            }
            
            require(msg.value == totalAmount, "Incorrect payment amount");
            // Product storage product = products[productId];
            // require(product.isAvailable, "Product not available");
            // require(product.stockQuantity >= quantity, "Insufficient stock");
            // require(msg.value == product.price * quantity, "Incorrect payment");

            uint256 newOrderId = _incrementOrderId();

            // Calculate fees
            uint256 developerFee = (msg.value * DEVELOPER_FEE_PERCENT) / 100;
            uint256 sellerAmount = msg.value - developerFee - STANDARD_SHIPPING_FEE;

            orders[newOrderId] = Order({
                id: newOrderId,
                buyer: msg.sender,
                seller: seller,
                productIds: productIds,
                quantities: quantities,
                totalPrice: totalAmount,
                shippingFee: STANDARD_SHIPPING_FEE,
                status: OrderStatus.PAYMENT_ESCROWED,
                shippingAddress: shippingAddress,
                trackingInfo: "",
                createdAt: block.timestamp,
                updatedAt: block.timestamp,
                isDisputed: false,
                disputeReason: ""
            });

            // Update product stock and sold count
            for (uint256 i = 0; i < productIds.length; i++) {
                uint256 productId = productIds[i];
                uint256 quantity = quantities[i];
                
                products[productId].stockQuantity -= quantity;
                products[productId].soldCount += quantity;
                
                // If stock is 0, set availability to false
                if (products[productId].stockQuantity == 0) {
                    products[productId].isAvailable = false;
                }
            }

            // Track orders for buyer and seller
            buyerOrders[msg.sender].push(newOrderId);
            sellerOrders[seller].push(newOrderId);

            // Add to seller's pending balance
            pendingWithdrawals[seller] += sellerAmount;

            // Track developer fee
            pendingWithdrawals[_developerWallet] += developerFee;

            // Update platform stats
            _platformTotalVolume += totalAmount;
            _platformTotalOrders++;

            emit OrderCreated(newOrderId, msg.sender, seller);
        }

        // Remaining functions are identical to the original contract
        function updateOrderStatus(uint256 orderId, OrderStatus newStatus) external orderExists(orderId) onlyOrderParticipant(orderId) whenNotPaused {
            Order storage order = orders[orderId];
            require(!order.isDisputed, "Cannot update disputed order");
            // require(msg.sender == order.seller || msg.sender == order.buyer, "Unauthorized");

            // Validate status transitions
            if (msg.sender == order.seller) {
                require(
                    (order.status == OrderStatus.PAYMENT_ESCROWED && newStatus == OrderStatus.PROCESSING) ||
                    (order.status == OrderStatus.PROCESSING && newStatus == OrderStatus.IN_DELIVERY) ||
                    (order.status == OrderStatus.IN_DELIVERY && newStatus == OrderStatus.DELIVERED),
                    "Invalid status transition for seller"
                );
            } else if (msg.sender == order.buyer) {
                require(
                    (order.status == OrderStatus.DELIVERED && newStatus == OrderStatus.COMPLETED) ||
                    (order.status == OrderStatus.PAYMENT_ESCROWED && newStatus == OrderStatus.CANCELLED),
                    "Invalid status transition for buyer"
                );
                
                // If buyer confirms completion, release funds to seller
                if (newStatus == OrderStatus.COMPLETED) {
                    // Funds are already in pendingWithdrawals from createOrder
                    emit PaymentReleased(orderId, order.totalPrice);
                }
                
                // If buyer cancels, refund them
                if (newStatus == OrderStatus.CANCELLED) {
                    // Calculate refund amount (excluding developer fee which is kept)
                    uint256 refundAmount = order.totalPrice - (order.totalPrice * DEVELOPER_FEE_PERCENT / 100);
                    
                    // Remove from seller's pending withdrawals
                    pendingWithdrawals[order.seller] -= (refundAmount - STANDARD_SHIPPING_FEE);
                    
                    // Add back to product stock
                    for (uint256 i = 0; i < order.productIds.length; i++) {
                        uint256 productId = order.productIds[i];
                        uint256 quantity = order.quantities[i];
                        
                        products[productId].stockQuantity += quantity;
                        products[productId].soldCount -= quantity;
                        products[productId].isAvailable = true;
                    }
                    
                    // Refund buyer
                    (bool success, ) = payable(order.buyer).call{value: refundAmount}("");
                    require(success, "Refund failed");
                }
            }

            order.status = newStatus;
            order.updatedAt = block.timestamp;

            emit OrderStatusUpdated(orderId, newStatus);
        }

        //++++++++++++ Function to add tracking information ++++++++++++//
        function addTrackingInfo(uint256 orderId, string memory trackingInfo) 
            external 
            orderExists(orderId) 
            whenNotPaused 
        {
            Order storage order = orders[orderId];
            require(msg.sender == order.seller, "Only seller can add tracking info");
            require(order.status == OrderStatus.PROCESSING || order.status == OrderStatus.IN_DELIVERY, "Order not in processing or delivery");
            
            order.trackingInfo = trackingInfo;
            order.updatedAt = block.timestamp;
            
            emit OrderStatusUpdated(orderId, order.status);
        }

        //++++++++++++ Function to create dispute ++++++++++++//
        function createDispute(uint256 orderId, string memory reason) 
            external 
            orderExists(orderId) 
            whenNotPaused 
        {
            Order storage order = orders[orderId];
            require(msg.sender == order.buyer, "Only buyer can create dispute");
            require(!order.isDisputed, "Dispute already exists");
            require(
                order.status == OrderStatus.PAYMENT_ESCROWED || 
                order.status == OrderStatus.PROCESSING || 
                order.status == OrderStatus.IN_DELIVERY || 
                order.status == OrderStatus.DELIVERED,
                "Cannot dispute order in current status"
            );
            
            order.isDisputed = true;
            order.disputeReason = reason;
            order.status = OrderStatus.DISPUTED;
            order.updatedAt = block.timestamp;
            
            uint256 disputeId = _incrementDisputeId();
            
            disputes[disputeId] = Dispute({
                orderId: orderId,
                initiator: msg.sender,
                reason: reason,
                resolved: false,
                resolution: DisputeResolution.NONE,
                createdAt: block.timestamp,
                resolvedAt: 0
            });
            
            emit DisputeCreated(orderId, msg.sender);
            emit OrderStatusUpdated(orderId, OrderStatus.DISPUTED);
        }

        //++++++++++++ Function to resolve dispute ++++++++++++//
        function resolveDispute(uint256 orderId, DisputeResolution resolution) 
            external 
            onlyOwner 
            orderExists(orderId) 
            whenNotPaused 
        {
            Order storage order = orders[orderId];
            require(order.isDisputed, "No dispute exists");
            require(order.status == OrderStatus.DISPUTED, "Order not in disputed status");
            
            // Find the dispute
            uint256 disputeId = 0;
            for (uint256 i = 1; i <= _disputeIds; i++) {
                if (disputes[i].orderId == orderId && !disputes[i].resolved) {
                    disputeId = i;
                    break;
                }
            }
            
            require(disputeId > 0, "Dispute not found");
            
            Dispute storage dispute = disputes[disputeId];
            
            if (resolution == DisputeResolution.REFUND_BUYER) {
                // Calculate refund amount (excluding developer fee which is kept)
                uint256 refundAmount = order.totalPrice - (order.totalPrice * DEVELOPER_FEE_PERCENT / 100);
                
                // Remove from seller's pending withdrawals
                pendingWithdrawals[order.seller] -= (refundAmount - STANDARD_SHIPPING_FEE);
                
                // Refund buyer
                (bool success, ) = payable(order.buyer).call{value: refundAmount}("");
                require(success, "Refund failed");
                
                order.status = OrderStatus.CANCELLED;
            } 
            else if (resolution == DisputeResolution.RELEASE_TO_SELLER) {
                // Funds are already in pendingWithdrawals from createOrder
                order.status = OrderStatus.COMPLETED;
            }
            else if (resolution == DisputeResolution.PARTIAL_REFUND) {
                // Calculate partial refund (50%)
                uint256 refundAmount = (order.totalPrice - STANDARD_SHIPPING_FEE) / 2;
                
                // Adjust seller's pending withdrawals
                pendingWithdrawals[order.seller] -= refundAmount;
                
                // Refund buyer
                (bool success, ) = payable(order.buyer).call{value: refundAmount}("");
                require(success, "Partial refund failed");
                
                order.status = OrderStatus.COMPLETED;
            }
            
            dispute.resolved = true;
            dispute.resolution = resolution;
            dispute.resolvedAt = block.timestamp;
            
            order.updatedAt = block.timestamp;
            
            emit DisputeResolved(orderId, resolution);
            emit OrderStatusUpdated(orderId, order.status);
        }

        function withdrawFunds() external nonReentrant whenNotPaused {
            uint256 amount = pendingWithdrawals[msg.sender];
            require(amount > 0, "No funds to withdraw");

            pendingWithdrawals[msg.sender] = 0;
            sellerBalances[msg.sender] += amount;

            (bool success,) = payable(msg.sender).call{value: amount}("");
            require(success, "Transfer failed");

            emit WithdrawalMade(msg.sender, amount);
        }

        //++++++++++++ Function to submit review ++++++++++++//
        function submitReview(
            address reviewee,
            uint256 productId,
            uint256 orderId,
            uint256 rating,
            string memory comment
        ) external whenNotPaused {
            require(rating >= 1 && rating <= 5, "Rating must be between 1 and 5");
            
            // If reviewing a product, verify the reviewer bought it
            if (productId > 0) {
                bool hasBought = false;
                uint256[] memory buyerOrdersList = buyerOrders[msg.sender];
                
                for (uint256 i = 0; i < buyerOrdersList.length; i++) {
                    Order storage order = orders[buyerOrdersList[i]];
                    if (order.status == OrderStatus.COMPLETED) {
                        for (uint256 j = 0; j < order.productIds.length; j++) {
                            if (order.productIds[j] == productId) {
                                hasBought = true;
                                break;
                            }
                        }
                    }
                    if (hasBought) break;
                }
                
                require(hasBought, "You must purchase the product before reviewing");
            }
            
            // If reviewing an order, verify the reviewer is part of the order
            if (orderId > 0) {
                require(
                    orders[orderId].buyer == msg.sender || orders[orderId].seller == msg.sender,
                    "You must be part of the order to review it"
                );
                require(orders[orderId].status == OrderStatus.COMPLETED, "Order must be completed to review");
            }
            
            uint256 reviewId = _incrementReviewId();
            
            Review memory newReview = Review({
                id: reviewId,
                reviewer: msg.sender,
                reviewee: reviewee,
                productId: productId,
                orderId: orderId,
                rating: rating,
                comment: comment,
                timestamp: block.timestamp
            });
            
            // Store review in appropriate mappings
            if (productId > 0) {
                productReviews[productId].push(newReview);
                
                // Update product seller's rating
                address seller = products[productId].seller;
                UserProfile storage sellerProfile = userProfiles[seller];
                
                uint256 totalRating = sellerProfile.rating * sellerProfile.reviewCount;
                totalRating += rating;
                sellerProfile.reviewCount++;
                sellerProfile.rating = totalRating / sellerProfile.reviewCount;
            }
            
            if (reviewee != address(0)) {
                userReviews[reviewee].push(newReview);
                
                // Update reviewee's rating if they're not being reviewed as a product seller
                if (productId == 0) {
                    UserProfile storage revieweeProfile = userProfiles[reviewee];
                    
                    uint256 totalRating = revieweeProfile.rating * revieweeProfile.reviewCount;
                    totalRating += rating;
                    revieweeProfile.reviewCount++;
                    revieweeProfile.rating = totalRating / revieweeProfile.reviewCount;
                }
            }
            
            emit ReviewSubmitted(reviewId, msg.sender, reviewee);
        }

        // ++++++++++++ Function to toggle favorite products ++++++++++++ //
        function toggleFavoriteProduct(uint256 productId) external productExists(productId) whenNotPaused {
            bool isFavorite = favoriteProducts[msg.sender][productId];
            
            if (isFavorite) {
                // Remove from favorites
                favoriteProducts[msg.sender][productId] = false;
                
                uint256[] storage favorites = userFavorites[msg.sender];
                for (uint256 i = 0; i < favorites.length; i++) {
                    if (favorites[i] == productId) {
                        favorites[i] = favorites[favorites.length - 1];
                        favorites.pop();
                        break;
                    }
                }
            } else {
                // Add to favorites
                favoriteProducts[msg.sender][productId] = true;
                userFavorites[msg.sender].push(productId);
            }
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

        //++++++++++++ Function to get products by category ++++++++++++//
        function getProductsByCategory(string memory category) external view returns (Product[] memory) {
            uint256[] memory productIds = productsByCategory[category];
            Product[] memory categoryProducts = new Product[](productIds.length);
            
            for (uint256 i = 0; i < productIds.length; i++) {
                categoryProducts[i] = products[productIds[i]];
            }
            
            return categoryProducts;
        }

        //+++++++++++++ Function to get user favorites ++++++++++++//
        function getUserFavorites(address user) external view returns (Product[] memory) {
            uint256[] memory favoriteIds = userFavorites[user];
            Product[] memory favoritesList = new Product[](favoriteIds.length);
            
            for (uint256 i = 0; i < favoriteIds.length; i++) {
                favoritesList[i] = products[favoriteIds[i]];
            }
            
            return favoritesList;
        }

        //+++++++++++++ Function to get user certification ++++++++++++//
        function getUserCertifications(address user) external view returns (string[] memory) {
            return userProfiles[user].certifications;
        }


        //+++++++++++++ Function to get user reviews ++++++++++++//
        function getProductReviews(uint256 productId) external view returns (Review[] memory) {
            return productReviews[productId];
        }

        //+++++++++++++ Function to get Product reviews ++++++++++++//
        function getUserReviews(address user) external view returns (Review[] memory) {
            return userReviews[user];
        }

        //+++++++++++++ Function to get user details +++++++++++++//
        function getUserProfile(address user) external view returns (
            string memory name,
            string memory contactInfo,
            string memory location,
            string memory bio,
            bool isVerified,
            uint256 rating,
            uint256 reviewCount,
            string[] memory certifications,
            uint256 createdAt,
            bool isSeller
        ) {
            UserProfile storage profile = userProfiles[user];
            return (
                profile.name,
                profile.contactInfo,
                profile.location,
                profile.bio,
                profile.isVerified,
                profile.rating,
                profile.reviewCount,
                profile.certifications,
                profile.createdAt,
                profile.isSeller
            );
        }
        function getBuyerOrders(address buyer) external view returns (Order[] memory) {
            uint256[] memory orderIds = buyerOrders[buyer];
            Order[] memory buyerOrderList = new Order[](orderIds.length);

            for (uint256 i = 0; i < orderIds.length; i++) {
                buyerOrderList[i] = orders[orderIds[i]];
            }

            return buyerOrderList;
        }

        // Statistics and Tracking Functions

        //++++++++++++ Function to get sellers statistics ++++++++++++//    
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

        //++++++++++++ Function to get buyer statistics ++++++++++++// 
        function getBuyerStats(address buyer)
            external
            view
            returns (uint256 totalOrders, uint256 totalSpent, uint256 availableBalance)
        {
            uint256 completedOrders = 0;
            uint256 spent = 0;
            
            for (uint256 i = 1; i <= _orderIds; i++) {
                if (orders[i].buyer == buyer && orders[i].status == OrderStatus.COMPLETED) {
                    completedOrders++;
                    spent += orders[i].totalPrice;
                }
            }
            
            totalOrders = completedOrders;
            totalSpent = spent;
            availableBalance = userBalances[buyer];
        }

        //++++++++++++ Function to get platform statistics ++++++++++++// 
        function getPlatformStats() external view returns (uint256 totalVolume, uint256 totalOrders, uint256 totalProducts) {
            return (_platformTotalVolume, _platformTotalOrders, _productIds);
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

        // Admin Functions 
        
        //++++++++++++ Function to pause contract ++++++++++++// 
        function pause() external onlyOwner {
            _pause();
        }

        //++++++++++++ Function to unpause contract ++++++++++++// 
        function unpause() external onlyOwner {
            _unpause();
        }

        //++++++++++++ Function to set developer wallet ++++++++++++//
        function setDeveloperWallet(address newDeveloperWallet) external onlyOwner {
            require(newDeveloperWallet != address(0), "Invalid address");
            _developerWallet = newDeveloperWallet;
        }

        //++++++++++++ Function to verify user ++++++++++++//
        function verifyUser(address user) external onlyOwner {
            require(bytes(userProfiles[user].name).length > 0, "User profile does not exist");
            userProfiles[user].isVerified = true;
        }

        // Fallback function to receive Ether
        receive() external payable {}
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