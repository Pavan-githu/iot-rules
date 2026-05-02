// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title  IoTAuthLog
 * @notice Immutable authentication event log for the RaceIoT gateway.
 *
 * @dev    HOW THIS CONTRACT LINKS OTP / USER / RPi3 WITH BLOCKCHAIN
 *         ──────────────────────────────────────────────────────────
 *
 *  1. USER IDENTITY  (privacy-preserving)
 *     The RPi3 C++ gateway computes keccak256(username) locally and
 *     passes the 32-byte digest as `userHash`.  The plaintext username
 *     never appears on-chain, yet on-chain state (fail count, lockout)
 *     is correctly scoped per user.
 *
 *  2. OTP FLOW → BLOCKCHAIN TRANSITIONS
 *     Password OK  →  logEvent(userHash, OTP_SENT,      sessionId)
 *     OTP correct  →  logEvent(userHash, OTP_SUCCESS,   sessionId)
 *     OTP wrong    →  logEvent(userHash, OTP_FAIL,      sessionId)
 *     3 failures   →  contract auto-sets lockedUsers[userHash] = true
 *                     and emits UserLocked event
 *
 *  3. SESSION CORRELATION
 *     The C++ gateway generates a random 32-byte sessionId at the
 *     password step.  Every subsequent event for that login attempt
 *     carries the same sessionId, creating an auditable chain:
 *       LOGIN_ATTEMPT(sid) → OTP_SENT(sid) → OTP_SUCCESS/FAIL(sid)
 *
 *  4. DISTRIBUTED LOCKOUT
 *     After MAX_OTP_FAILS (3) OTP_FAIL events the account is locked
 *     on-chain.  The RPi3 queries isLocked() before each OTP attempt,
 *     so even a rebooted device honours the on-chain lockout state.
 *     Only the contract owner can unlock a user via unlock().
 *
 *  5. DEVICE AUTHORISATION
 *     Only registered device addresses may call logEvent().
 *     Registering a device requires an owner transaction, preventing
 *     rogue devices from poisoning the log.
 */
