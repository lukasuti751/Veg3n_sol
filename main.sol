// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * On-chain companion for AI-driven healthy eating: meal logs, nutrition goals and daily paths.
 * Path coordinator and reward vault are set at deploy; suitable for mainnet with ReentrancyGuard and Pausable.
 */

import "https://raw.githubusercontent.com/OpenZeppelin/openzeppelin-contracts/v4.9.6/contracts/security/ReentrancyGuard.sol";
import "https://raw.githubusercontent.com/OpenZeppelin/openzeppelin-contracts/v4.9.6/contracts/security/Pausable.sol";
import "https://raw.githubusercontent.com/OpenZeppelin/openzeppelin-contracts/v4.9.6/contracts/access/Ownable.sol";

contract Veg3n is ReentrancyGuard, Pausable, Ownable {

    // -------------------------------------------------------------------------
    // EVENTS
    // -------------------------------------------------------------------------

    event MealLogged(
        uint256 indexed mealId,
        address indexed user,
        bytes32 mealHash,
        bytes32 indexed pathTag,
        uint256 loggedAtBlock,
        uint8 mealType
    );
    event GoalSet(
        address indexed user,
        bytes32 goalHash,
        uint256 targetValue,
        uint256 atBlock
    );
    event GoalUpdated(
        address indexed user,
        bytes32 indexed goalHash,
        uint256 previousTarget,
        uint256 newTarget,
        uint256 atBlock
    );
    event PathJoined(
        address indexed user,
        uint256 indexed pathId,
        uint256 atBlock
    );
    event PathLeft(address indexed user, uint256 indexed pathId, uint256 atBlock);
    event PathCreated(
        uint256 indexed pathId,
        bytes32 pathTag,
        uint256 startBlock,
        uint256 endBlock,
        address indexed createdBy,
        uint256 atBlock
    );
    event PointsAwarded(address indexed user, uint256 amount, uint256 totalPoints, uint256 atBlock);
    event PointsRedeemed(address indexed user, uint256 amount, bytes32 indexed reasonHash, uint256 atBlock);
    event TipRecorded(uint256 indexed tipId, bytes32 tipHash, address indexed recordedBy, uint256 atBlock);
    event DailyStreakUpdated(address indexed user, uint256 streakDays, uint256 atBlock);
    event CompanionPaused(bool paused, uint256 atBlock);
    event RewardVaultTopped(uint256 amountWei, uint256 atBlock);
    event BatchMealsLogged(uint256[] mealIds, address indexed user, uint256 atBlock);
    event MealRemoved(uint256 indexed mealId, address indexed removedBy, uint256 atBlock);
    event PathTagLabelSet(bytes32 indexed pathTag, bytes32 labelHash, uint256 atBlock);
    event BatchPointsAwarded(address[] users, uint256[] amounts, uint256 atBlock);

    // -------------------------------------------------------------------------
    // ERRORS
