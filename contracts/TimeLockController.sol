// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/governance/TimelockController.sol";

/**
 * @title LittleCoinTimelock
 * @dev Production-grade TimelockController for LittleCoin governance.
 *      Enforces a minimum delay on all privileged actions, controlled via multisig.
 */
contract LittleCoinTimelock is TimelockController {
    /// @notice Minimum delay for queued operations: 2 days
    uint256 public constant MIN_DELAY = 2 days;

    /**
     * @param proposers Addresses allowed to propose operations.
     * @param executors Addresses allowed to execute operations once the delay has passed.
     * @param admin Address that will hold the TIMELOCK_ADMIN_ROLE and can grant/revoke roles.
     */
    constructor(
        address[] memory proposers,
        address[] memory executors,
        address admin
    )
        TimelockController(
            MIN_DELAY,
            proposers,
            executors,
            admin
        )
    {}
}