// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IUSDT is IERC20 {
    function allocateTo(address _owner, uint256 value) external;
}