// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./libraries/TransferHelper.sol";
import "./libraries/Ownable.sol";
import "./interfaces/IERC20.sol";
import "./libraries/ReentrancyGuard.sol";
/**
 * @title DeboxDexRootRouter
 * @author Debox Team
 * @notice Trade Router for DEX
 */

contract DeboxDexRootRouter is Ownable, ReentrancyGuard {
    using TransferHelper for address;

    event SetSubRouter(address subRouter, address approveTo);

    /**
     * @dev Swap Event
     * @param acct is the msg.sender address
     * @param subRouter is used swap router.
     * @param tokenIn is the token address to swap.
     * @param tokenOut is the token address to receive.
     * @param amountIn is the token amount to swap,included swap fee.
     * @param amountOut is the amount of `tokenOut` token received by the `acct` address.
     */
    event Swap(
        address acct,
        address subRouter,
        address tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        bytes32 remarkId
    );

    uint256 private constant _UNITS = 10000;
    // feeTo is the address to receive fee.
    address public feeTo;
    uint256 public feeRate = 30; // 0.3%

    // subRouter is the address of subRouter.
    mapping(address => address) public isSubRouter;

    constructor(address fee, address subRouter, address approveTo) Ownable(msg.sender) {
        require(fee != address(0), "zero");
        feeTo = fee;
        setSubRouter(subRouter, approveTo);
    }

    /**
     * @notice Swap tokenIn to tokenOut.
     * @param tokenIn is the token address to swap.
     * @param tokenOut is the token address to receive.
     * @param amountIn  is the token amount to swap.
     * @param amountOutMin is the min token amount to receive.
     * @param subRouter is the subRouter address.
     * @param subRouterData is the subRouter data.
     * @param remarkId is arbitrary data to be recorded in logs.
     * @dev when tokenIn is native token(ETH), msg.value must be equal to amountIn
     * and tokenIn address is 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE or 0x0.
     */
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin,
        address subRouter,
        bytes calldata subRouterData,
        bytes32 remarkId
    ) external payable nonReentrant {
        require(amountIn > 0, "amount must be greater than zero");
        require(isSubRouter[subRouter] != address(0), "subRouter is not allowed");

        // swap tokenIn to tokenOut
        uint256 fee = amountIn * feeRate / _UNITS;
        uint256 swapAmount = amountIn - fee;
        uint256 ethValue;
        if (tokenIn.isETH()) {
            require(msg.value == amountIn, "msg.value must be equal to amountIn");
            if (fee > 0) TransferHelper.safeTransferETH(feeTo, fee);
            ethValue = swapAmount;
        } else {
            require(msg.value == 0, "msg.value must be zero");
            tokenIn.safeTransferFrom(msg.sender, address(this), swapAmount);
            if (fee > 0) tokenIn.safeTransferFrom(msg.sender, feeTo, fee);
            // approve  and check balance
            address subRouterApproveTo = isSubRouter[subRouter];
            if (IERC20(tokenIn).allowance(address(this), subRouterApproveTo) < swapAmount) {
                tokenIn.safeApprove(subRouterApproveTo, 0); //reset allowance
                tokenIn.safeApprove(subRouterApproveTo, type(uint256).max);
            }
            require(IERC20(tokenIn).balanceOf(address(this)) >= swapAmount, "balance not enough");
        }
        uint256 balaneBefore = _getBalance(tokenOut);
        (bool success,) = subRouter.call{value: ethValue}(subRouterData);
        require(success, "subRouter call failed");

        uint256 finalAmountOut = _getBalance(tokenOut) - balaneBefore;
        require(finalAmountOut >= amountOutMin, "insufficient output amount");
        // send tokenOut to msg.sender, note: unchecked receive token amount.
        if (tokenOut.isETH()) {
            TransferHelper.safeTransferETH(msg.sender, finalAmountOut);
        } else {
            tokenOut.safeTransfer(msg.sender, finalAmountOut);
        }

        address _tokenIn = tokenIn; // too deep
        uint256 _amountIn = amountIn;
        emit Swap(msg.sender, subRouter, _tokenIn, tokenOut, _amountIn, finalAmountOut, remarkId);
    }

    //////////////////////////// onlyOwner ////////////////////////////

    // setFeeTo is used to set feeTo address.
    function setFeeTo(address newFeeTo) external onlyOwner {
        require(newFeeTo != address(0), "new feeTo is the zero address");
        feeTo = newFeeTo;
    }

    function setFeeRate(uint256 newFeeRate) external onlyOwner {
        require(newFeeRate <= _UNITS / 10, "feeRate must be less than or equal to 10%");
        feeRate = newFeeRate;
    }

    function setSubRouter(address subRouter, address approveTo) public onlyOwner {
        require(subRouter != address(0), "zero");
        require(approveTo != address(0), "zero");
        isSubRouter[subRouter] = approveTo;
        emit SetSubRouter(subRouter, approveTo);
    }

    // safeWithdraw is used to withdraw token or eth.
    function withdraw(address token, uint256 amount) external onlyOwner {
        if (token.isETH()) {
            TransferHelper.safeTransferETH(msg.sender, amount);
        } else {
            token.safeTransfer(msg.sender, amount);
        }
    }

    function _getBalance(address token) private view returns (uint256) {
        return token.isETH() ? address(this).balance : IERC20(token).balanceOf(address(this));
    }

    // receive eth from subRouter
    receive() external payable {}
}
