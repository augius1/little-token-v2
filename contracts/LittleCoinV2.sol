// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./ITreasury.sol";

/**
 * @title LittleCoinV2
 * @dev ERC20 token with capped supply, role-based access, pausability,
 *      and configurable fee wallets (which can be Treasury contracts).
 */
contract LittleCoinV2 is ERC20Capped, AccessControl, Pausable {
    using Address for address;

    // Roles
    bytes32 public constant FEE_ADMIN_ROLE      = keccak256("FEE_ADMIN_ROLE");
    bytes32 public constant WALLET_UPDATER_ROLE = keccak256("WALLET_UPDATER_ROLE");

    // Constants
    uint256 public constant INITIAL_SUPPLY = 1e9 * 1e18;
    uint16  public constant MAX_FEE_BP     = 1000; // 10%

    // Fee parameters (in basis points)
    uint16 public totalFeeBP;
    uint16 public burnFeeBP;
    uint16 public charityFeeBP;
    uint16 public liquidityFeeBP;
    uint16 public rewardFeeBP;

    // Category identifiers
    bytes32 private constant _CHARITY   = keccak256("CHARITY");
    bytes32 private constant _LIQUIDITY = keccak256("LIQUIDITY");
    bytes32 private constant _REWARD    = keccak256("REWARD");

    // Fee wallet addresses (can be EOAs or Treasury contracts)
    address public charityWallet;
    address public liquidityWallet;
    address public rewardWallet;

    // Exemptions
    mapping(address => bool) public isFeeExempt;

    // Events
    event FeeDistributed(address indexed sender, uint256 burnt, uint256 charity, uint256 liquidity, uint256 reward);
    event FeeUpdated(uint16 newTotalFeeBP);
    event FeeDistributionUpdated(uint16 burnBP, uint16 charityBP, uint16 liquidityBP, uint16 rewardBP);
    event CharityWalletUpdated(address indexed newWallet);
    event LiquidityWalletUpdated(address indexed newWallet);
    event RewardWalletUpdated(address indexed newWallet);

    constructor(
        address daoTimelock,
        address charity_,
        address liquidity_,
        address reward_,
        uint256 cap_
    )
        ERC20("LittleCoin", "LTC")
        ERC20Capped(cap_)
    {
        require(daoTimelock != address(0), "Zero DAO address");
        require(charity_ != address(0) && liquidity_ != address(0) && reward_ != address(0), "Zero wallet addr");
        require(cap_ >= INITIAL_SUPPLY, "Cap < initial supply");

        // Mint initial supply to deployer
        _mint(msg.sender, INITIAL_SUPPLY);

        // Set roles
        _grantRole(DEFAULT_ADMIN_ROLE, daoTimelock);
        _grantRole(FEE_ADMIN_ROLE, daoTimelock);
        _grantRole(WALLET_UPDATER_ROLE, daoTimelock);

        // Set initial fee params
        totalFeeBP     = 300;
        burnFeeBP      = 0;
        charityFeeBP   = 3000;
        liquidityFeeBP = 4000;
        rewardFeeBP    = 3000;

        // Set fee wallets
        charityWallet   = charity_;
        liquidityWallet = liquidity_;
        rewardWallet    = reward_;

        // Exempt Treasury contracts and DAO from fees
        isFeeExempt[charity_]          = true;
        isFeeExempt[liquidity_]        = true;
        isFeeExempt[reward_]           = true;
        isFeeExempt[daoTimelock]       = true;

        // Deployer renounces admin
        renounceRole(DEFAULT_ADMIN_ROLE, msg.sender);
        renounceRole(FEE_ADMIN_ROLE, msg.sender);
        renounceRole(WALLET_UPDATER_ROLE, msg.sender);
    }

    // ======== ERC20 Overrides ========
    function _beforeTokenTransfer(address from, address to, uint256 amount)
        internal override(ERC20) whenNotPaused
    {
        super._beforeTokenTransfer(from, to, amount);
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transferWithFee(msg.sender, recipient, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transferWithFee(sender, recipient, amount);
        uint256 currentAllowance = allowance(sender, msg.sender);
        require(currentAllowance >= amount, "Allowance exceeded");
        _approve(sender, msg.sender, currentAllowance - amount);
        return true;
    }

    // ======== Fee Logic ========
    function _transferWithFee(address sender, address recipient, uint256 amount) internal {
        if (isFeeExempt[sender] || totalFeeBP == 0) {
            _transfer(sender, recipient, amount);
            return;
        }

        uint256 feeAmount  = amount * totalFeeBP / 10000;
        uint256 sendAmount = amount - feeAmount;

        uint256 burnShare      = feeAmount * burnFeeBP    / 10000;
        uint256 charityShare   = feeAmount * charityFeeBP / 10000;
        uint256 liquidityShare = feeAmount * liquidityFeeBP / 10000;
        uint256 rewardShare    = feeAmount * rewardFeeBP  / 10000;

        uint256 totalShares = burnShare + charityShare + liquidityShare + rewardShare;
        if (feeAmount > totalShares) {
            charityShare += (feeAmount - totalShares);
        }

        if (burnShare > 0) _burn(sender, burnShare);

        if (charityShare > 0)   _sendFee(sender, charityWallet,   charityShare,   _CHARITY);
        if (liquidityShare > 0) _sendFee(sender, liquidityWallet, liquidityShare, _LIQUIDITY);
        if (rewardShare > 0)    _sendFee(sender, rewardWallet,    rewardShare,    _REWARD);

        _transfer(sender, recipient, sendAmount);

        emit FeeDistributed(sender, burnShare, charityShare, liquidityShare, rewardShare);
    }

    function _sendFee(address sender, address wallet, uint256 amount, bytes32 category) private {
        _transfer(sender, wallet, amount);
        if (wallet.isContract()) {
            ITreasury(wallet).deposit(category, amount);
        }
    }

    // ======== Admin Functions ========
    function setTotalFeeBP(uint16 feeBP) external onlyRole(FEE_ADMIN_ROLE) {
        require(feeBP <= MAX_FEE_BP, "Exceeds max fee");
        totalFeeBP = feeBP;
        emit FeeUpdated(feeBP);
    }

    function setFeeDistribution(
        uint16 burnBP,
        uint16 charityBP,
        uint16 liquidityBP,
        uint16 rewardBP
    ) external onlyRole(FEE_ADMIN_ROLE) {
        require(burnBP + charityBP + liquidityBP + rewardBP == 10000, "Invalid distribution");
        burnFeeBP      = burnBP;
        charityFeeBP   = charityBP;
        liquidityFeeBP = liquidityBP;
        rewardFeeBP    = rewardBP;
        emit FeeDistributionUpdated(burnBP, charityBP, liquidityBP, rewardBP);
    }

    function setFeeExempt(address account, bool exempt) external onlyRole(FEE_ADMIN_ROLE) {
        isFeeExempt[account] = exempt;
    }

    function updateCharityWallet(address newWallet) external onlyRole(WALLET_UPDATER_ROLE) {
        require(newWallet != address(0), "Zero address");
        // Remove exemption from old wallet (optional)
        isFeeExempt[charityWallet] = false;
        // Set and exempt new wallet
        charityWallet = newWallet;
        isFeeExempt[newWallet] = true;
        emit CharityWalletUpdated(newWallet);
    }

    function updateLiquidityWallet(address newWallet) external onlyRole(WALLET_UPDATER_ROLE) {
        require(newWallet != address(0), "Zero address");
        isFeeExempt[liquidityWallet] = false;
        liquidityWallet = newWallet;
        isFeeExempt[newWallet] = true;
        emit LiquidityWalletUpdated(newWallet);
    }

    function updateRewardWallet(address newWallet) external onlyRole(WALLET_UPDATER_ROLE) {
        require(newWallet != address(0), "Zero address");
        isFeeExempt[rewardWallet] = false;
        rewardWallet = newWallet;
        isFeeExempt[newWallet] = true;
        emit RewardWalletUpdated(newWallet);
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    function mint(address to, uint256 amount) external onlyRole(FEE_ADMIN_ROLE) {
        _mint(to, amount);
    }

    function supportsInterface(bytes4 interfaceId) public view override(AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
