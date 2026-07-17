// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * FirmwareMetadataStore
 * ----------------------
 * Stores and retrieves full firmware metadata on-chain after every build.
 * Called by deploy_firmware.py → writeFirmwareMetadata()
 * Queried by the Raspberry Pi agent at boot  → readFirmwareMetadata()
 *
 * Fields stored per record:
 *   firmware_hash        – "sha256:<hex>" string from firmware-metadata.json
 *   firmware_version     – semver string, e.g. "v0.1.0"
 *   timestamp            – ISO-8601 build timestamp string
 *   signer_identity      – signer tag, e.g. "TechID:5678"
 *   download_url         – GitHub release asset URL
 *   image_filename       – raw image filename (.wic.bz2)
 *   image_size_bytes     – raw image byte size (uint256)
 *   final_image_filename – signed .ldr filename
 *   final_image_size_bytes – signed .ldr byte size (uint256)
 *
 * Access control:
 *   - Only the contract owner (build-server wallet) may call writeFirmwareMetadata.
 *   - Anyone (Raspberry Pi, auditor) may call readFirmwareMetadata.
 *
 * Deployed on: Polygon Amoy testnet (chainId 80002)
 */
contract FirmwareMetadataStore {

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