contract IoTAuthLog {

    // ── Event type enum (must stay in sync with BlockchainLogger::EventType) ─
    enum EventType {
        LOGIN_ATTEMPT,  // 0  password phase started
        OTP_SENT,       // 1  password OK – OTP dispatched to user
        OTP_SUCCESS,    // 2  correct OTP entered – session granted
        OTP_FAIL,       // 3  wrong OTP entered
        LOCKOUT,        // 4  account locked after MAX_OTP_FAILS failures
        LOGIN_FAIL      // 5  wrong password
    }

    // ── Stored event structure ────────────────────────────────────────────────
    struct AuthEvent {
        address   device;       // which RPi3 device logged this
        bytes32   userHash;     // keccak256(username) – never plaintext
        EventType eventType;
        uint256   timestamp;    // block.timestamp
        bytes32   sessionId;    // random ID linking events in one login
    }

    // ── Emitted events (indexable via eth_getLogs) ────────────────────────────
    event AuthLogged(
        address   indexed device,
        bytes32   indexed userHash,
        EventType indexed eventType,
        uint256           timestamp,
        bytes32           sessionId
    );
    event UserLocked  (bytes32 indexed userHash, uint256 timestamp);
    event UserUnlocked(bytes32 indexed userHash, uint256 timestamp);
    event DeviceAuthorized(address indexed device);
    event DeviceRevoked   (address indexed device);

    // ── State variables ───────────────────────────────────────────────────────
    address public owner;
    mapping(address => bool)  public authorizedDevices;
    mapping(bytes32 => uint8) public failCount;      // OTP_FAIL counter per user
    mapping(bytes32 => bool)  public lockedUsers;    // on-chain lockout flag
    AuthEvent[]               public events;         // append-only event log

    uint8 public constant MAX_OTP_FAILS = 3;

    // ── Access control ────────────────────────────────────────────────────────
    modifier onlyOwner() {
        require(msg.sender == owner, "IoTAuthLog: not owner");
        _;
    }

    modifier onlyDevice() {
        require(
            authorizedDevices[msg.sender] || msg.sender == owner,
            "IoTAuthLog: caller not an authorized device"
        );
        _;
    }

    // ── Constructor ───────────────────────────────────────────────────────────
    constructor() {
        owner = msg.sender;
        authorizedDevices[msg.sender] = true;   // deployer is also a device
        emit DeviceAuthorized(msg.sender);
    }

    // ── Device management (owner only) ────────────────────────────────────────

    function authorizeDevice(address device) external onlyOwner {
        require(device != address(0), "IoTAuthLog: zero address");
        authorizedDevices[device] = true;
        emit DeviceAuthorized(device);
    }

    function revokeDevice(address device) external onlyOwner {
        authorizedDevices[device] = false;
        emit DeviceRevoked(device);
    }

    // ── Core: log an authentication event ────────────────────────────────────

    /**
     * @param userHash   keccak256(username) computed by the RPi3 gateway
     * @param eventType  EventType enum value (0-5)
     * @param sessionId  Random 32-byte session ID for log correlation
     */
    function logEvent(
        bytes32 userHash,
        uint8   eventType,
        bytes32 sessionId
    ) external onlyDevice {
        require(eventType <= uint8(EventType.LOGIN_FAIL), "IoTAuthLog: invalid event type");

        events.push(AuthEvent({
            device:    msg.sender,
            userHash:  userHash,
            eventType: EventType(eventType),
            timestamp: block.timestamp,
            sessionId: sessionId
        }));

        emit AuthLogged(msg.sender, userHash, EventType(eventType), block.timestamp, sessionId);

        // State machine: update fail count / lockout on OTP events
        if (EventType(eventType) == EventType.OTP_FAIL) {
            // Overflow-safe: uint8 max is 255, MAX_OTP_FAILS is 3
            if (failCount[userHash] < type(uint8).max) {
                failCount[userHash]++;
            }
            if (failCount[userHash] >= MAX_OTP_FAILS && !lockedUsers[userHash]) {
                lockedUsers[userHash] = true;
                emit UserLocked(userHash, block.timestamp);
            }
        } else if (EventType(eventType) == EventType.OTP_SUCCESS) {
            // Reset fail streak on success (lockout NOT auto-cleared; needs admin)
            failCount[userHash] = 0;
        }
    }

    // ── Query functions (view – no gas for callers) ───────────────────────────

    function isLocked(bytes32 userHash) external view returns (bool) {
        return lockedUsers[userHash];
    }

    function getFailCount(bytes32 userHash) external view returns (uint8) {
        return failCount[userHash];
    }

    function getEventCount() external view returns (uint256) {
        return events.length;
    }

    /**
     * @notice Retrieve a stored auth event by index.
     * @return device     Ethereum address of the RPi3 that logged the event
     * @return userHash   keccak256(username)
     * @return eventType  0-5 matching EventType enum
     * @return timestamp  block.timestamp when logged
     * @return sessionId  32-byte session correlation ID
     */
    function getEvent(uint256 index)
        external
        view
        returns (
            address device,
            bytes32 userHash,
            uint8   eventType,
            uint256 timestamp,
            bytes32 sessionId
        )
    {
        require(index < events.length, "IoTAuthLog: index out of bounds");
        AuthEvent memory e = events[index];
        return (e.device, e.userHash, uint8(e.eventType), e.timestamp, e.sessionId);
    }

    // ── Admin: unlock a locked user (owner only) ──────────────────────────────

    /**
     * @notice Unlock a user that was locked after too many OTP failures.
     *         Only the contract owner (admin) can call this.
     */
    function unlock(bytes32 userHash) external onlyOwner {
        require(lockedUsers[userHash], "IoTAuthLog: user is not locked");
        lockedUsers[userHash] = false;
        failCount[userHash]   = 0;
        emit UserUnlocked(userHash, block.timestamp);
    }

    /**
     * @notice Transfer contract ownership (two-step recommended for production).
     */
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "IoTAuthLog: zero address");
        owner = newOwner;
    }
}
