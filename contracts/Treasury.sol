// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title Treasury
 * @dev A governed treasury contract for LittleCoin fee distribution.
 *      Holds and tracks multiple buckets (CHARITY, LIQUIDITY, REWARD) under DAO control.
 */
contract Treasury is AccessControl {
    // Roles
    bytes32 public constant DAO_ROLE = keccak256("DAO_ROLE");

    // Category identifiers
    bytes32 public constant CHARITY   = keccak256("CHARITY");
    bytes32 public constant LIQUIDITY = keccak256("LIQUIDITY");
    bytes32 public constant REWARD    = keccak256("REWARD");

    // Underlying token (LittleCoin)
    IERC20 public immutable token;

    // Balances per category
    mapping(bytes32 => uint256) public balances;

    // Events
    event Deposited(bytes32 indexed category, uint256 amount);
    event Distributed(bytes32 indexed category, address indexed to, uint256 amount);

    /**
     * @param token_  Address of the ERC20 token (LittleCoin)
     * @param dao     Address of the Timelock/DAO that receives DAO_ROLE
     */
    constructor(address token_, address dao) {
        require(token_ != address(0) && dao != address(0), "Treasury: zero address");
        token = IERC20(token_);

        _grantRole(DEFAULT_ADMIN_ROLE, dao);
        _grantRole(DAO_ROLE, dao);
    }

    /**
     * @dev Deposit tokens into a given category. Callable only by the token contract.
     * @param category  One of CHARITY, LIQUIDITY, REWARD
     * @param amount    Amount of tokens to deposit
     */
    function deposit(bytes32 category, uint256 amount) external {
        require(msg.sender == address(token), "Treasury: only token can deposit");
        require(amount > 0, "Treasury: zero amount");
        require(
            category == CHARITY || category == LIQUIDITY || category == REWARD,
            "Treasury: invalid category"
        );

        balances[category] += amount;
        emit Deposited(category, amount);
    }

    /**
     * @dev Distribute tokens from a category to a recipient. Callable only by DAO.
     * @param category  One of CHARITY, LIQUIDITY, REWARD
     * @param to        Recipient address
     * @param amount    Amount of tokens to distribute
     */
    function distribute(bytes32 category, address to, uint256 amount) external {
        // Only DAO can call
        require(hasRole(DAO_ROLE, msg.sender), "AccessControl");
        require(to != address(0), "Treasury: zero address");
        require(amount > 0 && balances[category] >= amount, "Treasury: insufficient balance");
        require(
            category == CHARITY || category == LIQUIDITY || category == REWARD,
            "Treasury: invalid category"
        );

        balances[category] -= amount;
        require(token.transfer(to, amount), "Treasury: transfer failed");

        emit Distributed(category, to, amount);
    }

    /**
     * @dev Returns the total tokens held in the treasury.
     */
    function totalHeld() external view returns (uint256) {
        return balances[CHARITY] + balances[LIQUIDITY] + balances[REWARD];
    }
}
