// SPDX-License-Identifier: MIT
// Creator: Debox Labs

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";


contract DeboxMetaDonation is Ownable {

    using SafeMath for uint256;

    uint256 public MAX_AMOUNT_PER_DAY = 2*10**18;  // 2 ethers

    address payable public _dAddr;
    mapping(address => uint256) public _nonces;
    address public _signOwner = 0xA6146598e4D58A1ca49F98591F3A528Fd4c695F9;
    uint256 public _currentTime = 20230523;
    uint256 public donateBalance;

    event MetaDonationRecord(address indexed sender,string meta, uint256 signatureTime, uint256 amount);
    
    modifier callerIsUser() {
        require(tx.origin == msg.sender, "The caller is another contract");
        _;
    }

    constructor(uint256 currentTime) {
        _dAddr = payable(msg.sender);
        _currentTime = currentTime;
        donateBalance = MAX_AMOUNT_PER_DAY;
    }

    function modifyDAddr(address new_addr) external onlyOwner {
        require(new_addr != address(0), "invalid address");
        _dAddr = payable(new_addr);
    }

    function modifySignOwner(address owner) external onlyOwner {
        require(owner != address(0), "Invalid address");
        _signOwner = owner;
    }

    function modifyCurrentTime(uint256 currentTime) external onlyOwner {
        require(currentTime > 0, "currentTime zero");
        _currentTime = currentTime;
    }

     function modifyPerAmount(uint256 maxAmountPerDay) external onlyOwner {
        require(maxAmountPerDay > 0, "maxAmountPerDay is zero");
        MAX_AMOUNT_PER_DAY = maxAmountPerDay;
    }

    function metaDonate (string memory meta, uint256 signatureTime, bytes memory signature) external payable callerIsUser returns  (bool) {
        bytes32 message = keccak256(abi.encodePacked(msg.sender, meta, signatureTime, _nonces[_msgSender()]));
        require(ECDSA.recover(message, signature) == _signOwner, "The signature is invalid");
        require(msg.value > 0 ,"Value is zero");

        if (_currentTime < signatureTime) {
            _currentTime = signatureTime;
            donateBalance = MAX_AMOUNT_PER_DAY;
        }
        require(donateBalance > 0 ,"Donate balance is zero");
        uint256 payAmount = 0;
        if (msg.value  > donateBalance) {
            payAmount = donateBalance;
            payable(msg.sender).transfer(msg.value.sub(donateBalance));
            donateBalance = 0;
        }else {
            donateBalance = donateBalance.sub(msg.value);
            payAmount = msg.value;
        }
        _nonces[_msgSender()] += 1;
        emit MetaDonationRecord (msg.sender,meta, signatureTime, payAmount);
        return true;
    }

    function withdrawAll() external onlyOwner {
        _dAddr.transfer(address(this).balance);
    }
}