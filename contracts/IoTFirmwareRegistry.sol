// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * IoTFirmwareRegistry
 * --------------------
 * Stores firmware metadata on-chain after every successful build.
 * Called by deploy_firmware.py → registerFirmware()
 * Queried by the Raspberry Pi agent at boot → getFirmware()
 *
 * Access control:
 *   - Only the contract owner (build server wallet) can register firmware.
 *   - Anyone (Raspberry Pi, auditor) can read firmware records.
 *
 * Deployed on: Polygon Amoy testnet (chainId 80002)
 */
contract IoTFirmwareRegistry {

    // ─────────────────────────────────────────────────────────────────────────
    // Data structures
    // ─────────────────────────────────────────────────────────────────────────

    struct FirmwareRecord {
        bytes32 name;           // e.g. "iot-gateway" (right-padded ASCII)
        bytes32 sha256;         // SHA-256 of the .wic.bz2 image
        uint256 fileSize;       // exact byte size of the image
        uint256 buildTs;        // unix timestamp of when the build ran
        string  downloadUrl;    // GitHub release download URL
        bool    exists;         // false → record not registered
    }

    // firmware_id (keccak256 of version+buildTs+gitCommit) → record
    mapping(bytes32 => FirmwareRecord) private _firmwares;

    // ordered list of all registered firmware IDs (for enumeration)
    bytes32[] private _firmwareIds;

    // ─────────────────────────────────────────────────────────────────────────
    // Access control
    // ─────────────────────────────────────────────────────────────────────────

    address public owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    modifier onlyOwner() {
        require(msg.sender == owner, "IoTFirmwareRegistry: caller is not owner");
        _;
    }

    constructor() {
        owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "New owner is zero address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────────────────────────────────

    event FirmwareRegistered(
        bytes32 indexed firmwareId,
        bytes32 indexed name,
        bytes32         sha256,
        uint256         fileSize,
        uint256         buildTs,
        string          downloadUrl
    );

    // ─────────────────────────────────────────────────────────────────────────
    // Write — called by deploy_firmware.py
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Register a new firmware build on-chain.
     * @param firmwareId  keccak256(version || buildTs || gitCommit) — computed in Python
     * @param name        Right-padded bytes32 of the firmware name, e.g. "iot-gateway"
     * @param sha256      SHA-256 of the .wic.bz2 image (32 bytes)
     * @param fileSize    Byte size of the image file
     * @param buildTs     Unix timestamp of the build
     * @param downloadUrl GitHub release asset download URL
     */
    function registerFirmware(
        bytes32        firmwareId,
        bytes32        name,
        bytes32        sha256,
        uint256        fileSize,
        uint256        buildTs,
        string calldata downloadUrl
    ) external onlyOwner {
        require(!_firmwares[firmwareId].exists, "Firmware ID already registered");
        require(sha256 != bytes32(0),           "SHA-256 cannot be empty");
        require(fileSize > 0,                   "File size cannot be zero");
        require(bytes(downloadUrl).length > 0,  "Download URL cannot be empty");

        _firmwares[firmwareId] = FirmwareRecord({
            name:        name,
            sha256:      sha256,
            fileSize:    fileSize,
            buildTs:     buildTs,
            downloadUrl: downloadUrl,
            exists:      true
        });

        _firmwareIds.push(firmwareId);

        emit FirmwareRegistered(
            firmwareId, name, sha256, fileSize, buildTs, downloadUrl
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Read — called by Raspberry Pi agent at boot / OTA check
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Fetch a firmware record by its ID.
     *         Raspberry Pi reads this at boot to verify its own firmware hash.
     * @param firmwareId  The firmware_id from /etc/firmware-meta.json on the device
     * @return name        Firmware name
     * @return sha256      Expected SHA-256 — Pi computes its own and must match this
     * @return fileSize    Expected file size in bytes
     * @return buildTs     Build timestamp
     * @return downloadUrl URL to download the image (for OTA updates)
     * @return exists      False if this firmware ID was never registered
     */
    function getFirmware(bytes32 firmwareId)
        external
        view
        returns (
            bytes32 name,
            bytes32 sha256,
            uint256 fileSize,
            uint256 buildTs,
            string  memory downloadUrl,
            bool    exists
        )
    {
        FirmwareRecord storage r = _firmwares[firmwareId];
        return (
            r.name,
            r.sha256,
            r.fileSize,
            r.buildTs,
            r.downloadUrl,
            r.exists
        );
    }

    /**
     * @notice Returns how many firmware versions have been registered.
     */
    function getFirmwareCount() external view returns (uint256) {
        return _firmwareIds.length;
    }

    /**
     * @notice Returns the firmware ID at a given index (for enumeration).
     * @param index  0-based index into the registration history
     */
    function getFirmwareIdAt(uint256 index) external view returns (bytes32) {
        require(index < _firmwareIds.length, "Index out of bounds");
        return _firmwareIds[index];
    }

    /**
     * @notice Check if a firmware ID is registered (lightweight boot check).
     * @param firmwareId  The firmware_id from /etc/firmware-meta.json
     */
    function isRegistered(bytes32 firmwareId) external view returns (bool) {
        return _firmwares[firmwareId].exists;
    }

    /**
     * @notice Returns the most recently registered firmware record.
     *         Use this when the Raspberry Pi does not have a firmware_id
     *         (e.g. /etc/firmware-meta.json is missing or the device is new).
     *         The Pi computes the SHA-256 of its own running image and compares
     *         it against the returned sha256 to verify authenticity.
     * @return firmwareId  The latest firmware ID
     * @return name        Firmware name
     * @return sha256      Expected SHA-256 of the latest approved image
     * @return fileSize    Expected file size in bytes
     * @return buildTs     Build timestamp of the latest firmware
     * @return downloadUrl URL to download the latest approved image
     */
    function getLatestFirmware()
        external
        view
        returns (
            bytes32 firmwareId,
            bytes32 name,
            bytes32 sha256,
            uint256 fileSize,
            uint256 buildTs,
            string  memory downloadUrl
        )
    {
        require(_firmwareIds.length > 0, "No firmware registered yet");

        bytes32 latestId = _firmwareIds[_firmwareIds.length - 1];
        FirmwareRecord storage r = _firmwares[latestId];
        return (
            latestId,
            r.name,
            r.sha256,
            r.fileSize,
            r.buildTs,
            r.downloadUrl
        );
    }

    /**
     * @notice Returns the latest registered firmware ID only.
     *         Cheaper call when the Pi only needs the ID to pass to getFirmware().
     */
    function getLatestFirmwareId() external view returns (bytes32) {
        require(_firmwareIds.length > 0, "No firmware registered yet");
        return _firmwareIds[_firmwareIds.length - 1];
    }
}
