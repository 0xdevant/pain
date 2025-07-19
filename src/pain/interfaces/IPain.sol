// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IPain {
    event NewTokenDeployed(
        address indexed deployedBy,
        address indexed token,
        uint256 tokenId,
        string name,
        string symbol,
        bool isDonating,
        uint256 deployedAt
    );
    event BoughtBackAndBurnt(address indexed buyBackToken, uint256 usedETH, uint256 amountBurnt, uint256 burntAt);
    event FeeBPUpdated(uint16 newProtocolFeeBP, uint16 newLotteryFeeBP);
    event BuyBackBPUpdated(uint16 newBuyBackBP);
    event DonationBPUpdated(uint16 newDonationBP);
    event SignerUpdated(address newSigner);
    event UpgraderUpdated(address newUpgrader);
    event ProtocolFeeWithdrawn(address receiver, uint256 amount, uint256 withdrawnAt);

    error OnlyUpgrader();
    error InvalidSignature();
    error InvalidFeeBP();
    error InsufficientFunds();
    error SwapExactAmountOutNotEnough();
    error EtherTransferFailed();

    function deployTokenAsClone(
        uint256 tokenId,
        string memory name,
        string memory symbol,
        bool isDonating,
        bytes calldata _signature
    ) external payable returns (address deployedToken);

    function buyBackAndBurn(address buyBackToken, uint24 poolFee, uint256 amountOutMinimum) external;
    function setFeeBP(uint16 newLotteryFeeBP, uint16 newProtocolFeeBP) external;
    function setBuyBackBP(uint16 newBuyBackBP) external;
    function setDonationBP(uint16 newDonationBP) external;
    function withdrawProtocolFee(address receiver) external;

    function receiveProtocolFee() external payable;

    function getReserveRatioBP() external view returns (uint256);
    function getLotteryFeeBP() external view returns (uint16);
    function getProtocolFeeBP() external view returns (uint16);
    function getBuyBackBP() external view returns (uint16);
    function getDonationBP() external view returns (uint16);
    function getDonationReceiver() external view returns (address);
    function getPainTokenImplementation() external view returns (address);

    function predictCreate2AddressForToken(address user, uint256 tokenId, string memory name, string memory symbol)
        external
        view
        returns (address);
}
