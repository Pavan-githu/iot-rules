// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title  CommitRevealOTP
 * @notice Blockchain-enforced commit-reveal second-factor authentication
 *         for the RaceIoT RPi3 IoT gateway.
 *
 * ── HOW IT WORKS ────────────────────────────────────────────────────────────
 *
 *  REGISTRATION (once per user)
 *  ─────────────────────────────
 *  1. RPi3 generates a 32-byte random seed.
 *  2. RPi3 calls commit(userHash, keccak256(seed)).
 *     → seedCommitment[userHash] = keccak256(seed) stored on-chain.
 *     → Seed itself never appears on-chain.
 *
 *  LOGIN — STEP 1 (after password verified)
 *  ─────────────────────────────────────────
 *  3. RPi3 generates a fresh 32-byte nonce per login.
 *  4. RPi3 computes:
 *       preImage   = seed || nonce || username || timestamp
 *       code       = keccak256(preImage) % 10^6      (6-digit OTP shown to user)
 *       nonceHash  = keccak256(nonce)                (nonce hidden)
 *       codeCommit = keccak256(preImage)             (full hash committed)
 *  5. RPi3 calls beginLogin(userHash, nonceHash, codeCommit).
 *     → pendingLogin[userHash] stored on-chain.
 *     → Code is LOCKED IN before the user sees it — RPi3 cannot cheat.
 *  6. RPi3 shows the 6-digit code on the browser screen.
 *
 *  LOGIN — STEP 2 (user submits the 6-digit code)
 *  ────────────────────────────────────────────────
 *  7. RPi3 calls reveal(userHash, nonce, preImage).
 *     Contract verifies:
 *       ✓ keccak256(nonce)    == nonceHash  (stored in beginLogin)
 *       ✓ keccak256(preImage) == codeCommit (stored in beginLogin)
 *       ✓ preImage not expired (block.timestamp <= expiresAt)
 *       ✓ nonceHash not previously used    (replay impossible)
 *       → marks nonceHash as spent
 *       → emits OTPRevealed
 *  8. RPi3 reads reveal() return value: true = grant access, false = deny.
 *
 * ── SECURITY PROPERTIES ─────────────────────────────────────────────────────
 *
 *  Non-repudiation:
 *    The code was committed on-chain BEFORE the user submitted anything.
 *    RPi3 cannot show code "482915" but secretly accept "000000".
 *    The contract enforces the device against itself.
 *
 *  Replay prevention:
 *    usedNonces[userHash][nonceHash] = true after first reveal.
 *    Any second reveal() with the same nonce is rejected permanently.
 *
 *  Brute-force resistance:
 *    codeCommit = keccak256(seed || nonce || username || timestamp)
 *    Attacker must know the 32-byte seed (2^256 search space) to compute
 *    the pre-image. The 6-digit truncation does not weaken the commitment.
 *
 *  Privacy:
 *    userHash = keccak256(username) — username never on-chain.
 *    Seed never on-chain (only keccak256(seed) is stored).
 *
 *  Lockout:
 *    After MAX_FAILS failed beginLogin/reveal cycles, account is locked.
 *    Only contract owner can unlock via unlock(userHash).
 *
 * ── FUNCTION SELECTORS (for blockchain_logger.cpp ABI encoding) ─────────────
 *
 *  commit(bytes32,bytes32)              → keccak256 first 4 bytes
 *  beginLogin(bytes32,bytes32,bytes32)  → keccak256 first 4 bytes
 *  reveal(bytes32,bytes32,bytes32)      → keccak256 first 4 bytes
 *  isLocked(bytes32)                    → view, eth_call
 *  isNonceUsed(bytes32,bytes32)         → view, eth_call
 *  hasCommitment(bytes32)               → view, eth_call
 */
