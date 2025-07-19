// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IPainBCToken {
    /// @dev Emitted when a user bought the token via bonding curve
    event TokenBought(address indexed buyer, uint256 amountBought, uint256 depositAmount);
    /// @dev Emitted when a user sold the token via bonding curve
    event TokenSold(address indexed seller, uint256 amountReturned, uint256 sellAmount);
    /// @dev Emitted when part of the LP for the token during promotion is donated
    event Donated(address indexed promotedToken, address donatedTo, uint256 amount);
    /// @dev Emitted when a token reached the target MC to promote to LP
    event PromotedToLP(
        address indexed poolAddress, uint256 liquidity, uint256 usedETH, uint256 usedToken, uint256 promotedAt
    );

    error OnlyFromPain();
    error ZeroAmount();
    error CannotExceedMaxSupply();
    error InsufficientFundsToBuyExactTokens();
    error NotEnoughAmountToSell();
    error ReturnLessThanExpected();
    error BondingCurveAlreadyEnded();
    error EtherTransferFailed();

    function initialize(
        address pain,
        address painLottery,
        address tokenDeployer,
        string memory _name,
        string memory _symbol,
        bool isDonating
    ) external payable;
    function buy(uint256 buyAmount, uint256 minTokenBought) external payable returns (uint256 amountMinted);
    function sell(uint256 sellAmount, uint256 minETHReturned) external returns (uint256 amountReturned);

    function getBuyReturnByExactETH(uint256 weiAmount) external view returns (uint256 tokenAmount);
    function getETHNeededByExactToken(uint256 tokenAmount) external view returns (uint256 weiAmount);
    function getSaleReturnByExactToken(uint256 tokenAmount) external view returns (uint256 weiAmount);
    function getSaleReturnForOneToken() external view returns (uint256);

    function getTokenMarketCap() external view returns (uint256);
    function getPoolBalance() external view returns (uint256);
    function getCurrentTokenPurchased() external view returns (uint256);
    function isTokenDonating() external view returns (bool);
    function isTokenProtmoted() external view returns (bool);
}
