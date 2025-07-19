// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IPainLottery} from "src/pain/interfaces/IPainLottery.sol";
import {PainTestSetup} from "./setup/PainTestSetup.t.sol";
import "./setup/PainTestConfig.t.sol";

contract PainLotteryTest is PainTestSetup {
    function test_InitialStates() public view {
        assertEq(painLottery.getDailyLotteryFeeBP(), DAILY_LOTTERY_FEE_BP);
        assertEq(painLottery.getWeeklyLotteryFeeBP(), BASIS_POINTS - DAILY_LOTTERY_FEE_BP);
    }

    function test_swapFeeToPrizeAndSettleLottery_SinglePrize_SwapToMemeAndGetExactOutput() public {
        vm.createSelectFork(vm.rpcUrl("base"));
        painLottery.receiveLotteryFee{value: 100 ether}();

        uint256 totalPrizeAmount = 1000 ether;
        IPainLottery.LotteryConfig memory config = IPainLottery.LotteryConfig({
            lotteryId: 1,
            prizeToken: BASE_GHST,
            bonusPrizeToken: address(0),
            interval: IPainLottery.LotteryInterval.DAILY,
            drawnAt: uint40(block.timestamp),
            totalPrizeAmount: totalPrizeAmount,
            swapParams: IPainLottery.SwapParams({
                poolFee: 3000, // 0.3%
                exactAmountOutForPrize: totalPrizeAmount,
                exactAmountOutForBonus: 0,
                amountInMaximumForPrize: 0.4 ether,
                amountInMaximumForBonus: 0
            }),
            merkleRoot: bytes32("testing")
        });

        uint256 beforeSwapETHBalance = address(painLottery).balance;
        painLottery.swapFeeToPrizeAndSettleLottery(config);
        uint256 afterSwapETHBalance = address(painLottery).balance;

        assertEq(IERC20(BASE_GHST).balanceOf(address(painLottery)), totalPrizeAmount);
        // should use less that 0.4 ETH for 1000 $GHST
        assertLt(beforeSwapETHBalance - afterSwapETHBalance, 0.4 ether);
    }
}
