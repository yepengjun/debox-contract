// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./libraries/ReentrancyGuard.sol";
import "./libraries/RevertReasonParser.sol";
import "./libraries/TransferHelper.sol";
import "./libraries/TransitStructs.sol";
import "./libraries/Ownable.sol";
import "./libraries/Pausable.sol";
import "./libraries/SafeMath.sol";
import "./interfaces/IERC20.sol";

contract TransitSwapRouter is Ownable, ReentrancyGuard, Pausable {

    using SafeMath for uint256;

    address private _transit_swap;

    event Receipt(address from, uint256 amount);
    event Withdraw(address indexed token, address indexed executor, address indexed recipient, uint amount);
    event ChangeTransitSwap(address indexed previousTransit, address indexed newTransit);
    event ChangeTransitCross(address indexed previousTransit, address indexed newTransit);
    event ChangeTransitFees(address indexed previousTransitFees, address indexed newTransitFees);
    event TransitSwapped(address indexed srcToken, address indexed dstToken, address indexed dstReceiver, address trader, uint256 amount, uint256 returnAmount, uint256 minReturnAmount, uint256 fee, uint256 time);

    constructor(address transitSwap_, address executor) Ownable (executor) {
        _transit_swap = transitSwap_;
    }

    receive() external payable {
        emit Receipt(msg.sender, msg.value);
    }

    function transitSwap() external view returns (address) {
        return _transit_swap;
    }

    function changeTransitSwap(address newTransit) external onlyExecutor {
        address oldTransit = _transit_swap;
        _transit_swap = newTransit;
        emit ChangeTransitSwap(oldTransit, newTransit);
    }

    function changePause(bool paused) external onlyExecutor {
        if (paused) {
            _pause();
        } else {
            _unpause();
        }
    }

    function _beforeSwap(TransitStructs.TransitSwapDescription calldata desc) private returns (uint256 swapAmount, uint256 fee, uint256 beforeBalance) {
        fee = desc.amount.mul(3).div(10000);
        if (TransferHelper.isETH(desc.srcToken)) {
            require(msg.value == desc.amount, "TransitSwap: invalid msg.value");
            swapAmount = desc.amount.sub(fee);
        } 
        else {
            TransferHelper.safeTransferFrom(desc.srcToken, msg.sender, address(this), desc.amount);
            TransferHelper.safeTransfer(desc.srcToken, desc.srcReceiver, desc.amount.sub(fee));
        }
        if (TransferHelper.isETH(desc.dstToken)) {
            beforeBalance = desc.dstReceiver.balance;
        } 
        else {
            beforeBalance = IERC20(desc.dstToken).balanceOf(desc.dstReceiver);
        }
    }

    function swap(TransitStructs.TransitSwapDescription calldata desc, TransitStructs.CallbytesDescription calldata callbytesDesc) external payable nonReentrant whenNotPaused {
        require(callbytesDesc.calldatas.length > 0, "TransitSwap: data should be not zero");
        require(desc.amount > 0, "TransitSwap: amount should be greater than 0");
        require(desc.dstReceiver != address(0), "TransitSwap: receiver should be not address(0)");
        require(desc.minReturnAmount > 0, "TransitSwap: minReturnAmount should be greater than 0");
        if (callbytesDesc.flag == uint8(TransitStructs.Flag.aggregate)) {
            require(desc.srcToken == callbytesDesc.srcToken, "TransitSwap: invalid callbytesDesc");
        }
        (uint256 swapAmount, uint256 fee, uint256 beforeBalance) = _beforeSwap(desc);
        //bytes4(keccak256(bytes('callbytes(TransitStructs.CallbytesDescription)')));
        (bool success, bytes memory result) = _transit_swap.call{value:swapAmount}(abi.encodeWithSelector(0xccbe4007, callbytesDesc));
        if (!success) {
            revert(RevertReasonParser.parse(result,"TransitSwap:"));
        } 
        uint256 returnAmount = 0;
        if (TransferHelper.isETH(desc.dstToken)) {
            returnAmount = desc.dstReceiver.balance.sub(beforeBalance);
            require(returnAmount >= desc.minReturnAmount, "TransitSwap: insufficient return amount");
        } 
        else {
            returnAmount = IERC20(desc.dstToken).balanceOf(desc.dstReceiver).sub(beforeBalance);
            require(returnAmount >= desc.minReturnAmount, "TransitSwap: insufficient return amount");
        }    
        _emitTransit(desc, fee, returnAmount);
    }

    function _beforeCross(TransitStructs.TransitSwapDescription calldata desc) private returns (uint256 swapAmount, uint256 fee, uint256 beforeBalance) {
        fee = desc.amount.mul(3).div(10000);
        if (TransferHelper.isETH(desc.srcToken)) {
            require(msg.value == desc.amount, "TransitSwap: invalid msg.value");
            swapAmount = desc.amount.sub(fee);
        } 
        else {
            beforeBalance = IERC20(desc.srcToken).balanceOf(_transit_swap);
            TransferHelper.safeTransferFrom(desc.srcToken, msg.sender, address(this), desc.amount);
            TransferHelper.safeTransfer(desc.srcToken, _transit_swap, desc.amount.sub(fee));
        }
    }

    function cross(TransitStructs.TransitSwapDescription calldata desc, TransitStructs.CallbytesDescription calldata callbytesDesc) external payable nonReentrant whenNotPaused {
        require(callbytesDesc.calldatas.length > 0, "TransitSwap: data should be not zero");
        require(desc.amount > 0, "TransitSwap: amount should be greater than 0");
        require(desc.srcToken == callbytesDesc.srcToken, "TransitSwap: invalid callbytesDesc");
        (uint256 swapAmount, uint256 fee, uint256 beforeBalance) = _beforeCross(desc);
        //bytes4(keccak256(bytes('callbytes(TransitStructs.CallbytesDescription)')));
        (bool success, bytes memory result) = _transit_swap.call{value:swapAmount}(abi.encodeWithSelector(0xccbe4007, callbytesDesc));
        if (!success) {
            revert(RevertReasonParser.parse(result,"TransitSwap:"));
        }
        if (!TransferHelper.isETH(desc.srcToken)) {
            require(IERC20(desc.srcToken).balanceOf(_transit_swap) >= beforeBalance, "TransitSwap: invalid cross");
        }
        _emitTransit(desc, fee, 0);
    }

    function _emitTransit(TransitStructs.TransitSwapDescription calldata desc, uint256 fee, uint256 returnAmount) private {
        emit TransitSwapped(
            desc.srcToken, 
            desc.dstToken, 
            desc.dstReceiver, 
            msg.sender,  
            desc.amount, 
            returnAmount, 
            desc.minReturnAmount, 
            fee, 
            block.timestamp
        );
    }

    function withdrawTokens(address[] memory tokens, address recipient) external onlyExecutor {
        for(uint index; index < tokens.length; index++) {
            uint amount;
            if(TransferHelper.isETH(tokens[index])) {
                amount = address(this).balance;
                TransferHelper.safeTransferETH(recipient, amount);
            } else {
                amount = IERC20(tokens[index]).balanceOf(address(this));
                TransferHelper.safeTransferWithoutRequire(tokens[index], recipient, amount);
            }
            emit Withdraw(tokens[index], msg.sender, recipient, amount);
        }
    }
}