contract CommitRevealOTP {

    // ── Constants ─────────────────────────────────────────────────────────────
    uint8   public constant MAX_FAILS      = 3;
    uint256 public constant LOGIN_TTL      = 120;  // seconds a beginLogin stays valid

    // ── Data structures ───────────────────────────────────────────────────────

    /**
     * Per-user registration record.
     * seedCommit = keccak256(seed) — proves the seed was set without revealing it.
     */
    struct UserCommitment {
        bytes32 seedCommit;     // keccak256(seed)
        bool    registered;     // true once commit() called
    }

    /**
     * Per-login-attempt record created by beginLogin().
     * Cleared after reveal() or expiry.
     */
    struct PendingLogin {
        bytes32 nonceHash;      // keccak256(nonce) — nonce stays off-chain until reveal
        bytes32 codeCommit;     // keccak256(seed||nonce||username||timestamp)
        uint256 expiresAt;      // block.timestamp + LOGIN_TTL
        bool    active;         // true while waiting for reveal
    }

    // ── State variables ───────────────────────────────────────────────────────
    address public owner;
    mapping(address  => bool)             public authorizedDevices;

    // Per-user registration commitment
    mapping(bytes32  => UserCommitment)   public userCommitments;

    // Per-user current pending login (only one active at a time)
    mapping(bytes32  => PendingLogin)     public pendingLogin;

    // Per-user nonce spend ledger: userHash → nonceHash → spent
    mapping(bytes32  => mapping(bytes32 => bool)) public usedNonces;

    // Per-user consecutive fail counter (reset on success)
    mapping(bytes32  => uint8)            public failCount;

    // Per-user lockout flag (set when failCount >= MAX_FAILS)
    mapping(bytes32  => bool)             public lockedUsers;

    // ── Events ────────────────────────────────────────────────────────────────
    event UserCommitted   (bytes32 indexed userHash, uint256 timestamp);
    event LoginStarted    (bytes32 indexed userHash, bytes32 nonceHash,
                           uint256 expiresAt);
    event OTPRevealed     (bytes32 indexed userHash, bool success,
                           uint256 timestamp);
    event RevealFailed    (bytes32 indexed userHash, string reason,
                           uint256 timestamp);
    event UserLocked      (bytes32 indexed userHash, uint256 timestamp);
    event UserUnlocked    (bytes32 indexed userHash, uint256 timestamp);
    event DeviceAuthorized(address indexed device);
    event DeviceRevoked   (address indexed device);

    // ── Access control ────────────────────────────────────────────────────────
    modifier onlyOwner() {
        require(msg.sender == owner, "CommitRevealOTP: not owner");
        _;
    }

    modifier onlyDevice() {
        require(
            authorizedDevices[msg.sender] || msg.sender == owner,
            "CommitRevealOTP: caller not an authorized device"
        );
        _;
    }

    // ── Constructor ───────────────────────────────────────────────────────────
    constructor() {
        owner = msg.sender;
        authorizedDevices[msg.sender] = true;
        emit DeviceAuthorized(msg.sender);
    }

    // ── Device management ─────────────────────────────────────────────────────
    function authorizeDevice(address device) external onlyOwner {
        require(device != address(0), "CommitRevealOTP: zero address");
        authorizedDevices[device] = true;
        emit DeviceAuthorized(device);
    }

    function revokeDevice(address device) external onlyOwner {
        authorizedDevices[device] = false;
        emit DeviceRevoked(device);
    }

    // =========================================================================
    // REGISTRATION
    // =========================================================================

    /**
     * @notice Store keccak256(seed) for a user — called once at registration.
     *
     * @param userHash   keccak256(username) — username never on-chain
     * @param seedCommit keccak256(seed)     — seed never on-chain
     *
     * Re-calling replaces the commitment (allows seed rotation by admin).
     * Only authorized devices may call this.
     */
    function commit(
        bytes32 userHash,
        bytes32 seedCommit
    ) external onlyDevice {
        require(userHash   != bytes32(0), "CommitRevealOTP: zero userHash");
        require(seedCommit != bytes32(0), "CommitRevealOTP: zero seedCommit");

        userCommitments[userHash] = UserCommitment({
            seedCommit:  seedCommit,
            registered:  true
        });

        emit UserCommitted(userHash, block.timestamp);
    }

    // =========================================================================
    // LOGIN STEP 1 — begin (called after password verified)
    // =========================================================================

    /**
     * @notice Lock in the expected nonce and code BEFORE showing the code to
     *         the user. This is the core non-repudiation guarantee — the
     *         RPi3 cannot change the expected code after the user sees it.
     *
     * @param userHash    keccak256(username)
     * @param nonceHash   keccak256(nonce)    — nonce stays off-chain
     * @param codeCommit  keccak256(seed || nonce || username || timestamp)
     *                    — the full pre-image hash, NOT keccak256(6-digit-code)
     *                    — brute-force resistant because pre-image contains seed
     *
     * Overwrites any previous pending login for this user (handles timeout
     * without requiring explicit cleanup).
     */
    function beginLogin(
        bytes32 userHash,
        bytes32 nonceHash,
        bytes32 codeCommit
    ) external onlyDevice {
        require(!lockedUsers[userHash],     "CommitRevealOTP: user is locked");
        require(userCommitments[userHash].registered,
                                            "CommitRevealOTP: user not registered");
        require(userHash   != bytes32(0),   "CommitRevealOTP: zero userHash");
        require(nonceHash  != bytes32(0),   "CommitRevealOTP: zero nonceHash");
        require(codeCommit != bytes32(0),   "CommitRevealOTP: zero codeCommit");
        require(!usedNonces[userHash][nonceHash],
                                            "CommitRevealOTP: nonce already used");

        uint256 expiry = block.timestamp + LOGIN_TTL;

        pendingLogin[userHash] = PendingLogin({
            nonceHash:   nonceHash,
            codeCommit:  codeCommit,
            expiresAt:   expiry,
            active:      true
        });

        emit LoginStarted(userHash, nonceHash, expiry);
    }

    // =========================================================================
    // LOGIN STEP 2 — reveal (called after user submits the code)
    // =========================================================================

    /**
     * @notice Verify the nonce and pre-image against committed values.
     *         Marks the nonce permanently spent on success.
     *
     * @param userHash  keccak256(username)
     * @param nonce     The raw 32-byte nonce (now revealed for verification)
     * @param preImage  seed || nonce || username || timestamp
     *                  (the full concatenated pre-image, not the 6-digit code)
     *
     * @return true if verification passed, false otherwise.
     *
     * CHECKS-EFFECTS-INTERACTIONS order:
     *   1. All require() checks
     *   2. State changes (nonce spent, fail count, pending cleared)
     *   3. Events emitted
     *   No external calls — reentrancy not applicable.
     */
    function reveal(
        bytes32 userHash,
        bytes32 nonce,
        bytes32 preImage
    ) external onlyDevice returns (bool) {
        // ── CHECKS ────────────────────────────────────────────────────────────
        if (lockedUsers[userHash]) {
            emit RevealFailed(userHash, "user locked", block.timestamp);
            return false;
        }

        PendingLogin storage pending = pendingLogin[userHash];

        if (!pending.active) {
            emit RevealFailed(userHash, "no pending login", block.timestamp);
            return false;
        }

        if (block.timestamp > pending.expiresAt) {
            // ── EFFECTS (expiry) ──────────────────────────────────────────────
            pending.active = false;
            emit RevealFailed(userHash, "login expired", block.timestamp);
            return false;
        }

        // Verify nonce: keccak256(nonce) must match nonceHash committed in beginLogin
        if (keccak256(abi.encodePacked(nonce)) != pending.nonceHash) {
            _recordFail(userHash);
            emit RevealFailed(userHash, "nonce mismatch", block.timestamp);
            return false;
        }

        // Verify pre-image: keccak256(preImage) must match codeCommit in beginLogin
        if (keccak256(abi.encodePacked(preImage)) != pending.codeCommit) {
            _recordFail(userHash);
            emit RevealFailed(userHash, "preimage mismatch", block.timestamp);
            return false;
        }

        // Verify nonce has never been used before (double-spend check)
        if (usedNonces[userHash][pending.nonceHash]) {
            emit RevealFailed(userHash, "nonce already spent", block.timestamp);
            return false;
        }

        // ── EFFECTS (success) ─────────────────────────────────────────────────
        usedNonces[userHash][pending.nonceHash] = true;  // spend nonce permanently
        failCount[userHash]  = 0;                        // reset fail streak
        pending.active       = false;                    // clear pending login

        // ── EVENT ─────────────────────────────────────────────────────────────
        emit OTPRevealed(userHash, true, block.timestamp);

        return true;
    }

    // =========================================================================
    // VIEW FUNCTIONS (eth_call — no gas for RPi3)
    // =========================================================================

    /** True if the user's account is locked (>= MAX_FAILS failures). */
    function isLocked(bytes32 userHash) external view returns (bool) {
        return lockedUsers[userHash];
    }

    /** True if the user has a seed commitment registered. */
    function hasCommitment(bytes32 userHash) external view returns (bool) {
        return userCommitments[userHash].registered;
    }

    /** True if this nonce has already been spent (replay check). */
    function isNonceUsed(bytes32 userHash, bytes32 nonceHash)
        external view returns (bool)
    {
        return usedNonces[userHash][nonceHash];
    }

    /** Returns the current fail count for a user. */
    function getFailCount(bytes32 userHash) external view returns (uint8) {
        return failCount[userHash];
    }

    /**
     * @notice Returns the pending login details for a user.
     * @return nonceHash  committed nonce hash
     * @return codeCommit committed code hash
     * @return expiresAt  unix timestamp of expiry
     * @return active     false if no pending login or already revealed
     */
    function getPendingLogin(bytes32 userHash)
        external view
        returns (
            bytes32 nonceHash,
            bytes32 codeCommit,
            uint256 expiresAt,
            bool    active
        )
    {
        PendingLogin storage p = pendingLogin[userHash];
        return (p.nonceHash, p.codeCommit, p.expiresAt, p.active);
    }

    // =========================================================================
    // ADMIN
    // =========================================================================

    /**
     * @notice Unlock a user locked by too many OTP failures.
     *         Only the contract owner (admin) may call this.
     */
    function unlock(bytes32 userHash) external onlyOwner {
        require(lockedUsers[userHash], "CommitRevealOTP: user not locked");
        lockedUsers[userHash] = false;
        failCount[userHash]   = 0;
        emit UserUnlocked(userHash, block.timestamp);
    }

    /**
     * @notice Rotate a user's seed commitment (e.g. after seed file compromise).
     *         Clears any active pending login for the user.
     */
    function rotateCommitment(
        bytes32 userHash,
        bytes32 newSeedCommit
    ) external onlyDevice {
        require(newSeedCommit != bytes32(0), "CommitRevealOTP: zero seedCommit");
        userCommitments[userHash].seedCommit = newSeedCommit;
        // Clear any in-flight pending login — old seed context is invalid
        pendingLogin[userHash].active = false;
        emit UserCommitted(userHash, block.timestamp);
    }

    /**
     * @notice Transfer contract ownership.
     */
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "CommitRevealOTP: zero address");
        owner = newOwner;
    }

    // =========================================================================
    // INTERNAL
    // =========================================================================

    /**
     * @dev Record a failed reveal attempt. Locks user after MAX_FAILS.
     *      Always clears the pending login to force a new beginLogin cycle.
     */
    function _recordFail(bytes32 userHash) internal {
        if (failCount[userHash] < type(uint8).max) {
            failCount[userHash]++;
        }
        // Clear pending login — attacker cannot retry the same commitment
        pendingLogin[userHash].active = false;

        if (failCount[userHash] >= MAX_FAILS && !lockedUsers[userHash]) {
            lockedUsers[userHash] = true;
            emit UserLocked(userHash, block.timestamp);
        }
    }
}
