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
    // -------------------------------------------------------------------------

    error V3G_ZeroAddress();
    error V3G_InvalidMealId();
    error V3G_MealNotFound();
    error V3G_InvalidMealHash();
    error V3G_InvalidPathTag();
    error V3G_NotPathCoordinator();
    error V3G_NotRewardKeeper();
    error V3G_CompanionPaused();
    error V3G_ReentrantCall();
    error V3G_TransferFailed();
    error V3G_ZeroAmount();
    error V3G_InsufficientPoints();
    error V3G_MaxMealsReached();
    error V3G_ArrayLengthMismatch();
    error V3G_BatchTooLarge();
    error V3G_ZeroBatchSize();
    error V3G_PathNotFound();
    error V3G_PathNotActive();
    error V3G_AlreadyOnPath();
    error V3G_NotOnPath();
    error V3G_MaxPathsReached();
    error V3G_InvalidBlockRange();
    error V3G_InvalidMealType();
    error V3G_InvalidTargetValue();
    error V3G_TipNotFound();
    error V3G_MaxTipsReached();
    error V3G_NotMealUser();
    error V3G_MealAlreadyRemoved();
    error V3G_InvalidLabelHash();

    // -------------------------------------------------------------------------
    // CONSTANTS
    // -------------------------------------------------------------------------

    uint256 public constant V3G_BPS_BASE = 10000;
    uint256 public constant V3G_MAX_MEALS = 3200;
    uint256 public constant V3G_MAX_PATHS = 110;
    uint256 public constant V3G_MAX_TIPS = 450;
    uint256 public constant V3G_MAX_BATCH_MEALS = 42;
    uint256 public constant V3G_POINTS_SCALE = 1e18;
    uint256 public constant V3G_COMPANION_SALT = 0x2F7b4E9a1C6d0F3b5E8a2C7d1F4b6E9a3C8d2F5;
    uint8 public constant V3G_MEAL_BREAKFAST = 1;
    uint8 public constant V3G_MEAL_LUNCH = 2;
    uint8 public constant V3G_MEAL_DINNER = 3;
    uint8 public constant V3G_MEAL_SNACK = 4;
    uint256 public constant V3G_MAX_DAILY_SNAPSHOTS = 5000;
    uint256 public constant V3G_BLOCKS_PER_DAY_EST = 7200;

    // -------------------------------------------------------------------------
    // IMMUTABLES
    // -------------------------------------------------------------------------

    address public immutable pathCoordinator;
    address public immutable rewardVault;
    address public immutable rewardKeeper;
    uint256 public immutable deployBlock;
    bytes32 public immutable companionDomain;

    // -------------------------------------------------------------------------
    // STATE
    // -------------------------------------------------------------------------

    struct MealLog {
        address user;
