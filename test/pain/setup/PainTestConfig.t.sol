// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

// general
uint256 constant BASIS_POINTS = 10_000;
uint256 constant DEFAULT_DECIMALS_PRECISIONS = 10 ** 18;

// user config
uint256 constant INITIAL_FUNDS = 100000 ether;
uint256 constant INITIAL_PURCHASE_ETH = 0.001 ether;
uint256 constant INITIAL_PROTOCOL_FEE = INITIAL_PURCHASE_ETH * PROTOCOL_FEE_BP / BASIS_POINTS;
string constant DEFAULT_TOKEN_NAME = "PainToken";
string constant DEFAULT_TOKEN_SYMBOL = "PAIN";

// system config
uint256 constant VIRTUAL_ETH_RESERVE = 0.01 ether;
uint256 constant MAX_SUPPLY = 1_000_000_000e18;
uint256 constant MAX_RESERVE_RATIO_BP = 10_000; // 100%
uint256 constant RESERVE_RATIO_BP = 1000; // 10%
uint256 constant SIGNER_PRIVATE_KEY = uint256(keccak256("SIGNER_PRIVATE_KEY"));
address constant UPGRADER = address(uint160(uint256(keccak256("UPGRADER"))));
address constant DONATION_RECEIVER = address(uint160(uint256(keccak256("DONATION_RECEIVER"))));

// fee config
uint16 constant PROTOCOL_FEE_BP = 1000; // 10%
uint16 constant LOTTERY_FEE_BP = 5000; // 50%
uint16 constant DAILY_LOTTERY_FEE_BP = 1000; // 10%, means the rest is for weekly lottery
uint16 constant BUY_BACK_BP = 1000; // 10%
uint16 constant DONATION_BP = 1000; // 10%

// test config
uint256 constant MIN_TOKEN_BOUGHT = 0;
uint256 constant MIN_ETH_RETURNED = 0;

// fork test
address constant MAINNET_MEME = 0xb131f4A55907B10d1F0A50d8ab8FA09EC342cd74;
address constant MAINNET_WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
address constant BASE_WETH = 0x4200000000000000000000000000000000000006;
address constant BASE_GHST = 0xcD2F22236DD9Dfe2356D7C543161D4d260FD9BcB; // Aavegotchi GHST Token deployed on Base
address constant BASE_NON_FUNGIBLE_POSITION_MANAGER = 0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1;

// Uniswap SwapRouter deployed on Mainnet, Polygon, Optimism, Arbitrum, Testnets
address constant MAINNET_UNISWAP_V3_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
// Uniswap SwapRouter02 deployed on Base
address constant BASE_UNISWAP_V3_ROUTER02 = 0x2626664c2603336E57B271c5C0b26F421741e481;
// Uniswap V2 Factory and Router deployed on Base
address constant _BASE_UNISWAP_V2_FACTORY = 0x8909Dc15e40173Ff4699343b6eB8132c65e18eC6;
address constant _BASE_UNISWAP_V2_ROUTER = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24;
