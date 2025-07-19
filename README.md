# Pain

Pain is a suite of contracts to be deployed on EVM L2 and achieve what [pump.fun](https://pump.fun/) is doing but more. Other than launching any unruggable ERC20 tokens with bonding curve which will trigger LP promotion when the token reaches a certain Market Cap. More features like Lottery, Donation, Token buy back & burn etc are also supported on Pain.

## Contract Strcuture

| Contract      | Description                                                                                                                                             |
| ------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Pain`        | Main entry for users to launch unruggable PainBCToken with 1B fixed supply, collects protocol fee, supports admin operations e.g. token buy back & burn |
| `PainBCToken` | Immutable ERC20 token deployed as minimal proxy, minted and burnt via bonding curve, will be migrated to Uniswap V2 0.3% Pool when reaches target MC    |
| `PainLottery` | Collects the lottery fee, supports setup and distribution of daily & weekly Lottery                                                                     |

### External Contracts Dependency

| Chain | Contract           | Address                                    |
| ----- | ------------------ | ------------------------------------------ |
| Base  | Uniswap V2 Factory | 0x8909Dc15e40173Ff4699343b6eB8132c65e18eC6 |
| Base  | Uniswap V2 Router  | 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24 |
| Base  | WETH               | 0x4200000000000000000000000000000000000006 |
| Base  | Pyth Oracle        | 0x8250f4aF4B972684F7b336503E2D6dFeDeB1487a |

## Glossary

`Basis Points` - A basis point is one hundredth of 1 percentage point, so 1000 BP means 10%

`Proxy` - A proxy contract is an intermediary contract that delegates calls to another smart contract known as the 'implementation' contract. Commonly there are two kinds of proxies which are UUPS and Transparent Proxy. In UUPS proxies the upgrade is handled by the implementation, and can eventually be removed. Transparent proxies on the other hand, include the upgrade and admin logic in the proxy itself.

## Technical Reference

## `Pain.sol`

### Deployment

| Input                             | Usage                                                                     | Example |
| --------------------------------- | ------------------------------------------------------------------------- | ------- |
| `address painLottery`             | The address of the deployed `painLottery.sol`                             | `0x...` |
| `address painTokenImplementation` | The "interface" for newly deployed token to use as the codebase           | `0x...` |
| `uint256 reserveRatioBP`          | The percentage for reserve ratio in Basis Points                          | `1000`  |
| `uint16 protocolFeeBP`            | The percentage for protocol fee in Basis Points                           | `1000`  |
| `uint16 lotteryFeeBP`             | The percentage for lottery fee in Basis Points                            | `5000`  |
| `uint16 buyBackBP`                | The percentage taken from protocol fee in Basis Points to buy back tokens | `1000`  |
| `uint16 donationBP`               | The percentage taken from migrated liquidity in Basis Points to donate    | `1000`  |

### User functions

| Method                                                                                              | Usage                                                                                                                                                                                                                                                                            |
| --------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `deployTokenAsClone(uint256 tokenId, string name, string symbol, bool isDonating, bytes signature)` | Deploy a new token as a minimal proxy with Bonding Curve applied, a protocol fee on top of `_INITIAL_PURCHASE_ETH` should be passed in when calling, a signature signed by our signer with token information is needed in order to have users launch new token via platform only |

The message to sign as `signature` will be:

```
"deploy-new-token_id-", tokenId, "_name-", name, "_symbol-", symbol, "_isDonating-", isDonating
```

For example a message could be `deploy-new-token_id-0_name-hello world_symbol-HW_isDonating-false`, the way of constructing the signature can be referenced from `signTokenDeploymentMessage` on [PainTestHelpers.t.sol](./test/utils/PainTestHelpers.t.sol).

P.S.: There could be spacing between the letters of the name, or checkings could be enforced externally via backend

### Getter functions

| Method                | Usage                                                                         | Return                      |
| --------------------- | ----------------------------------------------------------------------------- | --------------------------- |
| `getReserveRatioBP()` | Get the reserve ratio for bonding curve calulcation in Basis Points           | `uint256 _RESERVE_RATIO_BP` |
| `getProtocolFeeBP()`  | Get the percentage for protocol fee in Basis Points                           | `uint16 protocolFeeBP`      |
| `getLotteryFeeBP()`   | Get the percentage for lottery fee in Basis Points                            | `uint16 lotteryFeeBP`       |
| `getBuyBackBP()`      | Get the percentage taken from protocol fee in Basis Points to buy back tokens | `uint16 buyBackBP`          |
| `getDonationBP()`     | Get the percentage taken from migrated liquidity in Basis Points to donate    | `uint16 donationBP`         |

### Admin functions

| Method                                                                           | Usage                                                                             |
| -------------------------------------------------------------------------------- | --------------------------------------------------------------------------------- |
| `buyBackAndBurn(address buyBackToken, uint24 poolFee, uint256 amountOutMinimum)` | Buy back tokens with the collected fee and burn them                              |
| `setFeeBP(uint16 newProtocolFeeBP, uint16 newLotteryFeeBP)`                      | Set both the new percentage for protocol fee and lottery fee in Basis Points      |
| `setBuyBackBP(uint256 newBuyBackBP)`                                             | Set the new percentage taken from protocol fee in Basis Points to buy back tokens |
| `setDonationBP(uint256 newDonationBP)`                                           | Set the new percentage taken from migrated liquidity in Basis Points to donate    |
| `withdrawProtocolFee(address receiver)`                                          | Withdraw all protocol fee collected to receiver                                   |
| `receiveProtocolFee()`                                                           | Callback function to receive protocol fee from deployed tokens                    |

### Events

| Event                                                                                                                 | Description                                                                    |
| --------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| `NewTokenDeployed(address indexed deployedBy, address indexed token, string name, string symbol, uint256 deployedAt)` | Emitted when a user deployed a new token                                       |
| `BoughtBackAndBurnt(address indexed buyBackToken, uint256 usedETH, uint256 amountBurnt, uint256 burntAt)`             | Emitted when the admin used the collected fee to buy back tokens and burn them |

## `PainBCToken.sol`

### User functions

| Method             | Usage                                                                                                                   |
| ------------------ | ----------------------------------------------------------------------------------------------------------------------- |
| `buy(buyAmount)`   | Buy tokens via bonding curve, fee is expected to be added on top if the buyAmount is specified, 0 if no specific amount |
| `sell(sellAmount)` | Sell tokens via bonding curve, fee is applied to the ETH returned after selling                                         |

### Getter functions

| Method                        | Usage                                                         | Return                      |
| ----------------------------- | ------------------------------------------------------------- | --------------------------- |
| `getBuyReturnByExactETH()`    | Get the amount of token by buying with exact amount of ETH    | `uint256 tokenAmount`       |
| `getSaleReturnByExactToken()` | Get the amount of ETH by selling exact amount of token in wei | `uint256 weiAmount`         |
| `getSaleReturnForOneToken()`  | Get the amount of ETH by selling one token in wei             | `uint256 weiAmount`         |
| `getTokenMarketCap()`         | Get the current market cap of the token in wei                | `uint256 weiAmount`         |
| `getDonationReceiver()`       | Get the address of the donation receiver                      | `address DONATION_RECEIVER` |
| `getPoolBalance()`            | Get the ETH balance in the bonding curve in wei               | `uint256 weiAmount`         |
| `isTokenProtmoted()`          | Check if the token is being promoted to LP                    | `bool isTokenProtmoted`     |

### Events

| Event                                                                                                                  | Description                                                           |
| ---------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------- |
| `TokenBought(address indexed buyer, uint256 amountBought, uint256 depositAmount)`                                      | Emitted when a user bought the token via bonding curve                |
| `TokenSold(address indexed seller, uint256 amountReturned, uint256 sellAmount)`                                        | Emitted when a user sold the token via bonding curve                  |
| `Donated(address indexed promotedToken, address donatedTo, uint256 amount)`                                            | Emitted when part of the LP for the token during promotion is donated |
| `PromotedToLP(address indexed poolAddress, uint256 liquidity, uint256 usedETH, uint256 usedToken, uint256 promotedAt)` | Emitted when a token reached the target MC to promote to LP           |

## `PainLottery.sol`

### Specific data types

```solidity
/// @param prizeToken the token address for the lottery prize
/// @param bonusPrizeToken the token address for the lottery bonus prize if there is any
/// @param interval enum of `LotteryInterval`, this is saved for reference and is not used against any verifications
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
```

### Deployment

| Input                       | Usage                                                | Example |
| --------------------------- | ---------------------------------------------------- | ------- |
| `uint256 dailyLotteryFeeBP` | The percentage for daily lottery fee in Basis Points | `1000`  |

### User functions

| Method                                  | Usage                                                                |
| --------------------------------------- | -------------------------------------------------------------------- |
| `claimLotteryPrize(LotteryClaim claim)` | Claim lottery prize, will also claim the bonus prize if there is any |

### Getter functions

| Method                                               | Usage                                                                  | Return                       |
| ---------------------------------------------------- | ---------------------------------------------------------------------- | ---------------------------- |
| `getLotteryInfo(uint256 lotteryId)`                  | Get the info of respective lottery by its id                           | `Lottery lottery`            |
| `getLotteryPoolByInterval(LotteryInterval interval)` | Get the ETH balance of respective lottery pool                         | `uint256 poolETHAmount`      |
| `getDailyLotteryFeeBP()`                             | Get the percentage of fee allocated for daily lottery in Basis Points  | `uint256 dailyLotteryFeeBP`  |
| `getWeeklyLotteryFeeBP()`                            | Get the percentage of fee allocated for weekly lottery in Basis Points | `uint256 weeklyLotteryFeeBP` |

### Admin functions

| Method                                                 | Usage                                                                                          |
| ------------------------------------------------------ | ---------------------------------------------------------------------------------------------- |
| `swapFeeToPrizeAndSettleLottery(LotteryConfig config)` | Settle the lottery result by swapping the collected fees into lottery prize                    |
| `withdrawExpiredPrize(uint256 lotteryId)`              | Withdraw any lottery prize after it is expired by its lotteryId                                |
| `setDailyLotteryFeeBP(uint256 newDailyLotteryFeeBP)`   | Set the new daily lottery fee BP, the weekly lottery fee BP will be recalculated automatically |
| `receiveLotteryFee()`                                  | Callback function to receive lottery fee from Pain                                             |

### Events

| Event                                                                                                                    | Description                                                                                         |
| ------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------- |
| `LotteryClaimed(address indexed claimer, uint256 lotteryId, uint256 claimedAt)`                                          | Emitted when a user claimed the lottery prize                                                       |
| `SwappedAndSettledLotteryResult(uint256 indexed lotteryId, uint256 totalAmountUsedForSwap, uint256 swappedAndSettledAt)` | Emitted when the admin settled the lottery result and swapped the collected fees into lottery prize |

## Test Environment

### Tenderly Virtual TestNet - Base

| Contract                     | Address                                    |
| ---------------------------- | ------------------------------------------ |
| Pain (Proxy)                 | 0x6F6f570F45833E249e27022648a26F4076F48f78 |
| Pain (Implementation)        | 0x99dBE4AEa58E518C50a1c04aE9b48C9F6354612f |
| PainBCToken (Implementation) | 0xd6e1afe5cA8D00A2EFC01B89997abE2De47fdfAf |
| PainLottery                  | 0xf32d39ff9f6aa7a7a64d7a4f00a54826ef791a55 |

| Actor             | Address                                    |
| ----------------- | ------------------------------------------ |
| Deployer          | 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 |
| Upgrader          | 0x928Cfea9D9f10844049e4F2EEc80769d335766eC |
| Signer            | 0x33510Ae1136b2081B21e1d0d063DB6B3CfaDdE2E |
| Donation Receiver | 0xD1059dDb61B6a0fef8A21dec3692C3b0829bf0a7 |

## Foundry Commands

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```
