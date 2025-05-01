// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ITreasury
 * @dev Interface for Treasury contract used by LittleCoinV2 to deposit fees.
 */
interface ITreasury {
    // Category identifiers must match those in Treasury.sol
    function CHARITY() external pure returns (bytes32);
    function LIQUIDITY() external pure returns (bytes32);
    function REWARD() external pure returns (bytes32);

    /**
     * @dev Deposit an amount of tokens into a specific category.
     * @param category One of CHARITY, LIQUIDITY, REWARD
     * @param amount Amount of tokens to credit
     */
    function deposit(bytes32 category, uint256 amount) external;

    /**
     * @dev Distribute tokens from a specific category to an address.
     * @param category One of CHARITY, LIQUIDITY, REWARD
     * @param to Recipient address
     * @param amount Amount to distribute
     */
    function distribute(bytes32 category, address to, uint256 amount) external;

    /**
     * @dev View the current balance for a given category.
     * @param category One of CHARITY, LIQUIDITY, REWARD
     */
    function balances(bytes32 category) external view returns (uint256);
}
