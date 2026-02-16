// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title High Rolla
/// @notice On-chain craps table with a cannabis twist. Place your bet, roll the come-out; naturals and craps resolve instantly. Point rounds roll until you hit or seven out. All limits and house addresses fixed at deploy.
/// @dev RNG from block prevrandao and nonce; no user-supplied entropy. House and vault are immutable. Safe for EVM mainnets.

import "https://raw.githubusercontent.com/OpenZeppelin/openzeppelin-contracts/v4.9.6/contracts/security/ReentrancyGuard.sol";
import "https://raw.githubusercontent.com/OpenZeppelin/openzeppelin-contracts/v4.9.6/contracts/utils/Pausable.sol";

contract HighRolla is ReentrancyGuard, Pausable {

    event ComeOutRolled(
        address indexed player,
        uint256 betWei,
        uint8 die1,
        uint8 die2,
        uint8 sum,
        uint8 outcome
    );
    event PointSet(address indexed player, uint8 pointValue, uint256 atBlock);
    event PointRolled(
        address indexed player,
        uint8 die1,
        uint8 die2,
        uint8 sum,
        uint8 outcome
    );
    event HandWon(address indexed player, uint256 betWei, uint256 payoutWei, uint256 atBlock);
    event HandLost(address indexed player, uint256 betWei, uint256 atBlock);
    event VaultTopped(uint256 amount, address indexed from, uint256 newBalance);
    event HouseEdgeTaken(uint256 amount, uint256 atBlock);

    error RollaErr_NoActiveHand();
    error RollaErr_HandInProgress();
    error RollaErr_BetTooLow();
    error RollaErr_BetTooHigh();
    error RollaErr_NotHouse();
    error RollaErr_NotVault();
    error RollaErr_ZeroAmount();
    error RollaErr_TransferFailed();
    error RollaErr_NotPointPhase();
    error RollaErr_VaultInsufficient();

    uint256 public constant MIN_BET_WEI = 0.001 ether;
    uint256 public constant MAX_BET_WEI = 10 ether;
    uint256 public constant DICE_SIDES = 6;
    uint256 public constant NATURAL_SUM_ONE = 7;
    uint256 public constant NATURAL_SUM_TWO = 11;
    uint256 public constant CRAPS_SUM_LOW = 2;
    uint256 public constant CRAPS_SUM_MID = 3;
    uint256 public constant CRAPS_SUM_HIGH = 12;
    uint256 public constant PAYOUT_MULTIPLIER_BPS = 19800;
    uint256 public constant HOUSE_EDGE_BPS = 200;
