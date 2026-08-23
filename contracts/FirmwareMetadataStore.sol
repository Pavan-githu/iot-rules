// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * FirmwareMetadataStore
 * ----------------------
 * Stores and retrieves full firmware metadata on-chain.
 * Supports a 3-stage approval workflow: PENDING_OEM → OEM_APPROVED → RELEASED_TO_DEVICE
 *
 * writeFirmwareMetadata() — called by:
 *   - Supplier (stage 0, initial registration)
 *   - OEM      (stage 1, OEM approval)
 *   - Fleet    (stage 2, release to device)
 *
 * readFirmwareMetadata()       — returns 15 values (14 fields + exists bool)
 * readLatestFirmwareMetadata() — returns 14 values (no exists)
 *
 * ABI layout matches blockchain_logger.cpp abiDecodeFirmwareResult().
 */
contract FirmwareMetadataStore {

    // ─────────────────────────────────────────────────────────────────────────
    // Approval stage enum (stored as uint8)
    // ─────────────────────────────────────────────────────────────────────────
    uint8 public constant PENDING_OEM        = 0;
    uint8 public constant OEM_APPROVED       = 1;
    uint8 public constant RELEASED_TO_DEVICE = 2;

    // ─────────────────────────────────────────────────────────────────────────
    // Data structures
    // ─────────────────────────────────────────────────────────────────────────

    struct FirmwareMetadata {
        string  firmwareHash;
        string  firmwareVersion;
        string  timestamp;
        string  signerIdentity;
        string  downloadUrl;
        string  imageFilename;
        uint256 imageSizeBytes;
        string  finalImageFilename;
        uint256 finalImageSizeBytes;
        uint8   approvalStage;
        string  approvedByOem;
        string  oemApprovedAt;
        string  approvedByFleet;
        string  fleetApprovedAt;
        bool    exists;
    }

    mapping(string => FirmwareMetadata) private _metadataByVersion;
    string[] private _versions;

    // ─────────────────────────────────────────────────────────────────────────
    // Access control
    // ─────────────────────────────────────────────────────────────────────────

    address public owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    modifier onlyOwner() {
        require(msg.sender == owner, "FirmwareMetadataStore: caller is not owner");
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

    event FirmwareMetadataWritten(
        string  indexed firmwareVersion,
        string          firmwareHash,
        string          signerIdentity,
        uint256         imageSizeBytes,
        uint256         finalImageSizeBytes,
        string          timestamp,
        uint8           approvalStage
    );

    // ─────────────────────────────────────────────────────────────────────────
    // Write — 14 params matching blockchain_logger.cpp ABI layout
    // ─────────────────────────────────────────────────────────────────────────

    function writeFirmwareMetadata(
        string calldata firmwareHash,
        string calldata firmwareVersion,
        string calldata timestamp,
        string calldata signerIdentity,
        string calldata downloadUrl,
        string calldata imageFilename,
        uint256         imageSizeBytes,
        string calldata finalImageFilename,
        uint256         finalImageSizeBytes,
        uint8           approvalStage,
        string calldata approvedByOem,
        string calldata oemApprovedAt,
        string calldata approvedByFleet,
        string calldata fleetApprovedAt
    ) external onlyOwner {
        require(bytes(firmwareHash).length > 0,       "firmwareHash cannot be empty");
        require(bytes(firmwareVersion).length > 0,    "firmwareVersion cannot be empty");
        require(bytes(timestamp).length > 0,          "timestamp cannot be empty");
        require(bytes(signerIdentity).length > 0,     "signerIdentity cannot be empty");
        require(bytes(downloadUrl).length > 0,        "downloadUrl cannot be empty");
        require(bytes(imageFilename).length > 0,      "imageFilename cannot be empty");
        require(imageSizeBytes > 0,                   "imageSizeBytes cannot be zero");
        require(bytes(finalImageFilename).length > 0, "finalImageFilename cannot be empty");
        require(finalImageSizeBytes > 0,              "finalImageSizeBytes cannot be zero");
        require(approvalStage <= RELEASED_TO_DEVICE,  "Invalid approvalStage");

        bool isNew = !_metadataByVersion[firmwareVersion].exists;

        _metadataByVersion[firmwareVersion] = FirmwareMetadata({
            firmwareHash:        firmwareHash,
            firmwareVersion:     firmwareVersion,
            timestamp:           timestamp,
            signerIdentity:      signerIdentity,
            downloadUrl:         downloadUrl,
            imageFilename:       imageFilename,
            imageSizeBytes:      imageSizeBytes,
            finalImageFilename:  finalImageFilename,
            finalImageSizeBytes: finalImageSizeBytes,
            approvalStage:       approvalStage,
            approvedByOem:       approvedByOem,
            oemApprovedAt:       oemApprovedAt,
            approvedByFleet:     approvedByFleet,
            fleetApprovedAt:     fleetApprovedAt,
            exists:              true
        });

        if (isNew) _versions.push(firmwareVersion);

        emit FirmwareMetadataWritten(
            firmwareVersion, firmwareHash, signerIdentity,
            imageSizeBytes, finalImageSizeBytes, timestamp, approvalStage
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Read — returns 15 values (14 fields + exists)
    // Matches blockchain_logger.cpp abiDecodeFirmwareResult(has_exists=true)
    // ─────────────────────────────────────────────────────────────────────────

    function readFirmwareMetadata(string calldata firmwareVersion)
        external view
        returns (
            string  memory firmwareHash,
            string  memory firmwareVersion_,
            string  memory timestamp,
            string  memory signerIdentity,
            string  memory downloadUrl,
            string  memory imageFilename,
            uint256        imageSizeBytes,
            string  memory finalImageFilename,
            uint256        finalImageSizeBytes,
            uint8          approvalStage,
            string  memory approvedByOem,
            string  memory oemApprovedAt,
            string  memory approvedByFleet,
            string  memory fleetApprovedAt,
            bool           exists
        )
    {
        FirmwareMetadata storage m = _metadataByVersion[firmwareVersion];
        return (
            m.firmwareHash, m.firmwareVersion, m.timestamp,
            m.signerIdentity, m.downloadUrl, m.imageFilename,
            m.imageSizeBytes, m.finalImageFilename, m.finalImageSizeBytes,
            m.approvalStage, m.approvedByOem, m.oemApprovedAt,
            m.approvedByFleet, m.fleetApprovedAt, m.exists
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Read latest — returns 14 values (no exists)
    // Matches blockchain_logger.cpp abiDecodeFirmwareResult(has_exists=false)
    // ─────────────────────────────────────────────────────────────────────────

    function readLatestFirmwareMetadata()
        external view
        returns (
            string  memory firmwareHash,
            string  memory firmwareVersion,
            string  memory timestamp,
            string  memory signerIdentity,
            string  memory downloadUrl,
            string  memory imageFilename,
            uint256        imageSizeBytes,
            string  memory finalImageFilename,
            uint256        finalImageSizeBytes,
            uint8          approvalStage,
            string  memory approvedByOem,
            string  memory oemApprovedAt,
            string  memory approvedByFleet,
            string  memory fleetApprovedAt
        )
    {
        require(_versions.length > 0, "No firmware metadata registered yet");
        FirmwareMetadata storage m = _metadataByVersion[_versions[_versions.length - 1]];
        return (
            m.firmwareHash, m.firmwareVersion, m.timestamp,
            m.signerIdentity, m.downloadUrl, m.imageFilename,
            m.imageSizeBytes, m.finalImageFilename, m.finalImageSizeBytes,
            m.approvalStage, m.approvedByOem, m.oemApprovedAt,
            m.approvedByFleet, m.fleetApprovedAt
        );
    }

    function isRegistered(string calldata firmwareVersion) external view returns (bool) {
        return _metadataByVersion[firmwareVersion].exists;
    }

    function getFirmwareCount() external view returns (uint256) {
        return _versions.length;
    }

    function getFirmwareVersionAt(uint256 index) external view returns (string memory) {
        require(index < _versions.length, "Index out of bounds");
        return _versions[index];
    }
}


    // ─────────────────────────────────────────────────────────────────────────
    // Data structures
    // ─────────────────────────────────────────────────────────────────────────

    struct FirmwareMetadata {
        string  firmwareHash;          // "sha256:<hex>"
        string  firmwareVersion;       // "v0.1.0"
        string  timestamp;             // "2026-06-29T16:36:52Z"
        string  signerIdentity;        // "TechID:5678"
        string  downloadUrl;           // GitHub release download URL
        string  imageFilename;         // "core-image-minimal-raspberrypi3-....rootfs.wic.bz2"
        uint256 imageSizeBytes;        // 54803225
        string  finalImageFilename;    // "RPIF_v0.1.0.ldr"
        uint256 finalImageSizeBytes;   // 54803341
        bool    exists;                // false → record not registered
    }

    // firmware_version string → metadata record
    mapping(string => FirmwareMetadata) private _metadataByVersion;

    // ordered list of all registered firmware versions (for enumeration)
    string[] private _versions;

    // ─────────────────────────────────────────────────────────────────────────
    // Access control
    // ─────────────────────────────────────────────────────────────────────────

    address public owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    modifier onlyOwner() {
        require(msg.sender == owner, "FirmwareMetadataStore: caller is not owner");
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

    event FirmwareMetadataWritten(
        string  indexed firmwareVersion,
        string          firmwareHash,
        string          signerIdentity,
        uint256         imageSizeBytes,
        uint256         finalImageSizeBytes,
        string          timestamp
    );

    // ─────────────────────────────────────────────────────────────────────────
    // Write — called by deploy_firmware.py
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Store firmware metadata on-chain.
     *         Reverts if the version was already registered (immutability guarantee).
     * @param firmwareHash         "sha256:<hex>" hash of the raw image
     * @param firmwareVersion      Semver string, e.g. "v0.1.0"
     * @param timestamp            ISO-8601 build timestamp
     * @param signerIdentity       Signer tag, e.g. "TechID:5678"
     * @param downloadUrl          GitHub release asset download URL
     * @param imageFilename        Raw image filename (.wic.bz2)
     * @param imageSizeBytes       Raw image size in bytes
     * @param finalImageFilename   Signed .ldr filename
     * @param finalImageSizeBytes  Signed .ldr size in bytes
     */
    function writeFirmwareMetadata(
        string calldata firmwareHash,
        string calldata firmwareVersion,
        string calldata timestamp,
        string calldata signerIdentity,
        string calldata downloadUrl,
        string calldata imageFilename,
        uint256         imageSizeBytes,
        string calldata finalImageFilename,
        uint256         finalImageSizeBytes
    ) external onlyOwner {
        require(
            !_metadataByVersion[firmwareVersion].exists,
            "FirmwareMetadataStore: version already registered"
        );
        require(bytes(firmwareHash).length > 0,        "firmwareHash cannot be empty");
        require(bytes(firmwareVersion).length > 0,     "firmwareVersion cannot be empty");
        require(bytes(timestamp).length > 0,           "timestamp cannot be empty");
        require(bytes(signerIdentity).length > 0,      "signerIdentity cannot be empty");
        require(bytes(downloadUrl).length > 0,         "downloadUrl cannot be empty");
        require(bytes(imageFilename).length > 0,       "imageFilename cannot be empty");
        require(imageSizeBytes > 0,                    "imageSizeBytes cannot be zero");
        require(bytes(finalImageFilename).length > 0,  "finalImageFilename cannot be empty");
        require(finalImageSizeBytes > 0,               "finalImageSizeBytes cannot be zero");

        _metadataByVersion[firmwareVersion] = FirmwareMetadata({
            firmwareHash:        firmwareHash,
            firmwareVersion:     firmwareVersion,
            timestamp:           timestamp,
            signerIdentity:      signerIdentity,
            downloadUrl:         downloadUrl,
            imageFilename:       imageFilename,
            imageSizeBytes:      imageSizeBytes,
            finalImageFilename:  finalImageFilename,
            finalImageSizeBytes: finalImageSizeBytes,
            exists:              true
        });

        _versions.push(firmwareVersion);

        emit FirmwareMetadataWritten(
            firmwareVersion,
            firmwareHash,
            signerIdentity,
            imageSizeBytes,
            finalImageSizeBytes,
            timestamp
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Read — called by Raspberry Pi agent at boot / OTA check
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Retrieve full firmware metadata for a specific version.
     * @param firmwareVersion  e.g. "v0.1.0"
     * @return firmwareHash        "sha256:<hex>" of the raw image
     * @return firmwareVersion_    The version string (echoed back)
     * @return timestamp           ISO-8601 build timestamp
     * @return signerIdentity      Signer tag
     * @return downloadUrl         GitHub release asset URL
     * @return imageFilename       Raw image filename
     * @return imageSizeBytes      Raw image size in bytes
     * @return finalImageFilename  Signed .ldr filename
     * @return finalImageSizeBytes Signed .ldr size in bytes
     * @return exists              False if this version was never registered
     */
    function readFirmwareMetadata(string calldata firmwareVersion)
        external
        view
        returns (
            string  memory firmwareHash,
            string  memory firmwareVersion_,
            string  memory timestamp,
            string  memory signerIdentity,
            string  memory downloadUrl,
            string  memory imageFilename,
            uint256        imageSizeBytes,
            string  memory finalImageFilename,
            uint256        finalImageSizeBytes,
            bool           exists
        )
    {
        FirmwareMetadata storage m = _metadataByVersion[firmwareVersion];
        return (
            m.firmwareHash,
            m.firmwareVersion,
            m.timestamp,
            m.signerIdentity,
            m.downloadUrl,
            m.imageFilename,
            m.imageSizeBytes,
            m.finalImageFilename,
            m.finalImageSizeBytes,
            m.exists
        );
    }

    /**
     * @notice Retrieve the latest registered firmware metadata.
     *         Useful when the Pi does not know the exact version string.
     */
    function readLatestFirmwareMetadata()
        external
        view
        returns (
            string  memory firmwareHash,
            string  memory firmwareVersion,
            string  memory timestamp,
            string  memory signerIdentity,
            string  memory downloadUrl,
            string  memory imageFilename,
            uint256        imageSizeBytes,
            string  memory finalImageFilename,
            uint256        finalImageSizeBytes
        )
    {
        require(_versions.length > 0, "No firmware metadata registered yet");

        FirmwareMetadata storage m = _metadataByVersion[_versions[_versions.length - 1]];
        return (
            m.firmwareHash,
            m.firmwareVersion,
            m.timestamp,
            m.signerIdentity,
            m.downloadUrl,
            m.imageFilename,
            m.imageSizeBytes,
            m.finalImageFilename,
            m.finalImageSizeBytes
        );
    }

    /**
     * @notice Check if a firmware version has been registered.
     * @param firmwareVersion  e.g. "v0.1.0"
     */
    function isRegistered(string calldata firmwareVersion) external view returns (bool) {
        return _metadataByVersion[firmwareVersion].exists;
    }

    /**
     * @notice Returns the total number of registered firmware versions.
     */
    function getFirmwareCount() external view returns (uint256) {
        return _versions.length;
    }

    /**
     * @notice Returns the firmware version string at a given index (for enumeration).
     * @param index  0-based index into the registration history
     */
    function getFirmwareVersionAt(uint256 index) external view returns (string memory) {
        require(index < _versions.length, "Index out of bounds");
        return _versions[index];
    }
}
