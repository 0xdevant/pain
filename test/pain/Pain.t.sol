// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IPain} from "src/pain/interfaces/IPain.sol";
import {PainTestSetup} from "./setup/PainTestSetup.t.sol";
import {IERC20PainToken} from "test/pain/interfaces/IERC20PainToken.sol";
import {PainTestHelpers} from "./utils/PainTestHelpers.t.sol";
import "./setup/PainTestConfig.t.sol";

contract PainTest is PainTestSetup {
    function test_InitialStates() public view {
        assertEq(pain.getReserveRatioBP(), RESERVE_RATIO_BP);
        assertEq(pain.getProtocolFeeBP(), PROTOCOL_FEE_BP);
        assertEq(pain.getLotteryFeeBP(), LOTTERY_FEE_BP);
        assertEq(pain.getBuyBackBP(), BUY_BACK_BP);
        assertEq(pain.getDonationBP(), DONATION_BP);
    }

    function test_deployTokenAsClone_DeployedWithCorrectImpl_TriggerInitialMintViaBC() public {
        uint256 tokenId = 1;
        address predictedToken =
            pain.predictCreate2AddressForToken(users["alice"], tokenId, DEFAULT_TOKEN_NAME, DEFAULT_TOKEN_SYMBOL);
        bytes memory sig = PainTestHelpers.signTokenDeploymentMessage(
            users["alice"], 1, DEFAULT_TOKEN_NAME, DEFAULT_TOKEN_SYMBOL, true
        );

        vm.prank(users["alice"]);
        vm.expectEmit(address(pain));
        emit IPain.NewTokenDeployed(
            users["alice"], predictedToken, tokenId, DEFAULT_TOKEN_NAME, DEFAULT_TOKEN_SYMBOL, true, block.timestamp
        );
        address painToken = pain.deployTokenAsClone{value: INITIAL_PURCHASE_ETH + INITIAL_PROTOCOL_FEE}(
            tokenId, DEFAULT_TOKEN_NAME, DEFAULT_TOKEN_SYMBOL, true, sig
        );

        IERC20PainToken newToken = IERC20PainToken(painToken);
        assertEq(predictedToken, painToken);
        assertEq(newToken.name(), DEFAULT_TOKEN_NAME);
        assertEq(newToken.symbol(), DEFAULT_TOKEN_SYMBOL);
        assertEq(newToken.getPoolBalance(), INITIAL_PURCHASE_ETH);
        assertEq(newToken.balanceOf(users["alice"]), INITIAL_MINT_AMOUNT);

        assertEq(address(pain).balance, INITIAL_PAIN_BALANCE + PainTestHelpers.initialProtocolFeeMinusLotteryFee());
        assertEq(address(painLottery).balance, INITIAL_LOTTERY_BALANCE + PainTestHelpers.initialLotteryFee());

        // vm.prank(users["bob"]);
        // address painToken2 =
        //     pain.deployTokenAsClone{value: INITIAL_PURCHASE_ETH + protocolFee}("What The fk token", "WTF");
        // IERC20PainToken newToken2 = IERC20PainToken(painToken2);
        // assertEq(IERC20PainToken(newToken2).name(), "What The fk token");
        // assertEq(IERC20PainToken(newToken2).symbol(), "WTF");
        // assertEq(IERC20PainToken(newToken2).totalSupply(), INITIAL_SUPPLY_AND_POOL_BALANCE);
    }

    function test_buyBackAndBurn_AfterCollectedFee() public {
        address buyBackToken = BASE_GHST;
        uint256 amountOutMin = 2000 ether;
        uint256 totalFeeCollected = 10 ether;

        vm.createSelectFork(vm.rpcUrl("base"));
        deal(address(pain), totalFeeCollected);

        uint256 collectedFeeForBuyBack = totalFeeCollected * BUY_BACK_BP / BASIS_POINTS;

        uint256 beforeSwapETHBalance = address(pain).balance;
        console.log("beforeSwapETHBalance: ", beforeSwapETHBalance);

        // vm.expectEmit(address(pain));
        // emit IPain.BoughtBackAndBurnt(buyBackToken, collectedFeeForBuyBack, 0, block.timestamp);
        // emit IERC20.Transfer(address(pain), address(0), tokenBoughtBack);
        pain.buyBackAndBurn(buyBackToken, 3000, amountOutMin);
        uint256 afterSwapETHBalance = address(pain).balance;
        console.log("afterSwapETHBalance: ", afterSwapETHBalance);

        assertEq(beforeSwapETHBalance - afterSwapETHBalance, collectedFeeForBuyBack);
        // should have burnt all GHST bought back
        assertEq(IERC20(buyBackToken).balanceOf(address(pain)), 0);
    }
}
