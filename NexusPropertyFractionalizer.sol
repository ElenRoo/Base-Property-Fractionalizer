// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

contract NexusPropertyFractionalizer {
    struct Property {
        address payable seller;
        uint256 pricePerShareWei;
        uint256 totalShares;
        uint256 availableShares;
        bool isActive;
        bool isFrozen;
        bytes32 propertyHash;
    }

    address payable public immutable hubAdmin;
    string public hubDescriptor;
    uint256 public platformFeeBps; // 250 = 2.5%
    uint256 public propertyCounter;
    uint256 public accumulatedFees;
    bool public isHubHalted;

    mapping(address => bool) public verifiedAppraisers;
    mapping(address => bool) public investorWhitelist;
    mapping(uint256 => Property) public properties;
    mapping(uint256 => mapping(address => uint256)) public sharesOwned;
    mapping(address => uint256) public pendingRefunds;

    event AppraiserAdded(address indexed appraiser);
    event SharesPurchased(uint256 indexed propertyId, address indexed buyer, uint256 shares, uint256 cost);
    event ListingCanceled(uint256 indexed propertyId);
    event TreasuryDeposited(address indexed funder, uint256 amount);
    event ReservesEmptied(address indexed admin, uint256 amount);
    event PropertyFrozen(uint256 indexed propertyId, bool frozenStatus);
    event FeesGathered(address indexed admin, uint256 amount);
    event HubHaltToggled(bool isHalted);
    event PriceIncreased(uint256 indexed propertyId, uint256 newPrice);
    event WhitelistJoined(address indexed investor);
    event PropertyListed(uint256 indexed propertyId, address indexed seller, uint256 shares);
    event AppraiserRevoked(address indexed appraiser);
    event DescriptorUpdated(string newDescriptor);
    event RefundWithdrawn(address indexed user, uint256 amount);

    modifier onlyAdmin() {
        require(msg.sender == hubAdmin, "NexusProp: Access denied");
        _;
    }

    modifier whenNotHalted() {
        require(!isHubHalted, "NexusProp: Hub is halted");
        _;
    }

    constructor() {
        hubAdmin = payable(msg.sender);
        hubDescriptor = "Nexus Base Property Fractionalizer v1";
        platformFeeBps = 250; // 2.5%
        isHubHalted = false;
        verifiedAppraisers[msg.sender] = true;
    }

    // 1. addVerifiedAppraiser
    function addVerifiedAppraiser(address appraiser) external onlyAdmin {
        require(!verifiedAppraisers[appraiser], "NexusProp: Already verified");
        verifiedAppraisers[appraiser] = true;
        emit AppraiserAdded(appraiser);
    }

    // 2. buyPropertyShares
    function buyPropertyShares(uint256 propertyId, uint256 sharesToBuy) external payable whenNotHalted {
        Property storage p = properties[propertyId];
        require(propertyId > 0 && propertyId <= propertyCounter, "NexusProp: Invalid ID");
        require(p.isActive && !p.isFrozen, "NexusProp: Not available");
        require(investorWhitelist[msg.sender], "NexusProp: Not whitelisted");
        require(sharesToBuy > 0 && sharesToBuy <= p.availableShares, "NexusProp: Invalid share amount");

        uint256 totalCost = sharesToBuy * p.pricePerShareWei;
        require(msg.value >= totalCost, "NexusProp: Insufficient payment");

        uint256 fee = (totalCost * platformFeeBps) / 10000;
        uint256 sellerShare = totalCost - fee;

        accumulatedFees += fee;
        p.availableShares -= sharesToBuy;
        sharesOwned[propertyId][msg.sender] += sharesToBuy;

        if (p.availableShares == 0) {
            p.isActive = false;
        }

        if (sellerShare > 0) {
            (bool sent, ) = p.seller.call{value: sellerShare}("");
            require(sent, "NexusProp: Payout failed");
        }

        // Сохраняем переплату (сдачу) для последующего вывода
        if (msg.value > totalCost) {
            pendingRefunds[msg.sender] += (msg.value - totalCost);
        }

        emit SharesPurchased(propertyId, msg.sender, sharesToBuy, totalCost);
    }

    // 3. cancelPropertyListing
    function cancelPropertyListing(uint256 propertyId) external {
        Property storage p = properties[propertyId];
        require(propertyId > 0 && propertyId <= propertyCounter, "NexusProp: Invalid ID");
        require(msg.sender == p.seller || msg.sender == hubAdmin, "NexusProp: Unauthorized");
        require(p.isActive, "NexusProp: Already inactive");

        p.isActive = false;
        emit ListingCanceled(propertyId);
    }

    // 4. depositPlatformTreasury
    function depositPlatformTreasury() external payable whenNotHalted {
        require(msg.value > 0, "NexusProp: Zero deposit");
        accumulatedFees += msg.value;
        emit TreasuryDeposited(msg.sender, msg.value);
    }

    // 5. emptyPlatformReserves
    function emptyPlatformReserves() external onlyAdmin {
        uint256 balance = address(this).balance;
        require(balance > 0, "NexusProp: Zero balance");

        accumulatedFees = 0;
        (bool sent, ) = hubAdmin.call{value: balance}("");
        require(sent, "NexusProp: Sweep failed");

        emit ReservesEmptied(hubAdmin, balance);
    }

    // 6. freezePropertyAsset
    function freezePropertyAsset(uint256 propertyId, bool freezeStatus) external onlyAdmin {
        Property storage p = properties[propertyId];
        require(propertyId > 0 && propertyId <= propertyCounter, "NexusProp: Invalid ID");
        p.isFrozen = freezeStatus;
        emit PropertyFrozen(propertyId, freezeStatus);
    }

    // 7. gatherPlatformFees
    function gatherPlatformFees() external onlyAdmin {
        uint256 amount = accumulatedFees;
        require(amount > 0, "NexusProp: Zero fees");

        accumulatedFees = 0;
        (bool sent, ) = hubAdmin.call{value: amount}("");
        require(sent, "NexusProp: Harvest failed");

        emit FeesGathered(hubAdmin, amount);
    }

    // 8. haltPropertyHub
    function haltPropertyHub(bool isHalted) external onlyAdmin {
        isHubHalted = isHalted;
        emit HubHaltToggled(isHalted);
    }

    // 9. increasePropertyPrice
    function increasePropertyPrice(uint256 propertyId, uint256 newPriceWei) external {
        Property storage p = properties[propertyId];
        require(propertyId > 0 && propertyId <= propertyCounter, "NexusProp: Invalid ID");
        require(msg.sender == p.seller, "NexusProp: Only seller");
        require(newPriceWei > p.pricePerShareWei, "NexusProp: Must increase price");
        require(p.isActive && !p.isFrozen, "NexusProp: Cannot edit now");

        p.pricePerShareWei = newPriceWei;
        emit PriceIncreased(propertyId, newPriceWei);
    }

    // 10. joinInvestorWhitelist
    function joinInvestorWhitelist() external whenNotHalted {
        require(!investorWhitelist[msg.sender], "NexusProp: Already in whitelist");
        investorWhitelist[msg.sender] = true;
        emit WhitelistJoined(msg.sender);
    }

    // 11. listNewProperty
    function listNewProperty(uint256 pricePerShareWei, uint256 totalShares, bytes32 propertyHash) external whenNotHalted returns (uint256) {
        require(verifiedAppraisers[msg.sender], "NexusProp: Not an appraiser");
        require(pricePerShareWei > 0 && totalShares > 0, "NexusProp: Invalid parameters");

        propertyCounter++;
        properties[propertyCounter] = Property({
            seller: payable(msg.sender),
            pricePerShareWei: pricePerShareWei,
            totalShares: totalShares,
            availableShares: totalShares,
            isActive: true,
            isFrozen: false,
            propertyHash: propertyHash
        });

        emit PropertyListed(propertyCounter, msg.sender, totalShares);
        return propertyCounter;
    }

    // 12. revokeAppraiserStatus
    function revokeAppraiserStatus(address appraiser) external onlyAdmin {
        require(verifiedAppraisers[appraiser], "NexusProp: Not an appraiser");
        require(appraiser != msg.sender, "NexusProp: Cannot revoke self");
        verifiedAppraisers[appraiser] = false;
        emit AppraiserRevoked(appraiser);
    }

    // 13. updateHubDescriptor
    function updateHubDescriptor(string calldata newDescriptor) external onlyAdmin {
        require(bytes(newDescriptor).length > 0, "NexusProp: Empty string");
        hubDescriptor = newDescriptor;
        emit DescriptorUpdated(newDescriptor);
    }

    // 14. withdrawRefunds
    function withdrawRefunds() external {
        uint256 amount = pendingRefunds[msg.sender];
        require(amount > 0, "NexusProp: No refunds pending");

        pendingRefunds[msg.sender] = 0;
        (bool sent, ) = payable(msg.sender).call{value: amount}("");
        require(sent, "NexusProp: Refund transfer failed");

        emit RefundWithdrawn(msg.sender, amount);
    }
}