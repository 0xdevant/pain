// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Vm} from "forge-std/Vm.sol";

import {IBancorBondingCurve} from "test/pain/interfaces/IBancorBondingCurve.sol";
import "../setup/PainTestConfig.t.sol";

library PainTestHelpers {
    using Strings for uint256;

    address internal constant VM_ADDRESS = address(uint160(uint256(keccak256("hevm cheat code"))));
    Vm internal constant vm = Vm(VM_ADDRESS);

    function initialProtocolFeeMinusLotteryFee() public pure returns (uint256) {
        return INITIAL_PURCHASE_ETH * PROTOCOL_FEE_BP / BASIS_POINTS - initialLotteryFee();
    }

    function initialLotteryFee() public pure returns (uint256) {
        return INITIAL_PURCHASE_ETH * PROTOCOL_FEE_BP * LOTTERY_FEE_BP / BASIS_POINTS / BASIS_POINTS;
    }

    function calculatePrincipalPlusFee(uint256 buyOrReturnAmount) public pure returns (uint256) {
        return buyOrReturnAmount + buyOrReturnAmount * PROTOCOL_FEE_BP / BASIS_POINTS;
    }

    function calculateProtocolFee(uint256 buyOrReturnAmount) public pure returns (uint256) {
        return buyOrReturnAmount * PROTOCOL_FEE_BP / BASIS_POINTS;
    }

    function calculateProtocolFeeMinusLotteryFee(uint256 buyOrReturnAmount) public pure returns (uint256) {
        return buyOrReturnAmount * PROTOCOL_FEE_BP / BASIS_POINTS - calculateLotteryFee(buyOrReturnAmount);
    }

    function calculateProtocolFee(uint256 buyOrReturnAmount, uint256 protocolFeeBP) public pure returns (uint256) {
        return buyOrReturnAmount * protocolFeeBP / BASIS_POINTS;
    }

    function calculateProtocolFeeMinusLotteryFee(uint256 buyOrReturnAmount, uint256 protocolFeeBP)
        public
        pure
        returns (uint256)
    {
        return
            buyOrReturnAmount * PROTOCOL_FEE_BP / BASIS_POINTS - calculateLotteryFee(buyOrReturnAmount, protocolFeeBP);
    }

    function calculateLotteryFee(uint256 buyOrReturnAmount) public pure returns (uint256) {
        return calculateProtocolFee(buyOrReturnAmount) * LOTTERY_FEE_BP / BASIS_POINTS;
    }

    function calculateLotteryFee(uint256 buyOrReturnAmount, uint256 protocolFeeBP) public pure returns (uint256) {
        return calculateProtocolFee(buyOrReturnAmount, protocolFeeBP) * LOTTERY_FEE_BP / BASIS_POINTS;
    }

    function calculateBuyReturns(
        IBancorBondingCurve bondingCurve,
        uint256 currentTokenPurchased,
        uint256 currentPoolBalance,
        uint256 depositAmount
    ) public view returns (uint256) {
        return bondingCurve.calculatePurchaseReturn(
            currentTokenPurchased + MAX_SUPPLY,
            currentPoolBalance + VIRTUAL_ETH_RESERVE,
            RESERVE_RATIO_BP,
            depositAmount
        );
    }

    function calculateSellReturns(
        IBancorBondingCurve bondingCurve,
        uint256 supply,
        uint256 currentPoolBalance,
        uint256 depositAmount
    ) public view returns (uint256) {
        return bondingCurve.calculateSaleReturn(
            supply + MAX_SUPPLY, currentPoolBalance + VIRTUAL_ETH_RESERVE, RESERVE_RATIO_BP, depositAmount
        );
    }

    function signTokenDeploymentMessage(
        address user,
        uint256 tokenId,
        string memory name,
        string memory symbol,
        bool isDonating
    ) public pure returns (bytes memory signature) {
        string memory action = string.concat(
            "deploy-new-token_id-",
            tokenId.toString(),
            "_name-",
            name,
            "_symbol-",
            symbol,
            "_isDonating-",
            isDonating ? "true" : "false"
        );

        bytes32 digest = MessageHashUtils.toEthSignedMessageHash(keccak256(abi.encodePacked(user, action)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_PRIVATE_KEY, digest);
        return abi.encodePacked(r, s, v); // the order here is different from above
    }
}
