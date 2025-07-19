// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IPainBCToken} from "src/pain/interfaces/IPainBCToken.sol";

interface IERC20PainToken is IPainBCToken {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);
}
