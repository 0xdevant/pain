// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {
    Initializable,
    ERC20Upgradeable,
    IERC20
} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import {BancorBondingCurve} from "./maths/BancorBondingCurve.sol";
import {IPainBCToken} from "./interfaces/IPainBCToken.sol";
import {IPain} from "./interfaces/IPain.sol";
import {IPainLottery} from "./interfaces/IPainLottery.sol";

interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface IUniswapV2Router02 {
    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external payable returns (uint256 amountToken, uint256 amountETH, uint256 liquidity);
}

contract PainBCToken is Initializable, ERC20Upgradeable, IPainBCToken, BancorBondingCurve {
    // Uniswap configs
    IUniswapV2Factory private constant _BASE_UNISWAP_V2_FACTORY =
        IUniswapV2Factory(0x8909Dc15e40173Ff4699343b6eB8132c65e18eC6);
    IUniswapV2Router02 private constant _BASE_UNISWAP_V2_ROUTER =
        IUniswapV2Router02(0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24);

    address private constant _BASE_WETH9 = 0x4200000000000000000000000000000000000006;
    uint256 private constant _BASIS_POINTS = 10_000;
    uint256 private constant _DEFAULT_DECIMALS_PRECISIONS = 10 ** 18;
    uint256 private constant _THRESHOLD_TO_LP = 20 ether; // ~69k
    uint256 private constant _MIN_PURCHASE_ETH_AMOUNT = 0.0001 ether;
    // used for bonding curve calculation
    uint256 private constant _VIRTUAL_TOKEN_RESERVE = 1_000_000_000 ether;
    uint256 private constant _VIRTUAL_ETH_RESERVE = 0.01 ether;
    uint256 private constant _MAX_SUPPLY = 1_000_000_000 ether; // 1B max supply
    uint256 private constant _ONE_TOKEN = 1 ether;

    // token deployer can choose to donate to a charity wallet
    bool private _isDonating;

    IPain private _pain;
    IPainLottery private _painLottery;

    /// @dev The total ETH balance in the pool, used to calculate the token price
    uint256 private _poolBalance;
    /// @dev The total current token purchased via bonding curve, hence increase with buy and decrease with sell, used to calculate the token price
    uint256 private _currentTokenPurchased;

    bool private _promotedToLP;

    modifier onlyValidAmount(uint256 amount) {
        if (amount == 0) revert ZeroAmount();
        _;
    }

    modifier onlyLessThatMaxSupply(uint256 amount) {
        if (amount + _currentTokenPurchased > _MAX_SUPPLY) revert CannotExceedMaxSupply();
        _;
    }

    modifier onlyBCOngoing() {
        if (_promotedToLP) revert BondingCurveAlreadyEnded();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address pain,
        address painLottery,
        address tokenDeployer,
        string memory _name,
        string memory _symbol,
        bool isDonating
    ) external payable override initializer {
        ERC20Upgradeable.__ERC20_init(_name, _symbol);
        _pain = IPain(pain);
        _painLottery = IPainLottery(painLottery);
        if (isDonating) _isDonating = true;

        // every token has 1B fixed supply
        _mint(address(this), _MAX_SUPPLY);
        // initial purchase from token deployer
        _buyViaBC(tokenDeployer, msg.value);
    }

    /// @notice Buy tokens via bonding curve, fee is expected to be added on top of the desired amount
    /// @param buyAmount The exact amount of token user wants to buy, 0 if no specific amount
    /// @dev The exact ETH(plus fee) will be passed from frontend if user wants to purchase exact amount of token as getting this number from Solidity will incur precision loss.
    ///      Protocol fee is expected to be added on top of the expected purchase amount user sees on frontend.
    function buy(uint256 buyAmount, uint256 minTokenBought)
        external
        payable
        override
        onlyValidAmount(msg.value)
        onlyLessThatMaxSupply(buyAmount)
        onlyBCOngoing
        returns (uint256 amountBought)
    {
        bool isFeeOntop;
        // additional checks for exact token buy
        if (buyAmount != 0) {
            isFeeOntop = true;
            // get the original amount before adding fee on top
            uint256 etherAmountToBuyBeforeFee = msg.value * _BASIS_POINTS / (_BASIS_POINTS + _pain.getProtocolFeeBP());
            uint256 exactTokenAmount = getBuyReturnByExactETH(etherAmountToBuyBeforeFee);
            if (buyAmount != exactTokenAmount) revert InsufficientFundsToBuyExactTokens();
        }

        uint256 amountAfterFee = _feeCut(msg.value, isFeeOntop);
        amountBought = _buyViaBC(msg.sender, amountAfterFee);
        if (amountBought < minTokenBought) revert ReturnLessThanExpected();

        emit TokenBought(msg.sender, amountBought, amountAfterFee);

        if (_isTargetMarketCapReached()) {
            // donate part of the ETH to Pain's donationReceiver before minting into LP
            if (_isDonating) {
                _handleDonation(_pain.getDonationReceiver());
            }
            _promoteToLP();
        }
    }

    /// @notice Sell tokens via bonding curve, fee is applied to the ETH returned after selling
    /// @param sellAmount The exact amount of token user wants to sell
    function sell(uint256 sellAmount, uint256 minETHReturned)
        external
        override
        onlyValidAmount(sellAmount)
        onlyLessThatMaxSupply(sellAmount)
        onlyBCOngoing
        returns (uint256 amountReturned)
    {
        amountReturned = _sellViaBC(sellAmount);
        if (amountReturned < minETHReturned) revert ReturnLessThanExpected();

        uint256 returnedAmountAfterFee = _feeCut(amountReturned, false);
        _safeTransferETH(msg.sender, returnedAmountAfterFee);

        emit TokenSold(msg.sender, amountReturned, sellAmount);
    }

    /*//////////////////////////////////////////////////////////////
                               INTERNALS
    //////////////////////////////////////////////////////////////*/
    function _buyViaBC(address sendTo, uint256 weiAmount) internal returns (uint256 buyReturn) {
        buyReturn = getBuyReturnByExactETH(weiAmount);
        _currentTokenPurchased += buyReturn;
        _poolBalance += weiAmount;

        _transfer(address(this), sendTo, buyReturn);
    }

    function _sellViaBC(uint256 sellAmount) internal returns (uint256 saleReturn) {
        if (balanceOf(msg.sender) < sellAmount) revert NotEnoughAmountToSell();

        saleReturn = getSaleReturnByExactToken(sellAmount);
        // Safety:  _currentTokenPurchased must be >= sellAmount at this point since only buy can happen before first sell
        _currentTokenPurchased -= sellAmount;
        // Safety:  _poolBalance must be >= saleReturn at this point, reason is same as above
        _poolBalance -= saleReturn;

        transfer(address(this), sellAmount);
    }

    function _feeCut(uint256 amount, bool isFeeOntop) internal returns (uint256 amountAfterFee) {
        uint256 etherAmountBeforeFee = amount;
        if (isFeeOntop) {
            // get the original amount before adding fee on top to calculate correct protocol fee for buy
            etherAmountBeforeFee = amount * _BASIS_POINTS / (_BASIS_POINTS + _pain.getProtocolFeeBP());
        }

        uint256 protocolFee = etherAmountBeforeFee * _pain.getProtocolFeeBP() / _BASIS_POINTS;
        amountAfterFee = amount - protocolFee;
        // fee cut from lottery, rest of the protocol fee goes into pain
        uint256 lotteryFeeCut = protocolFee * _pain.getLotteryFeeBP() / _BASIS_POINTS;

        _pain.receiveProtocolFee{value: protocolFee - lotteryFeeCut}();
        _painLottery.receiveLotteryFee{value: lotteryFeeCut}();
    }

    /// @dev Once the token reaches market cap of `THRESHOLD_TO_LP`, rest of the liquidity is automatically migrated to a Uniswap V2 0.3% pool
    function _promoteToLP() internal returns (uint256 amountToken, uint256 amountETH, uint256 liquidityMinted) {
        uint256 poolBalance = _poolBalance;
        uint256 tokenBalance = balanceOf(address(this));

        address poolAddress = _BASE_UNISWAP_V2_FACTORY.createPair(_BASE_WETH9, address(this));

        // ETH will be automatically wrapped to WETH on v2, approve the _BASE_UNISWAP_V2_ROUTER to spend the token
        IERC20(address(this)).approve(address(_BASE_UNISWAP_V2_ROUTER), tokenBalance);

        _poolBalance = 0;
        _promotedToLP = true;

        (amountToken, amountETH, liquidityMinted) = _BASE_UNISWAP_V2_ROUTER.addLiquidityETH{value: poolBalance}({
            token: address(this),
            amountTokenDesired: tokenBalance,
            amountTokenMin: tokenBalance * 99 / 100, // 1% slippage
            amountETHMin: poolBalance * 99 / 100, // 1% slippage
            to: address(this),
            deadline: block.timestamp + 1 minutes
        });

        // liquidity is locked by burning the ERC20 LP token
        IERC20(address(poolAddress)).transfer(address(0x000000000000000000000000000000000000dEaD), liquidityMinted);

        // transfer any ETH leftover to pain
        if (amountETH < poolBalance) {
            _safeTransferETH(address(_pain), poolBalance - amountETH);
        }

        // remove allowance & transfer any token leftover to pain
        if (amountToken < tokenBalance) {
            IERC20(address(this)).approve(address(_BASE_UNISWAP_V2_ROUTER), 0);
            uint256 refund1 = tokenBalance - amountToken;
            _transfer(address(this), address(_pain), refund1);
        }

        emit PromotedToLP(poolAddress, liquidityMinted, amountETH, amountToken, block.timestamp);
    }

    // skipping the conversion from token to ETH as it's same as taking double cut from the ETH balance
    function _handleDonation(address receiver) internal {
        // getDonationBP() wouldn't be > 50%
        uint256 donation = _poolBalance * (_pain.getDonationBP() * 2) / _BASIS_POINTS;
        // Safety: _poolBalance must be >= donation at this point
        unchecked {
            _poolBalance -= donation;
        }
        _safeTransferETH(receiver, donation);

        emit Donated(address(this), receiver, donation);
    }

    function _safeTransferETH(address to, uint256 value) internal {
        (bool success,) = to.call{value: value}(new bytes(0));
        if (!success) revert EtherTransferFailed();
    }

    function _isTargetMarketCapReached() internal view returns (bool) {
        return getTokenMarketCap() / _DEFAULT_DECIMALS_PRECISIONS >= _THRESHOLD_TO_LP;
    }

    function _getETHNeededByOneTokenWithPrecision() internal view returns (uint256 weiAmountPerToken1BE18) {
        uint256 tokenAmountForOneETH = calculatePurchaseReturn(
            _currentTokenPurchased + _VIRTUAL_TOKEN_RESERVE, // circulating supply + _VIRTUAL_TOKEN_RESERVE
            _poolBalance + _VIRTUAL_ETH_RESERVE,
            _pain.getReserveRatioBP(),
            _ONE_TOKEN // 1 ETH
        );
        // in order to prevent precision loss when converting to weiAmount
        weiAmountPerToken1BE18 = _ONE_TOKEN * _MAX_SUPPLY / tokenAmountForOneETH;
    }

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/
    function getBuyReturnByExactETH(uint256 weiAmount) public view returns (uint256 tokenAmount) {
        return calculatePurchaseReturn(
            _currentTokenPurchased + _VIRTUAL_TOKEN_RESERVE, // circulating supply + _VIRTUAL_TOKEN_RESERVE
            _poolBalance + _VIRTUAL_ETH_RESERVE,
            _pain.getReserveRatioBP(),
            weiAmount
        );
    }

    function getETHNeededByExactToken(uint256 tokenAmount) public view returns (uint256 weiAmount) {
        uint256 weiAmountPerToken1BE18 = _getETHNeededByOneTokenWithPrecision();
        return tokenAmount * weiAmountPerToken1BE18 / _MAX_SUPPLY;
    }

    function getSaleReturnByExactToken(uint256 tokenAmount) public view returns (uint256 weiAmount) {
        return calculateSaleReturn(
            _currentTokenPurchased + _VIRTUAL_TOKEN_RESERVE,
            _poolBalance + _VIRTUAL_ETH_RESERVE,
            _pain.getReserveRatioBP(),
            tokenAmount
        );
    }

    function getSaleReturnForOneToken() public view returns (uint256 weiAmount) {
        return getSaleReturnByExactToken(_ONE_TOKEN);
    }

    function getTokenMarketCap() public view returns (uint256 weiAmount) {
        return _currentTokenPurchased * getSaleReturnForOneToken();
    }

    function getPoolBalance() external view override returns (uint256 weiAmount) {
        return _poolBalance;
    }

    function getCurrentTokenPurchased() external view returns (uint256) {
        return _currentTokenPurchased;
    }

    function isTokenDonating() external view returns (bool) {
        return _isDonating;
    }

    function isTokenProtmoted() external view override returns (bool) {
        return _promotedToLP;
    }
}
