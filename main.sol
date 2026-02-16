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
    uint256 public constant BPS_DENOM = 10000;
    bytes32 public constant ROLLA_DOMAIN = bytes32(uint256(0x4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f));
    uint256 public constant GELATO_BONUS_BPS = 0;
    uint256 public constant OG_KUSH_MAX_BET_BPS = 10000;
    uint256 public constant STRAIN_POINT_4 = 4;
    uint256 public constant STRAIN_POINT_5 = 5;
    uint256 public constant STRAIN_POINT_6 = 6;
    uint256 public constant STRAIN_POINT_8 = 8;
    uint256 public constant STRAIN_POINT_9 = 9;
    uint256 public constant STRAIN_POINT_10 = 10;

    uint8 public constant OUTCOME_NONE = 0;
    uint8 public constant OUTCOME_NATURAL = 1;
    uint8 public constant OUTCOME_CRAPS = 2;
    uint8 public constant OUTCOME_POINT_SET = 3;
    uint8 public constant OUTCOME_POINT_WIN = 4;
    uint8 public constant OUTCOME_SEVEN_OUT = 5;

    address public immutable rollaHouse;
    address public immutable rollaVault;
    uint256 public immutable genesisBlock;
    bytes32 public immutable rngSeed;

    uint256 public totalWagered;
    uint256 public totalPayouts;
    uint256 public totalHandsWon;
    uint256 public totalHandsLost;
    uint256 public vaultBalance;
    uint256 public houseEdgeCollected;

    struct Hand {
        uint256 betWei;
        uint8 stage;
        uint8 pointValue;
        uint256 nonce;
    }
    mapping(address => Hand) private _hands;

    modifier onlyHouse() {
        if (msg.sender != rollaHouse) revert RollaErr_NotHouse();
        _;
    }

    modifier onlyVault() {
        if (msg.sender != rollaVault) revert RollaErr_NotVault();
        _;
    }

    constructor() {
        rollaHouse = address(0xF2a8E5b1C9d4e7A0c3B6f9D2e5a8C1b4F7d0E3);
        rollaVault = address(0x6D1c9E4a7F0b3B8e2A5d6C9f1E4a7b0D3c8F2);
        genesisBlock = block.number;
        rngSeed = keccak256(abi.encodePacked(block.timestamp, block.prevrandao, block.chainid, "high_rolla"));
        totalWagered = 0;
        totalPayouts = 0;
        totalHandsWon = 0;
        totalHandsLost = 0;
        vaultBalance = 0;
        houseEdgeCollected = 0;
    }

    function topVault() external payable whenNotPaused {
        if (msg.value == 0) return;
        vaultBalance += msg.value;
        emit VaultTopped(msg.value, msg.sender, vaultBalance);
    }

    function _rollTwoDice(uint256 nonce) private view returns (uint8 d1, uint8 d2, uint8 sum) {
        bytes32 h = keccak256(abi.encodePacked(rngSeed, block.prevrandao, block.timestamp, block.number, msg.sender, nonce));
        d1 = uint8(uint256(h) % DICE_SIDES) + 1;
        d2 = uint8(uint256(keccak256(abi.encodePacked(h, nonce))) % DICE_SIDES) + 1;
        sum = d1 + d2;
    }

    function rollComeOut() external payable whenNotPaused nonReentrant {
        Hand storage h = _hands[msg.sender];
        if (h.stage == 1) revert RollaErr_HandInProgress();
        if (msg.value < MIN_BET_WEI) revert RollaErr_BetTooLow();
        if (msg.value > MAX_BET_WEI) revert RollaErr_BetTooHigh();

        uint256 payoutIfWin = (msg.value * PAYOUT_MULTIPLIER_BPS) / BPS_DENOM;
        if (payoutIfWin > address(this).balance) revert RollaErr_VaultInsufficient();

        vaultBalance += msg.value;
        totalWagered += msg.value;
        h.betWei = msg.value;
        h.nonce = block.number + block.timestamp;
        (uint8 d1, uint8 d2, uint8 sum) = _rollTwoDice(h.nonce);

        if (sum == NATURAL_SUM_ONE || sum == NATURAL_SUM_TWO) {
            uint256 payout = (msg.value * PAYOUT_MULTIPLIER_BPS) / BPS_DENOM;
            uint256 edge = (msg.value * HOUSE_EDGE_BPS) / BPS_DENOM;
            houseEdgeCollected += edge;
            vaultBalance -= payout;
            totalPayouts += payout;
            totalHandsWon += 1;
            h.stage = 0;
            h.betWei = 0;
            emit ComeOutRolled(msg.sender, msg.value, d1, d2, sum, OUTCOME_NATURAL);
            emit HandWon(msg.sender, msg.value, payout, block.number);
            (bool ok,) = payable(msg.sender).call{value: payout}("");
            if (!ok) revert RollaErr_TransferFailed();
            return;
        }
        if (sum == CRAPS_SUM_LOW || sum == CRAPS_SUM_MID || sum == CRAPS_SUM_HIGH) {
            totalHandsLost += 1;
            h.stage = 0;
            h.betWei = 0;
            emit ComeOutRolled(msg.sender, msg.value, d1, d2, sum, OUTCOME_CRAPS);
            emit HandLost(msg.sender, msg.value, block.number);
            return;
        }
        h.stage = 1;
        h.pointValue = sum;
        emit ComeOutRolled(msg.sender, msg.value, d1, d2, sum, OUTCOME_POINT_SET);
        emit PointSet(msg.sender, sum, block.number);
    }

    function rollPoint() external whenNotPaused nonReentrant {
        Hand storage h = _hands[msg.sender];
        if (h.stage != 1) revert RollaErr_NotPointPhase();
        uint256 betWei = h.betWei;
        uint256 nonce = h.nonce + block.number;
        (uint8 d1, uint8 d2, uint8 sum) = _rollTwoDice(nonce);
        h.nonce = nonce;

        if (sum == NATURAL_SUM_ONE) {
            houseEdgeCollected += betWei;
            vaultBalance += betWei;
            totalHandsLost += 1;
            h.stage = 0;
            h.betWei = 0;
            emit PointRolled(msg.sender, d1, d2, sum, OUTCOME_SEVEN_OUT);
            emit HandLost(msg.sender, betWei, block.number);
            return;
        }
        if (sum == h.pointValue) {
            uint256 payout = (betWei * PAYOUT_MULTIPLIER_BPS) / BPS_DENOM;
            uint256 edge = (betWei * HOUSE_EDGE_BPS) / BPS_DENOM;
            houseEdgeCollected += edge;
            vaultBalance -= payout;
            totalPayouts += payout;
            totalHandsWon += 1;
            h.stage = 0;
            h.betWei = 0;
            emit PointRolled(msg.sender, d1, d2, sum, OUTCOME_POINT_WIN);
            emit HandWon(msg.sender, betWei, payout, block.number);
            (bool ok,) = payable(msg.sender).call{value: payout}("");
            if (!ok) revert RollaErr_TransferFailed();
        }
    }

    function getHand(address player) external view returns (uint256 betWei, uint8 stage, uint8 pointValue) {
        Hand storage h = _hands[player];
        return (h.betWei, h.stage, h.pointValue);
    }

    function getTableStats() external view returns (
        uint256 wagered,
        uint256 payouts,
        uint256 handsWon,
        uint256 handsLost,
