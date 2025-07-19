// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {IPain} from "./interfaces/IPain.sol";
import {IPainLottery} from "./interfaces/IPainLottery.sol";
import {IPainBCToken} from "./interfaces/IPainBCToken.sol";

interface IWETH9 {
    /// @notice Deposit ether to get wrapped ether
    function deposit() external payable;

    /// @notice Withdraw wrapped ether to get ether
    function withdraw(uint256) external;
}

interface ISwapRouter02 {
    // there is no deadline in the swap params for SwapRouter02
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

contract Pain is Initializable, UUPSUpgradeable, OwnableUpgradeable, IPain {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;
    using SafeERC20 for IERC20;
    using Strings for uint256;

    // Uniswap SwapRouter02 deployed on Base
    ISwapRouter02 private constant _BASE_SWAP_ROUTER_02 = ISwapRouter02(0x2626664c2603336E57B271c5C0b26F421741e481);

    address private constant _BASE_WETH9 = 0x4200000000000000000000000000000000000006;
    uint256 private constant _BASIS_POINTS = 10_000;
    uint256 private constant _INITIAL_PURCHASE_ETH = 0.001 ether;
    /// @dev Protocol fee and allocation for donation cannot be more than 50%
    uint256 private constant _MAX_BP_TO_BE_SET = 5000;

    // ISwapRouter02 private _BASE_SWAP_ROUTER_02;
    IPainLottery private _painLottery;

    address private _PAIN_TOKEN_IMPLEMENTATION;

    uint256 private _RESERVE_RATIO_BP;

    address public upgrader;
    address public signer;

    address private _DONATION_RECEIVER;
    uint16 private _protocolFeeBP;
    uint16 private _lotteryFeeBP;
    uint16 private _buyBackBP;
    uint16 private _donationBP;

    modifier onlyUpgrader() {
        if (_msgSender() != upgrader) revert OnlyUpgrader();
        _;
    }

    // // to receive remaining ETH after swap via buyBackAndBurn
    // receive() external payable {}

    // required by the OZ UUPS module
    function _authorizeUpgrade(address) internal override onlyUpgrader {}

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address painLottery,
        address painTokenImplementation,
        address upgrader_,
        address signer_,
        address donationReceiver,
        uint256 reserveRatioBP,
        uint16 protocolFeeBP,
        uint16 lotteryFeeBP,
        uint16 buyBackBP,
        uint16 donationBP
    ) public initializer {
        __UUPSUpgradeable_init();
        __Ownable_init(msg.sender);
        _painLottery = IPainLottery(painLottery);
        _PAIN_TOKEN_IMPLEMENTATION = painTokenImplementation;
        upgrader = upgrader_;
        signer = signer_;
        _DONATION_RECEIVER = donationReceiver;
        _RESERVE_RATIO_BP = reserveRatioBP;
        _protocolFeeBP = protocolFeeBP;
        _lotteryFeeBP = lotteryFeeBP;
        _buyBackBP = buyBackBP;
        _donationBP = donationBP;
    }

