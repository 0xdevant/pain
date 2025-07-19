// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IPainLottery {
    enum LotteryInterval {
        DAILY,
        WEEKLY
    }

    /// @param prizeToken the token address for the lottery prize
    /// @param bonusPrizeToken the token address for the lottery bonus prize if there is any
    /// @param interval enum of `LotteryInterval`, represents how frequently the lottery is drawn
    /// @param drawnAt the timestamp when the lottery is drawn
    /// @param totalPrizeAmount the total amount of prize for the lottery, to be checked against the actual total amount swapped out
    /// @param merkleRoot the merkle root of the merkle tree used to verify the lottery winners
    struct Lottery {
        address prizeToken;
        address bonusPrizeToken;
        LotteryInterval interval;
        uint40 drawnAt;
        uint256 totalPrizeAmount;
        bytes32 merkleRoot;
    }

    struct LotteryClaim {
        uint256 lotteryId;
        LotteryInterval interval;
        uint256 prizeAmount;
        uint256 bonusAmount;
        bytes32[] proof;
    }

    struct LotteryConfig {
        uint256 lotteryId;
        address prizeToken;
        address bonusPrizeToken;
        LotteryInterval interval;
        uint40 drawnAt;
        uint256 totalPrizeAmount;
        SwapParams swapParams;
        bytes32 merkleRoot;
    }

    /// @param poolFee fee tier chosen for the Uniswap pool to swap, e.g. 3000 means 0.3% pool
    /// @param exactAmountOutForPrize the exact amount of token needed for the lottery prize
    /// @param exactAmountOutForBonus the exact amount of token needed for the lottery bonus prize if there is any
    /// @param amountInMaximumForPrize the maximum amount of token we will use to swap for the `exactAmountOutForPrize`
    /// @param amountInMaximumForBonus the maximum amount of token we will use to swap for the `exactAmountOutForBonus`
    struct SwapParams {
        uint24 poolFee;
        uint256 exactAmountOutForPrize;
        uint256 exactAmountOutForBonus;
        uint256 amountInMaximumForPrize;
        uint256 amountInMaximumForBonus;
    }

    /// @dev Emitted when a user claimed the lottery prize
    event LotteryClaimed(address indexed claimer, uint256 lotteryId, uint256 claimedAt);
    /// @dev Emitted when the admin settled the lottery result and swapped the collected fees into lottery prize
    event SwappedAndSettledLotteryResult(
        uint256 indexed lotteryId, uint256 totalAmountUsedForSwap, uint256 swappedAndSettledAt
    );

    error InvalidSetup();
    error InvalidPrizeAmount();
    error InvalidProof();
    error InvalidFeeBP();
    error ZeroAmount();
    error NonExistentLottery();
    error AlreadyClaimed();
    error LotteryIdAlreadyUsed();
    error PrizeNotExpired();
    error EtherTransferFailed();
    error SwapAmountOutNotEnoughForLottery();

    function swapFeeToPrizeAndSettleLottery(LotteryConfig calldata config) external;
    function withdrawExpiredPrize(uint256 lotteryId) external;
    function setDailyLotteryFeeBP(uint256 newDailyLotteryFeeBP) external;

    function receiveLotteryFee() external payable;

    function getLotteryInfo(uint256 lotteryId) external view returns (Lottery memory);
    function getLotteryPoolByInterval(LotteryInterval interval) external view returns (uint256);
    function getDailyLotteryFeeBP() external view returns (uint256);
    function getWeeklyLotteryFeeBP() external view returns (uint256);
}
