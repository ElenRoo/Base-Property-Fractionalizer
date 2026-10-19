// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;
interface INexusPropertyFractionalizer {
    function buyPropertyShares(uint256 propertyId, uint256 sharesToBuy) external payable;
    function joinInvestorWhitelist() external;
}