    /// @notice Deploy a new token as a minimal proxy with Bonding Curve applied
    /// @param name The name of the token
    /// @param symbol The symbol of the token
    function deployTokenAsClone(
        uint256 tokenId,
        string memory name,
        string memory symbol,
        bool isDonating,
        bytes calldata signature
    ) external payable returns (address deployedToken) {
        uint256 protocolFee = _INITIAL_PURCHASE_ETH * _protocolFeeBP / _BASIS_POINTS;
        if (msg.value != _INITIAL_PURCHASE_ETH + protocolFee) revert InsufficientFunds();

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
        if (!_checkValidity(msg.sender, signature, action)) revert InvalidSignature();

        bytes32 salt = keccak256(abi.encodePacked(msg.sender, tokenId, name, symbol));
        // using same salt will revert on deployment
        deployedToken = Clones.cloneDeterministic(_PAIN_TOKEN_IMPLEMENTATION, salt);

        // fee cut from lottery, rest of the protocol fee goes into this contract
        uint256 lotteryFeeCut = protocolFee * _lotteryFeeBP / _BASIS_POINTS;
        _painLottery.receiveLotteryFee{value: lotteryFeeCut}();

        // deployer will make an initial purchase of 0.001 ETH to start the bonding curve
        IPainBCToken(deployedToken).initialize{value: _INITIAL_PURCHASE_ETH}(
            address(this), address(_painLottery), msg.sender, name, symbol, isDonating
        );

        emit NewTokenDeployed(msg.sender, deployedToken, tokenId, name, symbol, isDonating, block.timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                                 ADMIN
    //////////////////////////////////////////////////////////////*/
    /// @notice Buy back tokens with the collected fee and burn them
    /// @param buyBackToken The token to buy back and burn
    /// @param poolFee The pool fee of the Uniswap v3 pool the `buyBackToken` is being bought in
    /// @param amountOutMinimum The minimum amount of token to receive
    function buyBackAndBurn(address buyBackToken, uint24 poolFee, uint256 amountOutMinimum) external onlyOwner {
        uint256 collectedFeeForBuyBack = address(this).balance * _buyBackBP / _BASIS_POINTS;
        if (collectedFeeForBuyBack == 0) revert InsufficientFunds();

        uint256 tokenBoughtBack = _exactInSwap(buyBackToken, poolFee, collectedFeeForBuyBack, amountOutMinimum);

        // burn the buyBackToken
        IERC20(buyBackToken).safeTransfer(address(0x000000000000000000000000000000000000dEaD), tokenBoughtBack);

        emit BoughtBackAndBurnt(buyBackToken, collectedFeeForBuyBack, tokenBoughtBack, block.timestamp);
    }

    function setFeeBP(uint16 newProtocolFeeBP, uint16 newLotteryFeeBP) public onlyOwner {
        if (newProtocolFeeBP > _MAX_BP_TO_BE_SET || newLotteryFeeBP > _BASIS_POINTS) {
            revert InvalidFeeBP();
        }
        _protocolFeeBP = newProtocolFeeBP;
        _lotteryFeeBP = newLotteryFeeBP;

        emit FeeBPUpdated(newProtocolFeeBP, newLotteryFeeBP);
    }

    function setBuyBackBP(uint16 newBuyBackBP) public onlyOwner {
        if (newBuyBackBP > _BASIS_POINTS) revert InvalidFeeBP();
        _buyBackBP = newBuyBackBP;

        emit BuyBackBPUpdated(newBuyBackBP);
    }

    function setDonationBP(uint16 newDonationBP) public onlyOwner {
        if (newDonationBP > _MAX_BP_TO_BE_SET) revert InvalidFeeBP();
        _donationBP = newDonationBP;

        emit DonationBPUpdated(newDonationBP);
    }

    function setUpgrader(address _upgrader) external onlyOwner {
        upgrader = _upgrader;

        emit UpgraderUpdated(_upgrader);
    }

    function setSigner(address _signer) external onlyOwner {
        signer = _signer;

        emit SignerUpdated(_signer);
    }

    function withdrawProtocolFee(address receiver) external onlyOwner {
        uint256 balance = address(this).balance;
        if (balance > 0) {
            _safeTransferETH(receiver, balance);
        }
    }

    /// @notice This is used to receive the trading fee from any tokens deployed from `deployTokenAsClone`
    function receiveProtocolFee() external payable {}

    /*//////////////////////////////////////////////////////////////
                               INTERNALS
    //////////////////////////////////////////////////////////////*/
    function _exactInSwap(address tokenOut, uint24 poolFee, uint256 exactAmountIn, uint256 amountOutMinimum)
        internal
        returns (uint256 amountOut)
    {
        // swap via Uniswap SwapRouter
        ISwapRouter02.ExactInputSingleParams memory params = ISwapRouter02.ExactInputSingleParams({
            tokenIn: _BASE_WETH9,
            tokenOut: tokenOut,
            fee: poolFee,
            recipient: address(this),
            amountIn: exactAmountIn,
            amountOutMinimum: amountOutMinimum,
            sqrtPriceLimitX96: 0 // 0 slippage
        });

        // wrap ETH to WETH
        IWETH9(_BASE_WETH9).deposit{value: exactAmountIn}();
        // approve the _BASE_SWAP_ROUTER_02 to spend WETH
        IERC20(_BASE_WETH9).approve(address(_BASE_SWAP_ROUTER_02), exactAmountIn);

        amountOut = _BASE_SWAP_ROUTER_02.exactInputSingle(params);

        if (IERC20(tokenOut).balanceOf(address(this)) < amountOut) revert SwapExactAmountOutNotEnough();
    }

    function _checkValidity(address _requester, bytes calldata _signature, string memory _action)
        private
        view
        returns (bool)
    {
        bytes32 hashVal = keccak256(abi.encodePacked(_requester, _action));
        bytes32 signedHash = hashVal.toEthSignedMessageHash();

        return signedHash.recover(_signature) == signer;
    }

    function _safeTransferETH(address to, uint256 value) internal {
        (bool success,) = to.call{value: value}(new bytes(0));
        if (!success) revert EtherTransferFailed();
    }

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/
    function getReserveRatioBP() external view returns (uint256) {
        return _RESERVE_RATIO_BP;
    }

    function getProtocolFeeBP() external view returns (uint16) {
        return _protocolFeeBP;
    }

    function getLotteryFeeBP() external view returns (uint16) {
        return _lotteryFeeBP;
    }

    function getBuyBackBP() external view returns (uint16) {
        return _buyBackBP;
    }

    function getDonationBP() external view returns (uint16) {
        return _donationBP;
    }

    function getDonationReceiver() external view returns (address) {
        return _DONATION_RECEIVER;
    }

    function getPainTokenImplementation() external view returns (address) {
        return _PAIN_TOKEN_IMPLEMENTATION;
    }

    function predictCreate2AddressForToken(address user, uint256 tokenId, string memory name, string memory symbol)
        external
        view
        returns (address)
    {
        bytes32 salts = keccak256(abi.encodePacked(user, tokenId, name, symbol));
        return Clones.predictDeterministicAddress(_PAIN_TOKEN_IMPLEMENTATION, salts);
    }
}
