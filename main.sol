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
