// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./PoolManager.sol";

/**
 * @title ScoreManager
 * @dev Manages user credit scores and calculates dynamic borrowing limits.
 */
contract ScoreManager is Ownable {
    PoolManager public poolManager;

    // Minimum score starts at 300 (Like FICO)
    uint256 public constant MIN_SCORE = 300;
    uint256 public constant MAX_SCORE = 850;

    mapping(address => uint256) public scores;
    mapping(address => uint256) public totalRepaidMap;

    event ScoreUpdated(address indexed user, uint256 newScore, string reason);

    constructor(address _poolManager) Ownable(msg.sender) {
        poolManager = PoolManager(_poolManager);
    }

    /**
     * @dev Gets the user's current credit score. Returns MIN_SCORE if new user.
     */
    function getScore(address user) public view returns (uint256) {
        uint256 score = scores[user];
        if (score == 0) return MIN_SCORE;
        return score;
    }

    /**
     * @dev Updates user score based on repayment behavior.
     * Can only be called by LoanEngine (Owner or specialized role in prod).
     */
    function updateScore(address user, int256 delta, string memory reason) public onlyOwner {
        uint256 current = getScore(user);
        int256 newScore = int256(current) + delta;

        if (newScore < int256(MIN_SCORE)) newScore = int256(MIN_SCORE);
        if (newScore > int256(MAX_SCORE)) newScore = int256(MAX_SCORE);

        scores[user] = uint256(newScore);
        emit ScoreUpdated(user, uint256(newScore), reason);
    }

    /**
     * @dev Records a successful repayment.
     * Logic: +5 points for every $100 repaid, max +20 per transaction.
     */
    function recordRepayment(address user, uint256 amount) external onlyOwner {
        totalRepaidMap[user] += amount;
        
        // Simple heuristic: Boost score based on volume
        // In real system, this would be more complex (on-time vs late)
        // Here we just give small boost for activity
        
        // 10 points for every repayment (activity bonus)
        // capped at decent intervals
        updateScore(user, 5, "Repayment Bonus");
    }

    /**
     * @dev Calculates the max borrow amount for a user.
     * Formula: Collateral * (Score / 1000) multiplier.
     * E.g. $1000 Collat * (300/1000) = $300 limit (30% LTV)
     * E.g. $1000 Collat * (800/1000) = $800 limit (80% LTV)
     */
    /**
     * @dev Calculates the max borrow amount for a user.
     * Formula: Total Aggregated Collateral * (Score / 1000).
     * This sums liquidity across all chains (Base, Arbitrum, Sepolia) as verified by PoolManager.
     */
    function getCreditLimit(address user) public view returns (uint256) {
        // 1. Get user total aggregated collateral across all chains/tokens from PoolManager
        uint256 totalCollateral = poolManager.getUserTotalCollateral(user);
        
        if (totalCollateral == 0) return 0;

        uint256 score = getScore(user);
        
        // Multiplier: Score / 1000
        // E.g. $1000 Total Value * (300/1000) = $300 Global limit
        return (totalCollateral * score) / 1000;
    }
}
