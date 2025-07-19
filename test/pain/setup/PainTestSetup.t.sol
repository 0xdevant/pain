// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {PainLottery} from "src/pain/PainLottery.sol";
import {Pain} from "src/pain/Pain.sol";
import {PainBCToken} from "src/pain/PainBCToken.sol";
import {BancorBondingCurve} from "src/pain/maths/BancorBondingCurve.sol";

import {IERC20PainToken} from "test/pain/interfaces/IERC20PainToken.sol";
import {IBancorBondingCurve} from "test/pain/interfaces/IBancorBondingCurve.sol";
import {PainTestHelpers} from "../utils/PainTestHelpers.t.sol";
import "./PainTestConfig.t.sol";

contract PainTestSetup is Test {
    using PainTestHelpers for *;

    mapping(string userName => address) users;

    PainLottery public painLottery;
    Pain public pain;
    Pain public painImpl;
    PainBCToken public painTokenImpl;
    BancorBondingCurve public bondingCurve = new BancorBondingCurve();
    IBancorBondingCurve public iBondingCurve = IBancorBondingCurve(address(bondingCurve));

    IERC20PainToken public testPainToken;

    address public SIGNER;

    // after deployTestBCToken()
    uint256 INITIAL_PAIN_BALANCE = PainTestHelpers.initialProtocolFeeMinusLotteryFee();
    uint256 INITIAL_LOTTERY_BALANCE = PainTestHelpers.initialLotteryFee();
    uint256 INITIAL_MINT_AMOUNT = bondingCurve.calculatePurchaseReturn(
        MAX_SUPPLY, VIRTUAL_ETH_RESERVE, uint32(RESERVE_RATIO_BP), INITIAL_PURCHASE_ETH
    );

    // to receive ETH back when test on selling token
    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                            SETUP 
    //////////////////////////////////////////////////////////////*/
    function setUp() public {
        setUpUsersWithFunds();
        deployContracts();
        deployTestBCToken();
        labelContracts();
        makeContractsPersistent();
    }

    /*//////////////////////////////////////////////////////////////
                        SETUP FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function setUpUsersWithFunds() public {
        string[3] memory names = ["alice", "bob", "cat"];

        for (uint256 i; i < names.length; i++) {
            users[names[i]] = makeAddr(names[i]);
            deal(users[names[i]], INITIAL_FUNDS);
        }

        SIGNER = vm.addr(SIGNER_PRIVATE_KEY);
        vm.label(address(SIGNER), "Signer");
    }

    function deployContracts() public {
        // deploy PainLottery contract
        painLottery = new PainLottery(DAILY_LOTTERY_FEE_BP);
        // deploy PainToken to act as an implementation contract for its minimal proxies before deploying Pain contract
        painTokenImpl = new PainBCToken();
        painImpl = new Pain();
        pain = Pain(
            address(
                new ERC1967Proxy(
                    address(painImpl),
                    abi.encodeCall(
                        Pain.initialize,
                        (
                            address(painLottery),
                            address(painTokenImpl),
                            UPGRADER,
                            SIGNER,
                            DONATION_RECEIVER,
                            RESERVE_RATIO_BP,
                            PROTOCOL_FEE_BP,
                            LOTTERY_FEE_BP,
                            BUY_BACK_BP,
                            DONATION_BP
                        )
                    )
                )
            )
        );
    }

    function deployTestBCToken() public {
        string memory tokenName = "Test Pain Token";
        string memory tokenSymbol = "TPT";

        address testBCToken = pain.deployTokenAsClone{value: INITIAL_PURCHASE_ETH + INITIAL_PROTOCOL_FEE}(
            0,
            tokenName,
            tokenSymbol,
            true,
            PainTestHelpers.signTokenDeploymentMessage(address(this), 0, tokenName, tokenSymbol, true)
        );

        testPainToken = IERC20PainToken(testBCToken);
    }

    function labelContracts() public {
        vm.label(address(pain), "Pain");
        vm.label(address(painLottery), "PainLottery");
        vm.label(address(testPainToken), "TestPainToken");
        vm.label(DONATION_RECEIVER, "DonationReceiver");
        vm.label(BASE_WETH, "Base_WETH");
        vm.label(BASE_UNISWAP_V3_ROUTER02, "Base_UniswapV3Router02");
        vm.label(BASE_NON_FUNGIBLE_POSITION_MANAGER, "Base_NonFungiblePositionManager");
    }

    function makeContractsPersistent() public {
        vm.makePersistent(users["alice"], users["bob"], users["cat"]);
        vm.makePersistent(DONATION_RECEIVER);

        vm.makePersistent(address(pain), address(painImpl), address(painTokenImpl));
        vm.makePersistent(address(testPainToken), address(painLottery));
    }

    /*//////////////////////////////////////////////////////////////
                            TEST UTILS
    //////////////////////////////////////////////////////////////*/
    // pain to ~20.1 ETH Market Cap when 4.32+0.09(next buy)+0.01(init buy) ETH purchased(after deducted 0.49 ETH fee)
    function painTokenToNearlyPromotionThreshold() public {
        uint256 etherAmount = 1.2 ether; // becomes 1.08 ETH after 0.12 ETH fee
        vm.prank(users["alice"]);
        testPainToken.buy{value: etherAmount}(0, MIN_TOKEN_BOUGHT);

        vm.prank(users["bob"]);
        testPainToken.buy{value: etherAmount}(0, MIN_TOKEN_BOUGHT);

        vm.prank(users["cat"]);
        testPainToken.buy{value: etherAmount}(0, MIN_TOKEN_BOUGHT);

        vm.prank(users["alice"]);
        testPainToken.buy{value: etherAmount}(0, MIN_TOKEN_BOUGHT);
    }

    function buyExactAmount(address user, uint256 etherAmount, uint256 buyAmount, uint256 minExpectedAmount)
        public
        returns (uint256 amountMinted)
    {
        uint256 etherAmountAfterFee = etherAmount - etherAmount.calculateProtocolFee();
        uint256 expectedMint = testPainToken.getBuyReturnByExactETH(etherAmountAfterFee);
        vm.prank(user);
        amountMinted = testPainToken.buy{value: etherAmount}(buyAmount, minExpectedAmount);

        // Balance of user
        assertEq(address(user).balance, INITIAL_FUNDS - etherAmount);
        assertEq(amountMinted, expectedMint);

        // Balance of contracts
        assertEq(address(testPainToken).balance, INITIAL_PURCHASE_ETH + etherAmountAfterFee);
        assertEq(address(pain).balance, INITIAL_PAIN_BALANCE + etherAmount.calculateProtocolFeeMinusLotteryFee());
        assertEq(address(painLottery).balance, INITIAL_LOTTERY_BALANCE + etherAmount.calculateLotteryFee());
    }

    function sellExactAmount(address user, uint256 sellAmount, uint256 minETHReturned)
        public
        returns (uint256 amountReturned)
    {
        uint256 expectedReturn = testPainToken.getSaleReturnByExactToken(sellAmount);
        console.log("expectedReturn: ", expectedReturn);
        uint256 beforeSellTokenBalance = testPainToken.balanceOf(user);
        uint256 beforeSellETHBalance = user.balance;
        uint256 painTokenBeforeSellETHBalance = address(testPainToken).balance;
        uint256 painBeforeSellETHBalance = address(pain).balance;
        uint256 painLotteryBeforeSellETHBalance = address(painLottery).balance;

        vm.prank(user);
        amountReturned = testPainToken.sell(sellAmount, minETHReturned);

        // Balance of User
        uint256 afterSellTokenBalance = testPainToken.balanceOf(user);
        uint256 afterSellETHBalance = user.balance;
        assertEq(afterSellTokenBalance, beforeSellTokenBalance - sellAmount);
        assertEq(afterSellETHBalance - beforeSellETHBalance, amountReturned - amountReturned.calculateProtocolFee());
        assertEq(amountReturned, expectedReturn);

        // Balance of contracts
        assertEq(address(testPainToken).balance, painTokenBeforeSellETHBalance - amountReturned);
        assertEq(address(pain).balance, painBeforeSellETHBalance + amountReturned.calculateProtocolFeeMinusLotteryFee());
        assertEq(address(painLottery).balance, painLotteryBeforeSellETHBalance + amountReturned.calculateLotteryFee());
    }
}
