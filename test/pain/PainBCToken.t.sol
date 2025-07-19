// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {console} from "forge-std/Test.sol";

import {IPainBCToken} from "src/pain/interfaces/IPainBCToken.sol";

import {PainTestSetup} from "./setup/PainTestSetup.t.sol";
import {PainTestHelpers} from "./utils/PainTestHelpers.t.sol";
import "./setup/PainTestConfig.t.sol";

contract PainBCTokenTest is PainTestSetup {
    using PainTestHelpers for *;

    function test_InitialStates_AfterDeployedTestToken() public view {
        assertEq(testPainToken.getPoolBalance(), INITIAL_PURCHASE_ETH);
        assertEq(testPainToken.getCurrentTokenPurchased(), INITIAL_MINT_AMOUNT);
        assertEq(testPainToken.balanceOf(address(this)), INITIAL_MINT_AMOUNT);
        assertEq(testPainToken.totalSupply(), MAX_SUPPLY);
        assertTrue(testPainToken.isTokenDonating());

        console.log("getCurrentTokenPurchased", testPainToken.getCurrentTokenPurchased());
        console.log("getPoolBalance", testPainToken.getPoolBalance());
    }

    function test_buy_MintCorrectAmount_AppliedFeeCut() public {
        buyExactAmount(users["alice"], 1 ether, 0, MIN_TOKEN_BOUGHT);
    }

    function test_buy_WithoutExactAmount() public {
        buyExactAmount(users["alice"], 0.008 ether, 0, MIN_TOKEN_BOUGHT);
    }

    function test_buy_WithExactAmount() public {
        // buyExactAmount(users["alice"], 0.008 ether, 3000, MIN_TOKEN_BOUGHT);
    }

    function test_sell_DeployerBurntCorrectAmount_AppliedFeeCut() public {
        console.log("initPurchasedAmount: ", INITIAL_MINT_AMOUNT);
        uint256 sellAmount = INITIAL_MINT_AMOUNT;
        sellExactAmount(address(this), sellAmount, MIN_ETH_RETURNED);
    }

    function test_buyAndSell_UserCanBuyAndSellToken() public {
        uint256 buyAmount = 0.008 ether;
        uint256 sellAmount = 0.005 ether;
        address user = users["alice"];
        console.log(testPainToken.balanceOf(user));

        buyExactAmount(user, buyAmount, 0, MIN_TOKEN_BOUGHT);
        sellExactAmount(user, sellAmount, MIN_ETH_RETURNED);
    }

    function test_buyAndSell_UserCanBuyAndSellSpecifiedTokenAmount() public {}

    function test_buy_EnoughToLPPromotion_NewPoolCreatedWithAllLiquidityAdded_DonationReceiverReceivedPartOfETH()
        public
    {
        vm.createSelectFork(vm.rpcUrl("base"));

        painTokenToNearlyPromotionThreshold();

        uint256 beforePoolBalanceForToken = testPainToken.getPoolBalance();
        console.log("MC: ", testPainToken.getTokenMarketCap() / DEFAULT_DECIMALS_PRECISIONS);
        console.log("Total Supply: ", testPainToken.totalSupply());
        console.log("\n");
        console.log("Pool Balance: ", beforePoolBalanceForToken);
        console.log("Token Balance: ", testPainToken.balanceOf(address(testPainToken)));
        console.log("ETH Balance: ", address(testPainToken).balance);
        console.log("B4 Pain Token Balance: ", testPainToken.balanceOf(address(pain)));
        console.log("B4 Pain ETH Balance: ", address(pain).balance);

        // trigger promotion to LP after buying
        uint256 etherAmount = 0.2 ether;
        uint256 etherAfterFee = etherAmount - etherAmount.calculateProtocolFee();

        vm.prank(users["alice"]);
        testPainToken.buy{value: etherAmount}(0, MIN_TOKEN_BOUGHT);

        assertEq(testPainToken.isTokenProtmoted(), true);
        assertEq(testPainToken.getPoolBalance(), 0);
        assertEq(testPainToken.balanceOf(address(testPainToken)), 0);
        assertEq(address(testPainToken).balance, 0);
        assertEq(
            address(DONATION_RECEIVER).balance,
            (beforePoolBalanceForToken + etherAfterFee) * (DONATION_BP * 2) / BASIS_POINTS
        );

        console.log("\n");
        console.log("Token Balance: ", testPainToken.balanceOf(address(testPainToken)));
        console.log("ETH Balance: ", address(testPainToken).balance);
        console.log("Pain Token Balance: ", testPainToken.balanceOf(address(pain)));
        console.log("Pain ETH Balance: ", address(pain).balance);
    }

    function test_buyOrSell_RevertWhenBondingCurveIsCompleted() public {
        vm.createSelectFork(vm.rpcUrl("base"));

        painTokenToNearlyPromotionThreshold();
        // trigger promotion to LP after buying
        uint256 etherAmount = 0.2 ether;
        uint256 tokenAmount = 10000 ether;
        vm.prank(users["alice"]);
        testPainToken.buy{value: etherAmount}(0, MIN_TOKEN_BOUGHT);

        vm.expectRevert(IPainBCToken.BondingCurveAlreadyEnded.selector);
        vm.prank(users["bob"]);
        testPainToken.buy{value: etherAmount}(0, MIN_TOKEN_BOUGHT);

        vm.expectRevert(IPainBCToken.BondingCurveAlreadyEnded.selector);
        vm.prank(users["bob"]);
        testPainToken.sell(tokenAmount, MIN_ETH_RETURNED);
    }

    // function testInternal_buy_SimulateTokenPriceOnDEX_WhenTriggerLPPromotion() public {
    //     // vm.createSelectFork(vm.rpcUrl("base"));

    //     painTokenToNearlyPromotionThreshold();
    //     uint256 etherAmount = 0.1 ether;

    //     vm.prank(users["alice"]);
    //     testPainToken.buy{value: etherAmount}(0, MIN_TOKEN_BOUGHT);

    //     console.log("\n");
    //     console.log("MC: ", testPainToken.getTokenMarketCap() / DEFAULT_DECIMALS_PRECISIONS);
    //     console.log("Token Balance: ", testPainToken.balanceOf(address(testPainToken)));
    //     console.log("Token poolBalance: ", testPainToken.getPoolBalance());
    //     console.log("Token getCurrentPurchased: ", testPainToken.getCurrentTokenPurchased());
    //     console.log("Token is promoted: ", testPainToken.isTokenProtmoted());
    // }

    // function testInternal_newFunctions() public {
    //     console.log("getBuyReturnByExactETH of 1 ETH", testPainToken.getBuyReturnByExactETH(1 ether));
    //     console.log("weiAmountPerTokenE18", testPainToken.getETHNeededByOneTokenWithPrecision());
    //     console.log("getETHNeededByExactToken", testPainToken.getETHNeededByExactToken(577051422097662458478890958));
    // }
}
