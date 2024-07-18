// SPDX-License-Identifier: MIT
// Creator: Debox Labs

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./utils/DateTime.sol";

contract DeboxMetaDonation is DateTime,Ownable {

    using SafeMath for uint256;

    uint256 public constant MAX_AMOUNT_PER_DAY = 2*10**18;  // 10 ethers
    uint256 public constant MIN_AMOUNT_PER_META_DAY = 5*10**17;  // 0.5 ethers

    address payable public _dAddr;
    mapping(address => uint256) public _nonces;
    address public _signOwner = 0x96216849c49358B10257cb55b28eA603c874b05E;
    mapping (uint256 => uint256) public _donatePerDayAmount;
    mapping (bytes32 => mapping (uint256 => uint256)) public _metaDonatePerDayAmount;

    event MetaDonationRecord(address indexed sender,string meta, uint256 amount);
    
    modifier callerIsUser() {
        require(tx.origin == msg.sender, "The caller is another contract");
        _;
    }

    constructor() {
        _dAddr = payable(msg.sender);
    }

    function modifyDAddr(address new_addr) external onlyOwner {
        require(new_addr != address(0), "invalid address");
        _dAddr = payable(new_addr);
    }

    function modifySignOwner(address owner) external onlyOwner {
        require(owner != address(0), "Invalid address");
        _signOwner = owner;
    }

    function _stringToBytes32(string memory source) internal pure returns (bytes32 result) {
        bytes memory temp = bytes(source);
        require(temp.length <= 32, "Ths source string exceeds 32 bytes");
        assembly {
            result := mload(add(source, 32))
        }
    }

    function getYearMonthDay(uint256 timestamp) internal pure returns (uint256) {
        uint256 year = getYear(timestamp);
        uint256 month = getMonth(timestamp);
        uint256 day = getDay(timestamp);
        return year.mul(10000).add(month.mul(100)).add(day);
    }

    function metaDonate (string memory meta, bytes memory signature) external payable callerIsUser returns  (bool) {
        bytes32 message = keccak256(abi.encodePacked(msg.sender, meta, _nonces[_msgSender()]));
        require(ECDSA.recover(message, signature) == _signOwner, "The signature is invalid");
        bytes32 metaBytes = _stringToBytes32(meta);
        uint256 nowYearMonthDay = getYearMonthDay(block.timestamp);
        uint256 donatePerDayBalance = MAX_AMOUNT_PER_DAY.sub(_donatePerDayAmount[nowYearMonthDay]);
        uint256 metaDonatePerDayBalance = MIN_AMOUNT_PER_META_DAY.sub(_metaDonatePerDayAmount[metaBytes][nowYearMonthDay]);
        require(donatePerDayBalance > 0 && metaDonatePerDayBalance > 0 ,"Exceed per day max amount");
        require(msg.value > 0 ,"Value is zero");
        uint256 payAmount = 0;
        uint256 refundAmount = 0;
        if (donatePerDayBalance >= metaDonatePerDayBalance) {
            if (msg.value >= metaDonatePerDayBalance) {
                payAmount = metaDonatePerDayBalance;
                refundAmount = msg.value.sub(metaDonatePerDayBalance);
            }else {
                payAmount = msg.value;
            }
        }else {
            if (msg.value >= donatePerDayBalance) {
                payAmount = donatePerDayBalance;
                refundAmount = msg.value.sub(donatePerDayBalance);
            }else {
                payAmount = msg.value;
            }
        }
        if (refundAmount > 0) {
            payable(msg.sender).transfer(refundAmount);
        }
        _dAddr.transfer(payAmount);
        _donatePerDayAmount[nowYearMonthDay] = _donatePerDayAmount[nowYearMonthDay].add(payAmount);
        _metaDonatePerDayAmount[metaBytes][nowYearMonthDay] = _metaDonatePerDayAmount[metaBytes][nowYearMonthDay].add(payAmount);
        _nonces[_msgSender()] += 1;
        emit MetaDonationRecord (msg.sender,meta,payAmount);
        return true;
    }

    function getMetaDonateBalance (string memory meta) external view callerIsUser returns  (uint256) {
        bytes32 metaBytes = _stringToBytes32(meta);
        uint256 nowYearMonthDay = getYearMonthDay(block.timestamp);
        uint256 donatePerDayBalance = MAX_AMOUNT_PER_DAY.sub(_donatePerDayAmount[nowYearMonthDay]);
        uint256 metaDonatePerDayBalance = MIN_AMOUNT_PER_META_DAY.sub(_metaDonatePerDayAmount[metaBytes][nowYearMonthDay]);
        if (donatePerDayBalance >= metaDonatePerDayBalance) {
            return metaDonatePerDayBalance;
        }else {
            return donatePerDayBalance;
        }
    }
}