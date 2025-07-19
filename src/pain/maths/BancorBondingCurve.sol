// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Power} from "./Power.sol";

contract BancorBondingCurve is Power {
    error InvalidInput();

    uint256 public constant MAX_RESERVE_RATIO_BP = 10_000; // 100%

    /**
     * @dev given a continuous token supply, reserve token balance, reserve ratio, and a deposit amount (in the reserve token),
     * calculates the return for a given conversion (in the continuous token)
     *
     * Formula:
     * Return = _supply * ((1 + _depositAmount / _reserveBalance) ^ _reserveRatio - 1)
     *
     * @param _supply              continuous token total supply
     * @param _reserveBalance    total reserve token balance
     * @param _reserveRatioBP     reserve ratioBP, represented in BP, 1-10000
     * @param _depositAmount       deposit amount, in reserve token
     *
     *  @return purchase return amount
     */
    function calculatePurchaseReturn(
        uint256 _supply,
        uint256 _reserveBalance,
        uint256 _reserveRatioBP,
        uint256 _depositAmount
    ) public view returns (uint256) {
        // validate input
        if (_supply == 0 || _reserveBalance == 0 || _reserveRatioBP == 0 || _reserveRatioBP > MAX_RESERVE_RATIO_BP) {
            revert InvalidInput();
        }

        // special case if the ratio = 100%
        if (_reserveRatioBP == MAX_RESERVE_RATIO_BP) {
            return _supply * _depositAmount / _reserveBalance;
        }
        uint256 result;
        uint8 precision;
        uint256 baseN = _depositAmount + _reserveBalance;
        (result, precision) = power(baseN, _reserveBalance, uint32(_reserveRatioBP), uint32(MAX_RESERVE_RATIO_BP));
        uint256 newTokenSupply = (_supply * result) >> precision;
        return newTokenSupply - _supply;
    }

    /**
     * @dev given a continuous token supply, reserve token balance, reserve ratio and a sell amount (in the continuous token),
     * calculates the return for a given conversion (in the reserve token)
     *
     * Formula:
     * Return = _reserveBalance * (1 - (1 - _sellAmount / _supply) ^ (1 / _reserveRatio)))
     *
     * @param _supply              continuous token total supply
     * @param _reserveBalance    total reserve token balance
     * @param _reserveRatioBP     constant reserve ratio, represented in BP, 1 - 10000
     * @param _sellAmount          sell amount, in the continuous token itself
     *
     * @return sale return amount
     */
    function calculateSaleReturn(uint256 _supply, uint256 _reserveBalance, uint256 _reserveRatioBP, uint256 _sellAmount)
        public
        view
        returns (uint256)
    {
        // validate input
        if (
            _supply == 0 || _reserveBalance == 0 || _reserveRatioBP == 0 || _reserveRatioBP > MAX_RESERVE_RATIO_BP
                || _sellAmount > _supply
        ) revert InvalidInput();

        // special case for selling the entire supply
        if (_sellAmount == _supply) {
            return _reserveBalance;
        }
        // special case if the ratio = 100%
        if (_reserveRatioBP == MAX_RESERVE_RATIO_BP) {
            return _reserveBalance * _sellAmount / _supply;
        }
        uint256 result;
        uint8 precision;
        uint256 baseD = _supply - _sellAmount;
        (result, precision) = power(_supply, baseD, uint32(MAX_RESERVE_RATIO_BP), uint32(_reserveRatioBP));
        uint256 oldBalance = _reserveBalance * result;
        uint256 newBalance = _reserveBalance << precision;
        return (oldBalance - newBalance) / (result);
    }
}
