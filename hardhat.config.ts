import { HardhatUserConfig, vars } from 'hardhat/config';
import { ethers } from 'ethers';

import '@openzeppelin/hardhat-upgrades';
import '@nomicfoundation/hardhat-ethers';
import '@nomicfoundation/hardhat-verify';
import '@nomiclabs/hardhat-solhint';
import '@typechain/hardhat';
import 'hardhat-abi-exporter';
import 'hardhat-deploy';
import 'hardhat-deploy-ethers';
import 'hardhat-gas-reporter';
import 'hardhat-storage-layout';
import 'hardhat-watcher';
import * as tdly from '@tenderly/hardhat-tenderly';

import 'dotenv/config';

import type { HardhatNetworkAccountConfig, HttpNetworkAccountsUserConfig, NetworkUserConfig } from 'hardhat/types';

// =============== Tenderly Configuration ===============
if (process.env.TENDERLY_AUTO_VERIFY) {
  console.info('Enabling Tenderly auto-verification...');
  tdly.setup({ automaticVerifications: true });
} else {
  tdly.setup({ automaticVerifications: false });
}

// =============== Accounts Configuration ===============
// Input WALLET_PRIVATE_KEY if you have specific account to use
const firstWalletPrivatekey: string | undefined = process.env.WALLET_PRIVATE_KEY;
const secondWalletPrivateKey: string | undefined = process.env.SECOND_WALLET_PRIVATE_KEY;
const thirdWalletPrivateKey: string | undefined = process.env.THIRD_WALLET_PRIVATE_KEY;

const mnemonic = 'test test test test test test test test test test test junk';
let accounts: HttpNetworkAccountsUserConfig = [];
const localhostAccounts: HardhatNetworkAccountConfig[] = [];

if (!firstWalletPrivatekey) {
  console.log('Using Mnemonic test accounts ...');
  accounts = { mnemonic };
} else {
  accounts = [firstWalletPrivatekey];
  if (secondWalletPrivateKey) accounts.push(secondWalletPrivateKey);
  if (thirdWalletPrivateKey) accounts.push(thirdWalletPrivateKey);

  for (const account of accounts) {
    // localhost using testnet wallet addresses - make use of these in hardhat network setting if you want to test localhost with testnet wallet addresses
    localhostAccounts.push({
      privateKey: account,
      balance: ethers.parseEther((1e9).toString()).toString(),
    });
  }
}

// =============== Hardhat Configuration ================
const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.25",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },
  tenderly: {
    username: '9gag',
    project: 'pump',
    privateVerification: true,
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY
  },
  paths: {
    sources: './src', // Path to your contracts
    cache: './cache',
    artifacts: './artifacts',
  },
  abiExporter: {
    path: './build/abi',
    clear: false,
    flat: false,
    runOnCompile: true,
    // only: [],
    // except: [],
  },
  networks: {
    hardhat: {
      chainId: 1337,
      accounts: localhostAccounts,
    },
    localhost: {
      url: 'http://localhost:8545',
      chainId: 31337,
      accounts,
    },
    tenderly: {
      url: 'https://rpc.tenderly.co/fork/fc8d8ca7-a460-4f31-90fa-c50ac49b7f2c',
      chainId: 69691,
      accounts,
    },
    tenderlyTestnet: {
      url: 'https://virtual.base.rpc.tenderly.co/b4cd2ce5-7b23-475b-9602-0bd0954d130f',
      chainId: 8453001,
      accounts,
    },
    sepolia: {
      url: `https://sepolia.infura.io/v3/${process.env.INFURA_API_KEY}`,
      accounts,
      chainId: 11155111,
      gasMultiplier: 2,
    },
  },
};

export default config;
