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
        bytes32 mealHash;
        bytes32 pathTag;
        uint256 loggedAtBlock;
        uint8 mealType;
        bool active;
    }

    struct Path {
        bytes32 pathTag;
        uint256 startBlock;
        uint256 endBlock;
        uint256 participantCount;
        bool exists;
    }

    struct UserGoal {
        bytes32 goalHash;
        uint256 targetValue;
        uint256 setAtBlock;
    }

    uint256 public mealCounter;
    uint256 public pathCounter;
    uint256 public tipCounter;
    uint256 public pointsPerMeal;
    bool public companionPaused;

    mapping(uint256 => MealLog) public mealLogs;
    mapping(uint256 => Path) public paths;
    mapping(uint256 => bytes32) public tips;
    mapping(address => uint256) public pointsBalance;
    mapping(address => uint256) public dailyStreak;
    mapping(address => uint256) public lastLogBlock;
    mapping(address => uint256[]) private _mealIdsByUser;
    mapping(uint256 => address[]) private _pathParticipants;
    mapping(address => mapping(uint256 => bool)) private _userOnPath;
    mapping(address => UserGoal) public userGoals;
    mapping(bytes32 => bytes32) public pathTagLabels;
    mapping(bytes32 => uint256) public pathTagMealCount;
    mapping(address => mapping(bytes32 => uint256)) public userPathTagMealCount;
    mapping(uint256 => uint256) public pathMealCount;
    uint256 public dailySnapshotCounter;
    struct DailySnapshot {
        address user;
        uint256 dayBlock;
        uint256 mealCount;
        uint256 pointsEarned;
        bool exists;
    }
    mapping(uint256 => DailySnapshot) public dailySnapshots;
    mapping(address => uint256[]) private _snapshotIdsByUser;
    uint256[] private _allMealIds;
    uint256[] private _pathIds;
    uint256[] private _tipIds;
    bytes32[] private _pathTagsRegistered;
    uint256 private _reentrancyLock;

    // -------------------------------------------------------------------------
    // MODIFIERS
    // -------------------------------------------------------------------------

    modifier whenCompanionActive() {
        if (companionPaused) revert V3G_CompanionPaused();
        _;
    }

    modifier onlyPathCoordinator() {
        if (msg.sender != pathCoordinator) revert V3G_NotPathCoordinator();
        _;
    }

    modifier onlyRewardKeeper() {
        if (msg.sender != rewardKeeper) revert V3G_NotRewardKeeper();
        _;
    }

    modifier nonReentrant() {
        if (_reentrancyLock != 0) revert V3G_ReentrantCall();
        _reentrancyLock = 1;
        _;
        _reentrancyLock = 0;
    }

    // -------------------------------------------------------------------------
    // CONSTRUCTOR
    // -------------------------------------------------------------------------

    constructor() {
        pathCoordinator = address(0x7F3e9A2c4D6b8E0f1a3C5d7E9b0D2f4A6c8e1B3);
        rewardVault = address(0x9C1d4F6b8A0c2E5f7B9d1A4c6E8f0B2d4F6a8C0);
        rewardKeeper = address(0xB2d4F6a8C0e2B4d6F8a0C2e4B6d8F0a2C4e6B8);
        deployBlock = block.number;
        companionDomain = keccak256(abi.encodePacked("Veg3n_Companion", block.chainid, block.prevrandao, V3G_COMPANION_SALT));
        if (pathCoordinator == address(0) || rewardVault == address(0) || rewardKeeper == address(0)) revert V3G_ZeroAddress();
        pointsPerMeal = 50 * V3G_POINTS_SCALE;
    }

    // -------------------------------------------------------------------------
    // ADMIN
    // -------------------------------------------------------------------------

    function setCompanionPaused(bool paused) external onlyOwner {
        companionPaused = paused;
        emit CompanionPaused(paused, block.number);
    }

    function setPointsPerMeal(uint256 newPoints) external onlyOwner {
        pointsPerMeal = newPoints;
    }

    // -------------------------------------------------------------------------
    // PATHS
    // -------------------------------------------------------------------------

    function createPath(bytes32 pathTag, uint256 startBlock, uint256 endBlock) external onlyPathCoordinator whenCompanionActive returns (uint256 pathId) {
        if (startBlock >= endBlock) revert V3G_InvalidBlockRange();
        if (pathCounter >= V3G_MAX_PATHS) revert V3G_MaxPathsReached();
        pathId = ++pathCounter;
        _pathIds.push(pathId);
        paths[pathId] = Path({
            pathTag: pathTag,
            startBlock: startBlock,
            endBlock: endBlock,
            participantCount: 0,
            exists: true
        });
        emit PathCreated(pathId, pathTag, startBlock, endBlock, msg.sender, block.number);
    }

    function joinPath(uint256 pathId) external whenCompanionActive {
        if (pathId == 0 || pathId > pathCounter) revert V3G_PathNotFound();
        if (_userOnPath[msg.sender][pathId]) revert V3G_AlreadyOnPath();
        Path storage p = paths[pathId];
        if (!p.exists || block.number < p.startBlock || block.number > p.endBlock) revert V3G_PathNotActive();
        _userOnPath[msg.sender][pathId] = true;
        _pathParticipants[pathId].push(msg.sender);
        p.participantCount++;
        emit PathJoined(msg.sender, pathId, block.number);
    }

    function leavePath(uint256 pathId) external {
        if (pathId == 0 || pathId > pathCounter) revert V3G_PathNotFound();
        if (!_userOnPath[msg.sender][pathId]) revert V3G_NotOnPath();
        _userOnPath[msg.sender][pathId] = false;
        Path storage p = paths[pathId];
        if (p.participantCount > 0) p.participantCount--;
        emit PathLeft(msg.sender, pathId, block.number);
    }

    // -------------------------------------------------------------------------
    // MEAL LOGGING
    // -------------------------------------------------------------------------

    function logMeal(bytes32 mealHash, bytes32 pathTag, uint8 mealType) external nonReentrant whenCompanionActive returns (uint256 mealId) {
        if (mealHash == bytes32(0)) revert V3G_InvalidMealHash();
        if (mealType < V3G_MEAL_BREAKFAST || mealType > V3G_MEAL_SNACK) revert V3G_InvalidMealType();
        if (mealCounter >= V3G_MAX_MEALS) revert V3G_MaxMealsReached();
        mealId = ++mealCounter;
        mealLogs[mealId] = MealLog({
            user: msg.sender,
            mealHash: mealHash,
            pathTag: pathTag,
            loggedAtBlock: block.number,
            mealType: mealType,
            active: true
        });
        _mealIdsByUser[msg.sender].push(mealId);
        _allMealIds.push(mealId);
        pathTagMealCount[pathTag]++;
        userPathTagMealCount[msg.sender][pathTag]++;
        _updateStreak(msg.sender);
        emit MealLogged(mealId, msg.sender, mealHash, pathTag, block.number, mealType);
    }

    function _updateStreak(address user) internal {
        uint256 prevBlock = lastLogBlock[user];
        uint256 current = block.number;
        if (prevBlock == 0) {
            dailyStreak[user] = 1;
        } else {
            uint256 blocksSince = current - prevBlock;
            if (blocksSince <= 6500) dailyStreak[user] += 1;
            else dailyStreak[user] = 1;
        }
        lastLogBlock[user] = current;
        emit DailyStreakUpdated(user, dailyStreak[user], current);
    }

    function batchLogMeals(
        bytes32[] calldata mealHashes,
        bytes32[] calldata pathTags,
        uint8[] calldata mealTypes
    ) external nonReentrant whenCompanionActive returns (uint256[] memory mealIds) {
        uint256 n = mealHashes.length;
        if (n != pathTags.length || n != mealTypes.length) revert V3G_ArrayLengthMismatch();
        if (n == 0) revert V3G_ZeroBatchSize();
        if (n > V3G_MAX_BATCH_MEALS) revert V3G_BatchTooLarge();
        if (mealCounter + n > V3G_MAX_MEALS) revert V3G_MaxMealsReached();
        mealIds = new uint256[](n);
        for (uint256 i; i < n;) {
            if (mealHashes[i] == bytes32(0)) revert V3G_InvalidMealHash();
            if (mealTypes[i] < V3G_MEAL_BREAKFAST || mealTypes[i] > V3G_MEAL_SNACK) revert V3G_InvalidMealType();
            uint256 mealId = ++mealCounter;
            mealLogs[mealId] = MealLog({
                user: msg.sender,
                mealHash: mealHashes[i],
                pathTag: pathTags[i],
                loggedAtBlock: block.number,
                mealType: mealTypes[i],
                active: true
            });
            mealIds[i] = mealId;
            _mealIdsByUser[msg.sender].push(mealId);
            _allMealIds.push(mealId);
            pathTagMealCount[pathTags[i]]++;
            userPathTagMealCount[msg.sender][pathTags[i]]++;
            emit MealLogged(mealId, msg.sender, mealHashes[i], pathTags[i], block.number, mealTypes[i]);
            unchecked { ++i; }
        }
        _updateStreak(msg.sender);
        emit BatchMealsLogged(mealIds, msg.sender, block.number);
    }

    // -------------------------------------------------------------------------
    // GOALS
    // -------------------------------------------------------------------------

    function setGoal(bytes32 goalHash, uint256 targetValue) external whenCompanionActive {
        if (goalHash == bytes32(0)) revert V3G_InvalidMealHash();
        UserGoal storage g = userGoals[msg.sender];
        uint256 prev = g.targetValue;
        g.goalHash = goalHash;
        g.targetValue = targetValue;
        g.setAtBlock = block.number;
        if (prev == 0) emit GoalSet(msg.sender, goalHash, targetValue, block.number);
        else emit GoalUpdated(msg.sender, goalHash, prev, targetValue, block.number);
    }

    // -------------------------------------------------------------------------
    // POINTS
    // -------------------------------------------------------------------------

    function awardPoints(address user, uint256 amount) external onlyRewardKeeper nonReentrant {
        if (user == address(0)) revert V3G_ZeroAddress();
        if (amount == 0) revert V3G_ZeroAmount();
        pointsBalance[user] += amount;
        emit PointsAwarded(user, amount, pointsBalance[user], block.number);
    }

    function awardPointsForMeal(uint256 mealId) external onlyRewardKeeper nonReentrant {
        if (mealId == 0 || mealId > mealCounter) revert V3G_MealNotFound();
        MealLog storage m = mealLogs[mealId];
        if (!m.active) revert V3G_MealNotFound();
        pointsBalance[m.user] += pointsPerMeal;
        emit PointsAwarded(m.user, pointsPerMeal, pointsBalance[m.user], block.number);
    }

    function redeemPoints(uint256 amount, bytes32 reasonHash) external nonReentrant {
        if (amount == 0) revert V3G_ZeroAmount();
        if (pointsBalance[msg.sender] < amount) revert V3G_InsufficientPoints();
        pointsBalance[msg.sender] -= amount;
        emit PointsRedeemed(msg.sender, amount, reasonHash, block.number);
    }

    // -------------------------------------------------------------------------
    // TIPS (AI healthy eating tips)
    // -------------------------------------------------------------------------

    function recordTip(bytes32 tipHash) external onlyPathCoordinator whenCompanionActive returns (uint256 tipId) {
        if (tipHash == bytes32(0)) revert V3G_InvalidMealHash();
        if (tipCounter >= V3G_MAX_TIPS) revert V3G_MaxTipsReached();
        tipId = ++tipCounter;
        tips[tipId] = tipHash;
        _tipIds.push(tipId);
        emit TipRecorded(tipId, tipHash, msg.sender, block.number);
    }

    function setPathTagLabel(bytes32 pathTag, bytes32 labelHash) external onlyPathCoordinator {
        if (labelHash == bytes32(0)) revert V3G_InvalidLabelHash();
        pathTagLabels[pathTag] = labelHash;
        if (pathTagMealCount[pathTag] == 0) _pathTagsRegistered.push(pathTag);
        emit PathTagLabelSet(pathTag, labelHash, block.number);
    }

    function recordDailySnapshot(address user, uint256 dayBlock, uint256 mealCount, uint256 pointsEarned) external onlyRewardKeeper returns (uint256 snapshotId) {
        if (dailySnapshotCounter >= V3G_MAX_DAILY_SNAPSHOTS) return 0;
        snapshotId = ++dailySnapshotCounter;
        dailySnapshots[snapshotId] = DailySnapshot({
            user: user,
            dayBlock: dayBlock,
            mealCount: mealCount,
            pointsEarned: pointsEarned,
            exists: true
        });
        _snapshotIdsByUser[user].push(snapshotId);
    }

    function removeMeal(uint256 mealId) external {
        if (mealId == 0 || mealId > mealCounter) revert V3G_MealNotFound();
        MealLog storage m = mealLogs[mealId];
        if (!m.active) revert V3G_MealAlreadyRemoved();
        if (m.user != msg.sender && msg.sender != rewardKeeper) revert V3G_NotMealUser();
        m.active = false;
        emit MealRemoved(mealId, msg.sender, block.number);
    }

    function batchAwardPoints(address[] calldata users, uint256[] calldata amounts) external onlyRewardKeeper nonReentrant {
        uint256 n = users.length;
        if (n != amounts.length) revert V3G_ArrayLengthMismatch();
        if (n == 0) revert V3G_ZeroBatchSize();
        for (uint256 i; i < n;) {
            if (users[i] != address(0) && amounts[i] > 0) {
                pointsBalance[users[i]] += amounts[i];
                emit PointsAwarded(users[i], amounts[i], pointsBalance[users[i]], block.number);
            }
            unchecked { ++i; }
        }
        emit BatchPointsAwarded(users, amounts, block.number);
    }

    // -------------------------------------------------------------------------
    // VIEWS
    // -------------------------------------------------------------------------

    function getMeal(uint256 mealId) external view returns (
        address user,
        bytes32 mealHash,
        bytes32 pathTag,
        uint256 loggedAtBlock,
        uint8 mealType,
