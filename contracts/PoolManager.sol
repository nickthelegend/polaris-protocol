// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/INativeQueryVerifier.sol";
import "./interfaces/EvmV1Decoder.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract PoolManager is Ownable, ReentrancyGuard {
    INativeQueryVerifier public immutable VERIFIER;
    address public loanEngine;
    bytes32 public constant TRANSFER_EVENT_SIGNATURE = 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef;

    struct Pool { uint256 totalLiquidity; address tokenOnSource; }
    mapping(address => Pool) public pools;
    mapping(address => mapping(address => uint256)) public lpBalance;
    mapping(bytes32 => bool) public processedQueries;
    mapping(uint64 => mapping(address => bool)) public whitelistedVaults;
    address[] public whitelistedTokens;
    mapping(address => bool) public isTokenWhitelisted;
    uint256 public withdrawalNonce;

    event LiquidityAdded(address indexed user, address indexed tokenOnSource, uint256 amount);
    event LiquidityWithdrawn(address indexed user, address indexed tokenOnSource, uint256 amount);
    event WithdrawalAuthorized(address indexed user, address indexed tokenOnSource, uint256 amount, uint256 nonce, uint64 destChainId);
    event LiquiditySlashed(address indexed user, address indexed tokenOnSource, uint256 amount);
    event VaultWhitelisted(uint64 indexed chainId, address indexed vault, bool status);
    event TokenWhitelisted(address indexed token, bool status);

    constructor(address _verifier) Ownable(msg.sender) {
        if (_verifier == address(0)) {
            VERIFIER = NativeQueryVerifierLib.getVerifier();
        } else {
            VERIFIER = INativeQueryVerifier(_verifier);
        }
    }

    function setWhitelistedToken(address token, bool status) external onlyOwner {
        if (status && !isTokenWhitelisted[token]) whitelistedTokens.push(token);
        isTokenWhitelisted[token] = status;
        emit TokenWhitelisted(token, status);
    }

    function setWhitelistedVault(uint64 chainId, address vault, bool status) external onlyOwner {
        whitelistedVaults[chainId][vault] = status;
        emit VaultWhitelisted(chainId, vault, status);
    }

    function setLoanEngine(address _loanEngine) external onlyOwner { loanEngine = _loanEngine; }

    function addLiquidityFromProof(
        uint64 chainKey, uint64 blockHeight, bytes calldata encodedTransaction,
        bytes32 merkleRoot, INativeQueryVerifier.MerkleProofEntry[] calldata siblings,
        bytes32 lowerEndpointDigest, bytes32[] calldata continuityRoots
    ) external nonReentrant {
        (bool isNotReplay, bytes32 txKey) = _checkForReplay(chainKey, blockHeight, siblings);
        require(isNotReplay, "Transaction already processed");

        require(VERIFIER.verifyAndEmit(
            chainKey, blockHeight, encodedTransaction,
            INativeQueryVerifier.MerkleProof({root: merkleRoot, siblings: siblings}),
            INativeQueryVerifier.ContinuityProof({lowerEndpointDigest: lowerEndpointDigest, roots: continuityRoots})
        ), "Native verification failed");

        EvmV1Decoder.ReceiptFields memory receipt = EvmV1Decoder.decodeReceiptFields(encodedTransaction);
        require(receipt.receiptStatus == 1, "Transaction failed on source chain");

        EvmV1Decoder.LogEntry[] memory logs = EvmV1Decoder.getLogsByEventSignature(receipt, TRANSFER_EVENT_SIGNATURE);
        require(logs.length > 0, "No Transfer events found");

        bool processed = false;
        for (uint i = 0; i < logs.length; i++) {
            address vault = logs[i].address_;
            if (whitelistedVaults[chainKey][vault]) {
                require(logs[i].topics.length == 3, "Invalid topics");
                address lender = address(uint160(uint256(logs[i].topics[1])));
                address toAddr = address(uint160(uint256(logs[i].topics[2])));
                if (uint160(toAddr) < 128) {
                    uint256 amount = abi.decode(logs[i].data, (uint256));
                    pools[vault].totalLiquidity += amount;
                    lpBalance[lender][vault] += amount;
                    processed = true;
                    emit LiquidityAdded(lender, vault, amount);
                    break;
                }
            }
        }
        require(processed, "No valid burn found");
        processedQueries[txKey] = true;
    }

    function _checkForReplay(uint64 chainKey, uint64 blockHeight, INativeQueryVerifier.MerkleProofEntry[] memory siblings) 
        internal view returns (bool, bytes32 txKey) 
    {
        uint256 transactionIndex = NativeQueryVerifierLib._calculateTransactionIndex(siblings);
        txKey = keccak256(abi.encodePacked(chainKey, blockHeight, transactionIndex));
        return (!processedQueries[txKey], txKey);
    }

    function getUserTotalCollateral(address user) public view returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < whitelistedTokens.length; i++) {
            if (isTokenWhitelisted[whitelistedTokens[i]]) total += lpBalance[user][whitelistedTokens[i]];
        }
        return total;
    }

    function requestWithdrawal(address tokenOnSource, uint256 amount, uint64 destChainId) external nonReentrant {
        require(lpBalance[msg.sender][tokenOnSource] >= amount, "Insufficient LP balance");
        lpBalance[msg.sender][tokenOnSource] -= amount;
        pools[tokenOnSource].totalLiquidity -= amount;
        emit WithdrawalAuthorized(msg.sender, tokenOnSource, amount, withdrawalNonce, destChainId);
        withdrawalNonce++;
        emit LiquidityWithdrawn(msg.sender, tokenOnSource, amount);
    }

    function slashLiquidity(address user, address token, uint256 amount) external {
        require(msg.sender == loanEngine, "Only LoanEngine");
        uint256 slashAmount = amount > lpBalance[user][token] ? lpBalance[user][token] : amount;
        lpBalance[user][token] -= slashAmount;
        emit LiquiditySlashed(user, token, slashAmount);
    }

    function getPoolLiquidity(address token) external view returns (uint256) {
        return pools[token].totalLiquidity;
    }
}
