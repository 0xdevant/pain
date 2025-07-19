// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IBancorBondingCurve {
    function calculatePurchaseReturn(
        uint256 _supply,
        uint256 _reserveBalance,
        uint256 _reserveRatioBP,
        uint256 _depositAmount
    ) external view returns (uint256);

    function calculateSaleReturn(uint256 _supply, uint256 _reserveBalance, uint256 _reserveRatioBP, uint256 _sellAmount)
        external
        view
        returns (uint256);
}
