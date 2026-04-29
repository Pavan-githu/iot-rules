// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract IoTUsers {

    address public adminAddress;
    address public userAAddress;
    address public userBAddress;

    event AdminSet(address indexed previous, address indexed newAdmin);
    event UserASet(address indexed previous, address indexed newAddress);
    event UserBSet(address indexed previous, address indexed newAddress);

    constructor(
        address _admin,
        address _userA,
        address _userB
    ) {
        require(_admin != address(0), "Admin cannot be zero address");
        require(_userA != address(0), "User A cannot be zero address");
        require(_userB != address(0), "User B cannot be zero address");

        adminAddress = _admin;
        userAAddress = _userA;
        userBAddress = _userB;

        emit AdminSet(address(0), _admin);
        emit UserASet(address(0), _userA);
        emit UserBSet(address(0), _userB);
    }

    modifier onlyAdmin() {
        require(msg.sender == adminAddress, "Caller is not Admin");
        _;
    }

    function setAdmin(address _newAdmin) external onlyAdmin {
        require(_newAdmin != address(0), "Admin cannot be zero address");
        emit AdminSet(adminAddress, _newAdmin);
        adminAddress = _newAdmin;
    }

    function setUserA(address _newUserA) external onlyAdmin {
        require(_newUserA != address(0), "User A cannot be zero address");
        emit UserASet(userAAddress, _newUserA);
        userAAddress = _newUserA;
    }

    function setUserB(address _newUserB) external onlyAdmin {
        require(_newUserB != address(0), "User B cannot be zero address");
        emit UserBSet(userBAddress, _newUserB);
        userBAddress = _newUserB;
    }

    function getAllAddresses() external view returns (
        address admin,
        address userA,
        address userB
    ) {
        return (adminAddress, userAAddress, userBAddress);
    }

    function isKnownAddress(address _addr) external view returns (bool) {
        return (
            _addr == adminAddress ||
            _addr == userAAddress ||
            _addr == userBAddress
        );
    }
}