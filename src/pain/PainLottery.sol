// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IPainLottery} from "./interfaces/IPainLottery.sol";

interface IWETH9 {
    /// @notice Deposit ether to get wrapped ether
    function deposit() external payable;

    /// @notice Withdraw wrapped ether to get ether
    function withdraw(uint256) external;
}

interface ISwapRouter02 {
    // there is no deadline in the swap params for SwapRouter02
    struct ExactOutputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountOut;
        uint256 amountInMaximum;
        uint160 sqrtPriceLimitX96;
    }

    function exactOutputSingle(ExactOutputSingleParams calldata params) external payable returns (uint256 amountIn);
}

contract PainLottery is Ownable, IPainLottery {
    using SafeERC20 for IERC20;

    // Uniswap SwapRouter02 deployed on Base
    ISwapRouter02 private constant _BASE_SWAP_ROUTER_02 = ISwapRouter02(0x2626664c2603336E57B271c5C0b26F421741e481);

    address private constant _BASE_WETH9 = 0x4200000000000000000000000000000000000006;
    uint256 private constant _BASIS_POINTS = 10_000;
    uint256 private constant _LOTTERY_PRIZE_EXPIRY = 7 days;

    /// @dev e.g. 1000 means 10% of the lottery fee will be used for daily lottery, the rest 90% will be for weekly lottery
    uint256 private _dailyLotteryFeeBP;

    mapping(uint256 lotteryId => Lottery lottery) private _lotterysInfoById;
    mapping(LotteryInterval interval => uint256 poolETHAmount) private _lotteryPoolsByInterval;
    mapping(address user => mapping(uint256 lotteryId => bool claimed)) private _usersLotteryClaimed;

    // to receive remaining ETH after swap via swapFeeToPrizeAndSettleLottery
    receive() external payable {}

    constructor(uint256 dailyLotteryFeeBP) Ownable(msg.sender) {
        _dailyLotteryFeeBP = dailyLotteryFeeBP;
    }

    function claimLotteryPrize(LotteryClaim calldata claim) external {
        Lottery memory lottery = _lotterysInfoById[claim.lotteryId];

        _checkValidClaim(msg.sender, lottery, claim);

        address claimer = msg.sender;
        _usersLotteryClaimed[claimer][claim.lotteryId] = true;
        IERC20(lottery.prizeToken).safeTransfer(claimer, claim.prizeAmount);
        if (claim.bonusAmount > 0) {
            IERC20(lottery.bonusPrizeToken).safeTransfer(claimer, claim.bonusAmount);
        }

        emit LotteryClaimed(claimer, claim.lotteryId, block.timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                               INTERNALS
    //////////////////////////////////////////////////////////////*/
    function _checkValidClaim(address user, Lottery memory lottery, LotteryClaim calldata claim) internal view {
        if (lottery.prizeToken == address(0)) revert NonExistentLottery();
        if (claim.prizeAmount == 0) revert InvalidPrizeAmount();
        if (_usersLotteryClaimed[user][claim.lotteryId]) revert AlreadyClaimed();
        if (!_verifyProof(user, lottery, claim)) revert InvalidProof();
    }

    function _verifyProof(address user, Lottery memory lottery, LotteryClaim calldata claim)
        internal
        pure
        returns (bool)
    {
        return MerkleProof.verifyCalldata(
            claim.proof,
            lottery.merkleRoot,
            keccak256(bytes.concat(keccak256(abi.encode(user, claim.lotteryId, claim.prizeAmount, claim.bonusAmount))))
        );
    }

    function _checkValidSetup(LotteryConfig calldata config) internal view {
        // various checks e.g. zero amount, invalid merkle proof, whether lottery pool balance is enough for swap etc
        if (
            config.prizeToken == address(0) || config.drawnAt == 0 || config.totalPrizeAmount == 0
                || config.swapParams.poolFee == 0 || config.merkleRoot.length == 0
                || _lotteryPoolsByInterval[config.interval]
                    < config.swapParams.amountInMaximumForPrize + config.swapParams.amountInMaximumForBonus
                || config.totalPrizeAmount
                    != config.swapParams.exactAmountOutForPrize + config.swapParams.exactAmountOutForBonus
        ) revert InvalidSetup();
    }

    function _exactOutSwap(address tokenOut, uint24 poolFee, uint256 exactAmountOut, uint256 amountInMaximum)
        internal
        returns (uint256 amountIn)
    {
        // swap via Uniswap SwapRouter
        ISwapRouter02.ExactOutputSingleParams memory params = ISwapRouter02.ExactOutputSingleParams({
            tokenIn: _BASE_WETH9,
            tokenOut: tokenOut,
            fee: poolFee,
            recipient: address(this),
            amountOut: exactAmountOut,
            amountInMaximum: amountInMaximum,
            sqrtPriceLimitX96: 0 // 0 slippage
        });

        // wrap ETH to WETH
        IWETH9(_BASE_WETH9).deposit{value: amountInMaximum}();
        // approve the _BASE_SWAP_ROUTER_02 to spend WETH
        IERC20(_BASE_WETH9).approve(address(_BASE_SWAP_ROUTER_02), amountInMaximum);

        // Executes the swap returning the amountIn needed to spend to receive the desired amountOut.
        amountIn = _BASE_SWAP_ROUTER_02.exactOutputSingle(params);

        // For exact output swaps, the amountInMaximum may not have all been spent.
        // If the actual amount spent (amountIn) is less than the specified maximum amount, we should withdraw the unused WETH back and approve the swapRouter to spend 0
        if (amountIn < amountInMaximum) {
            IERC20(_BASE_WETH9).approve(address(_BASE_SWAP_ROUTER_02), 0);
            IWETH9(_BASE_WETH9).withdraw(amountInMaximum - amountIn);
        }
    }

    /*//////////////////////////////////////////////////////////////
                                 ADMIN
    //////////////////////////////////////////////////////////////*/
    /// @dev Should be called by admin daily/weekly for each lottery result
    /// @dev `amountInMaximum` should be calculated using SDK or an onchain price oracle to protect against front running sandwich or price manipulation
    function swapFeeToPrizeAndSettleLottery(LotteryConfig calldata config) external onlyOwner {
        if (_lotterysInfoById[config.lotteryId].prizeToken != address(0)) revert LotteryIdAlreadyUsed();
        _checkValidSetup(config);

        Lottery memory lottery = Lottery({
            prizeToken: config.prizeToken,
            bonusPrizeToken: config.bonusPrizeToken,
            interval: config.interval,
            drawnAt: config.drawnAt,
            totalPrizeAmount: config.totalPrizeAmount,
            merkleRoot: config.merkleRoot
        });
        _lotterysInfoById[config.lotteryId] = lottery;
        SwapParams calldata swapParams = config.swapParams;

        uint256 totalAmountUsed = _exactOutSwap(
            config.prizeToken, swapParams.poolFee, swapParams.exactAmountOutForPrize, swapParams.amountInMaximumForPrize
        );

        // if there is a bonus prize for the lottery
        if (config.bonusPrizeToken != address(0)) {
            uint256 amountUsedForBonus = _exactOutSwap(
                config.bonusPrizeToken,
                swapParams.poolFee,
                swapParams.exactAmountOutForBonus,
                swapParams.amountInMaximumForBonus
            );
            totalAmountUsed += amountUsedForBonus;
        }

        // deduct the totalAmountUsed from the respective lottery pool balance
        _lotteryPoolsByInterval[config.interval] -= totalAmountUsed;

        uint256 totalTokenBalance = IERC20(config.prizeToken).balanceOf(address(this));
        if (config.bonusPrizeToken != address(0)) {
            totalTokenBalance += IERC20(config.bonusPrizeToken).balanceOf(address(this));
        }

        // ensure swapped balanceOf prizeToken + bonusPrizeToken >= totalPrizeAmount
        if (totalTokenBalance < config.totalPrizeAmount) revert SwapAmountOutNotEnoughForLottery();

        emit SwappedAndSettledLotteryResult(config.lotteryId, totalAmountUsed, block.timestamp);
    }

    function withdrawExpiredPrize(uint256 lotteryId) external onlyOwner {
        Lottery memory lottery = _lotterysInfoById[lotteryId];
        // check if prize is indeed expired
        if (block.timestamp < lottery.drawnAt + _LOTTERY_PRIZE_EXPIRY) revert PrizeNotExpired();

        // since anyone could send ERC20 token to this contract, we want to withdraw all of them as well
        uint256 tokenBalance = IERC20(lottery.prizeToken).balanceOf(address(this));
        IERC20(lottery.prizeToken).safeTransfer(msg.sender, tokenBalance);
    }

    function setDailyLotteryFeeBP(uint256 newDailyLotteryFeeBP) external onlyOwner {
        if (newDailyLotteryFeeBP >= _BASIS_POINTS) revert InvalidFeeBP();
        _dailyLotteryFeeBP = newDailyLotteryFeeBP;
    }

    // called by Pain to receive lottery fee
    function receiveLotteryFee() external payable {
        if (msg.value == 0) revert ZeroAmount();

        uint256 dailyLotteryFee = msg.value * _dailyLotteryFeeBP / _BASIS_POINTS;
        uint256 weeklyLotteryFee = msg.value - dailyLotteryFee;

        _lotteryPoolsByInterval[LotteryInterval.DAILY] += dailyLotteryFee;
        _lotteryPoolsByInterval[LotteryInterval.WEEKLY] += weeklyLotteryFee;
    }

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/
    /// @notice Get the information of respective lottery by its id
    function getLotteryInfo(uint256 lotteryId) external view returns (Lottery memory) {
        return _lotterysInfoById[lotteryId];
    }

    /// @notice Get the ETH balance of respective lottery pool
    function getLotteryPoolByInterval(LotteryInterval interval) external view returns (uint256) {
        return (_lotteryPoolsByInterval[interval]);
    }

    /// @notice Get the percentage of fee allocated for daily lottery in Basis Points
    function getDailyLotteryFeeBP() external view returns (uint256) {
        return _dailyLotteryFeeBP;
    }

    /// @notice Get the percentage of fee allocated for weekly lottery in Basis Points
    function getWeeklyLotteryFeeBP() external view returns (uint256) {
        return _BASIS_POINTS - _dailyLotteryFeeBP;
    }
}
