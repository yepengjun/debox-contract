// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./libraries/Ownable.sol";
import "./libraries/TransferHelper.sol";
import "./libraries/SafeMath.sol";
import "./libraries/ReentrancyGuard.sol";
import "./libraries/RevertReasonParser.sol";
import "./libraries/TransitStructs.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IUniswapV2Pair.sol";

contract TransitSwap is Ownable, ReentrancyGuard {

    using SafeMath for uint256;

    address private _transit_router;
    address private _wrapped;
    mapping(address => mapping(address => bool)) private _approves;

    event Receipt(address from, uint256 amount);
    event ChangeTransitRouter(address indexed previousRouter, address indexed newRouter);
    event ChangeTransitAllowed(address indexed previousAllowed, address indexed newAllowed);
    event Withdraw(address indexed token, address indexed executor, address indexed recipient, uint amount);
    
    constructor(address wrapped, address executor) Ownable(executor) {
        _wrapped = wrapped;
    }

    receive() external payable {
        emit Receipt(msg.sender, msg.value);
    }

    function transitRouter() public view returns (address) {
        return _transit_router;
    }

    function approves(address token, address caller) public view returns (bool) {
        return _approves[token][caller];
    }

    function wrappedNative() public view returns (address) {
        return _wrapped;
    }

    function changeTransitRouter(address newRouter) public onlyExecutor {
        address oldRouter = _transit_router;
        _transit_router = newRouter;
        emit ChangeTransitRouter(oldRouter, newRouter);
    }

    function callbytes(TransitStructs.CallbytesDescription calldata desc) external payable nonReentrant checkRouter {
        if (desc.flag == uint8(TransitStructs.Flag.aggregate)) {
            TransitStructs.AggregateDescription memory aggregateDesc = TransitStructs.decodeAggregateDesc(desc.calldatas);
            swap(desc.srcToken, aggregateDesc);
        } 
        else if (desc.flag == uint8(TransitStructs.Flag.swap)) {
            TransitStructs.SwapDescription memory swapDesc = TransitStructs.decodeSwapDesc(desc.calldatas);
            supportingFeeOn(swapDesc);
        }
        else if (desc.flag == uint8(TransitStructs.Flag.cross)) {
            TransitStructs.CrossDescription memory crossDesc = TransitStructs.decodeCrossDesc(desc.calldatas);
            cross(desc.srcToken, crossDesc);
        }
        else {
            revert("TransitSwap: invalid flag");
        }
    }

    function swap(address srcToken, TransitStructs.AggregateDescription memory desc) internal {
        require(desc.callers.length == desc.calls.length, "TransitSwap: invalid calls");
        require(desc.callers.length == desc.needTransfer.length, "TransitSwap: invalid callers");
        require(desc.calls.length == desc.amounts.length, "TransitSwap: invalid amounts");
        require(desc.calls.length == desc.approveProxy.length, "TransitSwap: invalid calldatas");
        uint256 callSize = desc.callers.length;
        for (uint index; index < callSize; index++) {
            require(desc.callers[index] != address(this), "TransitSwap: invalid caller");
            address approveAddress = desc.approveProxy[index] == address(0)? desc.callers[index]:desc.approveProxy[index];
            uint beforeBalance;
            if (TransferHelper.isETH(desc.dstToken)) {
                beforeBalance = address(this).balance;
            } 
            else {
                beforeBalance = IERC20(desc.dstToken).balanceOf(address(this));
            }
            if (!TransferHelper.isETH(srcToken)) {
                require(desc.amounts[index] == 0, "TransitSwap: invalid call.value");
                bool isApproved = _approves[srcToken][approveAddress];
                if (!isApproved) {
                    TransferHelper.safeApprove(srcToken, approveAddress, 2**256-1);
                    _approves[srcToken][approveAddress] = true;
                }
            }
            // 
            (bool success, bytes memory result) = desc.callers[index].call{value:desc.amounts[index]}(desc.calls[index]);
            if (!success) {
                revert(RevertReasonParser.parse(result,""));
            }
            if (desc.needTransfer[index] == 1) {
                uint afterBalance = IERC20(desc.dstToken).balanceOf(address(this));
                TransferHelper.safeTransfer(desc.dstToken, desc.receiver, afterBalance.sub(beforeBalance));
            } 
            else if (desc.needTransfer[index] == 2) {
                TransferHelper.safeTransferETH(desc.receiver, address(this).balance.sub(beforeBalance));
            }
        }
    }

    function supportingFeeOn(TransitStructs.SwapDescription memory desc) internal {
        require(desc.deadline >= block.timestamp, "TransitSwap: expired");
        require(desc.paths.length == desc.pairs.length, "TransitSwap: invalid calldatas");
        for (uint i; i < desc.paths.length; i++) {
            address[] memory path = desc.paths[i];
            address[] memory pair = desc.pairs[i];
            uint256 fee = desc.fees[i];
            for (uint256 index; index < path.length - 1; index++) {
                (address input, address output) = (path[index], path[index + 1]);
                (address token0,) = input < output ? (input, output) : (output, input);
                IUniswapV2Pair pairAddress = IUniswapV2Pair(pair[index]);
                uint amountInput;
                uint amountOutput;
                { 
                    // scope to avoid stack too deep errors
                    (uint reserve0, uint reserve1,) = pairAddress.getReserves();
                    (uint reserveInput, uint reserveOutput) = input == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
                    amountInput = IERC20(input).balanceOf(address(pairAddress)).sub(reserveInput);
                    // 
                    require(amountInput > 0, "TransitSwap: INSUFFICIENT_INPUT_AMOUNT");
                    require(reserveInput > 0 && reserveOutput > 0, "TransitSwap: INSUFFICIENT_LIQUIDITY");
                    uint amountInWithFee = amountInput.mul(fee);
                    uint numerator = amountInWithFee.mul(reserveOutput);
                    uint denominator = reserveInput.mul(10000).add(amountInWithFee);
                    amountOutput = numerator / denominator;
                }
                (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOutput) : (amountOutput, uint(0));
                address to = index < path.length - 2 ? pair[index + 1] : desc.receiver;
                pairAddress.swap(amount0Out, amount1Out, to, new bytes(0));
            }
        }
    }

    function cross(address srcToken, TransitStructs.CrossDescription memory crossDesc) internal {
        uint swapAmount;
        if (TransferHelper.isETH(srcToken)) {
            require(msg.value >= crossDesc.amount, "TransitSwap: Invalid msg.value");
            swapAmount = msg.value;
            if (crossDesc.needWrapped) {
                TransferHelper.safeDeposit(_wrapped, crossDesc.amount);
                TransferHelper.safeApprove(_wrapped, crossDesc.caller, swapAmount);
                swapAmount = 0;
            }
        } else {
            require(IERC20(srcToken).balanceOf(address(this)) >= crossDesc.amount, "TransitSwap: Invalid amount");
            TransferHelper.safeApprove(srcToken, crossDesc.caller, crossDesc.amount);
        }

        (bool success, bytes memory result) = crossDesc.caller.call{value:swapAmount}(crossDesc.calls);
        if (!success) {
            revert(RevertReasonParser.parse(result, ""));
        }
    }

    modifier checkRouter {
        require(msg.sender == _transit_router, "TransitSwap: invalid router");
        _;
    }

    function withdrawTokens(address[] memory tokens, address recipient) external onlyExecutor {
        for(uint index; index < tokens.length; index++) {
            uint amount;
            if (TransferHelper.isETH(tokens[index])) {
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