// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "./LittleCoinV2.sol";
import "./ITreasury.sol";

/// @notice Echidna harness combining LittleCoinV2 and an on-chain Treasury stub
contract EchidnaHarness is LittleCoinV2, ITreasury {
    // Internal identifiers for categories
    bytes32 private constant _CHARITY   = keccak256("CHARITY");
    bytes32 private constant _LIQUIDITY = keccak256("LIQUIDITY");
    bytes32 private constant _REWARD    = keccak256("REWARD");

    // Treasury balances for each category
    mapping(bytes32 => uint256) public override balances;

    constructor()
        // Pass: timelock DAO, charity wallet, liquidity wallet, reward wallet, cap
        LittleCoinV2(
            address(this),             // daoTimelock
            address(this),             // charity_
            address(this),             // liquidity_
            address(this),             // reward_
            1_000_000_000 * 1e18       // cap == initial supply
        )
    {
        // Exempt harness (DAO) from fees
        isFeeExempt[address(this)] = true;
    }

    // ======== ITreasury Interface Implementation ========
    function CHARITY() external pure override returns (bytes32) {
        return _CHARITY;
    }
    function LIQUIDITY() external pure override returns (bytes32) {
        return _LIQUIDITY;
    }
    function REWARD() external pure override returns (bytes32) {
        return _REWARD;
    }
    function deposit(bytes32 category, uint256 amount) external override {
        require(msg.sender == address(this), "Only token can deposit");
        balances[category] += amount;
    }
    function distribute(bytes32, address, uint256) external pure override {
        // no-op for invariant testing
    }

    // ======== Invariants ========
    /// totalFeeBP never exceeds MAX_FEE_BP
    function echidna_fee_within_bounds() public view returns (bool) {
        return totalFeeBP <= MAX_FEE_BP;
    }

    /// totalSupply never exceeds cap
    function echidna_cap_not_exceeded() public view returns (bool) {
        return totalSupply() <= cap();
    }

    /// fee distribution sums to 10000 basis points
    function echidna_fee_distribution_sums_to_10000() public view returns (bool) {
        return uint256(burnFeeBP) + charityFeeBP + liquidityFeeBP + rewardFeeBP == 10000;
    }

    /// Treasury balances never underflow
    function echidna_treasury_non_negative() public view returns (bool) {
        return balances[_CHARITY]   >= 0
            && balances[_LIQUIDITY] >= 0
            && balances[_REWARD]    >= 0;
    }

    /// Harness retains all admin roles
    function echidna_admin_roles_intact() public view returns (bool) {
        return hasRole(DEFAULT_ADMIN_ROLE, address(this))
            && hasRole(FEE_ADMIN_ROLE, address(this))
            && hasRole(WALLET_UPDATER_ROLE, address(this));
    }

    // ======== Action Wrappers ========
    function test_transfer(address to, uint256 amount) external {
        uint256 bal = balanceOf(address(this));
        _transferWithFee(address(this), to, amount % (bal + 1));
    }

    function test_transferFrom(address from, address to, uint256 amount) external {
        _approve(from, address(this), type(uint256).max);
        uint256 bal = balanceOf(from);
        _transferWithFee(from, to, amount % (bal + 1));
    }

    function test_setTotalFeeBP(uint16 feeBP) external {
        if (hasRole(FEE_ADMIN_ROLE, address(this))) {
            this.setTotalFeeBP(feeBP % (MAX_FEE_BP + 1));
        }
    }

    function test_setFeeDistribution(uint16 b, uint16 c, uint16 l, uint16 r) external {
        if (hasRole(FEE_ADMIN_ROLE, address(this))) {
            if (uint256(b) + c + l + r == 10000) {
                this.setFeeDistribution(b, c, l, r);
            }
        }
    }

    function test_setFeeExempt(address acct, bool ex) external {
        if (hasRole(FEE_ADMIN_ROLE, address(this))) {
            this.setFeeExempt(acct, ex);
        }
    }

    function test_updateCharityWallet(address newW) external {
        if (hasRole(WALLET_UPDATER_ROLE, address(this)) && newW != address(0)) {
            this.updateCharityWallet(newW);
        }
    }
    function test_updateLiquidityWallet(address newW) external {
        if (hasRole(WALLET_UPDATER_ROLE, address(this)) && newW != address(0)) {
            this.updateLiquidityWallet(newW);
        }
    }
    function test_updateRewardWallet(address newW) external {
        if (hasRole(WALLET_UPDATER_ROLE, address(this)) && newW != address(0)) {
            this.updateRewardWallet(newW);
        }
    }

    function test_pause() external {
        if (hasRole(DEFAULT_ADMIN_ROLE, address(this))) {
            _pause();
        }
    }

    function test_unpause() external {
        if (hasRole(DEFAULT_ADMIN_ROLE, address(this))) {
            _unpause();
        }
    }

    function test_mint(address to, uint256 amount) external {
        if (hasRole(FEE_ADMIN_ROLE, address(this))) {
            uint256 allowed = cap() - totalSupply();
            _mint(to, amount % (allowed + 1));
        }
    }

    function test_burn(uint256 amount) external {
        uint256 bal = balanceOf(address(this));
        _burn(address(this), amount % (bal + 1));
    }
}
