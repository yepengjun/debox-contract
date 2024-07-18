// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
/**
 * @title BoxAllocate
 * @author Debox Team
 * @notice Allocate box
 */

contract Box is Ownable,ReentrancyGuard {
    using SignatureChecker for address;
    struct BoxMeta {
        address owner;
        uint256 expireTime;
        uint256 saleCnt;
        uint256 tradeCnt;
        uint256 rewards;
        uint256 index;
    }  

    struct BoxPreOrder {
        uint256 cnt;
        address owner;
        bool allocate;
    } 

    struct BoxAllocate {
        uint256 orderIndex;
        uint256 cnt;
    } 

    struct BoxPrice {
        uint256 boxCnt;
        uint256 price;
    } 

    struct UserInfo {
        uint256 cnt;
        uint256 index;
        uint256 claims;
    } 

    uint256 public constant PER_BOX_PRICE = 10**14;
    uint256 public constant PER_BOX_GAS = 10**15;
    uint256 public constant BOX_SALE_PERIOD = 3600;
    uint256 public constant BOX_SALE_CNT = 100;
    uint256 public BOX_TRADE_FEE = 10;
    uint256 public BOX_OWNER_FEE = 4;
    uint256 public BOX_PLATFORM_FEE = 2;
    uint256 public BOX_FARM_FEE = 4;

    mapping(address => uint256) public _nonces;
    address public _signOwner = 0x96216849c49358B10257cb55b28eA603c874b05E;
    //meta box balance
    mapping(bytes => mapping(address => UserInfo)) public _metaBoxUserInfo;
    mapping(bytes => BoxMeta) private _metaBoxs;
    mapping(bytes => BoxPreOrder[]) private _boxPreOrders;
    mapping(uint256 => uint256) public _boxPrices;
    address payable public _feeReciever;

    enum TradeType{DEFAUL,BUY,SELL}
    enum FeeType{OWNER,PLATFORM,FARM}

    event BoxStart(address indexed sender, string meta, uint256 expireTime);
    event BoxSale(address indexed sender, bytes meta, uint256 order_index, uint256 box_cnt);
    event BoxTrade(address indexed sender, bytes meta,uint256 amount,uint256 fees, TradeType trade_type, uint256 box_cnt);
    event BoxAllocateRefund(address indexed sender, bytes meta, uint256 order_index);
    event DistributeFees(address indexed sender, bytes meta, uint256 fees, FeeType fee_type);
    event BoxClaim(address indexed sender, bytes meta, uint256 claim_amount);

    constructor() Ownable(msg.sender) {
        _feeReciever = payable(msg.sender);
    }

    function setFeeReciever (address fee_reciever) external onlyOwner {
      require(address(0) != fee_reciever,"fee_reciever is zero addresss");
      _feeReciever = payable(fee_reciever);
    }

    function setBoxFee(uint256 owner,uint256 platform,uint256 farm) external onlyOwner {
        BOX_OWNER_FEE = owner;
        BOX_PLATFORM_FEE = platform;
        BOX_FARM_FEE = farm;
        BOX_TRADE_FEE = BOX_OWNER_FEE+BOX_PLATFORM_FEE+BOX_FARM_FEE;
    }

    function getBoxUserInfo(bytes memory meta,address ca) public view returns (UserInfo memory) {
        return _metaBoxUserInfo[meta][ca];
    }

    function getBuyAmount(bytes memory meta,uint256 cnt) external view returns(uint256,uint256){
        (uint256 tradeTotalAmount,uint256 fee) = _calculateBuyAmount(meta,cnt);
        return (tradeTotalAmount,fee);
    }

    function getSellAmount(bytes memory meta,uint256 cnt) external view returns(uint256,uint256){
        (uint256 tradeTotalAmount,uint256 fee) = _calculateSellAmount(meta,cnt);
        return (tradeTotalAmount,fee);
    }

    function startBox(string memory meta, bytes memory signature) external {
        bytes memory metaBytes = _stringToBytes(meta);
        require(_metaBoxs[metaBytes].expireTime == 0, "The box is started");
        bytes32 message = keccak256(abi.encodePacked(msg.sender, meta, _nonces[_msgSender()]));
        require(_signOwner.isValidSignatureNow(message,signature), "The signature is invalid");
        uint256 expireTime = block.timestamp+BOX_SALE_PERIOD;
        _metaBoxs[metaBytes] = BoxMeta({
                owner: msg.sender,
                expireTime: expireTime,
                saleCnt:0,
                tradeCnt:0,
                rewards:0,
                index:0
        });
        emit BoxStart(msg.sender,meta,expireTime);
    }

    function boxPreSale(bytes memory meta, uint256 box_cnt) external payable {
        require(_metaBoxs[meta].expireTime -  BOX_SALE_PERIOD <=  block.timestamp && _metaBoxs[meta].expireTime >= block.timestamp, "The box sale is not process");
        require(box_cnt > 0 ,"Box cnt is zero");
        require(box_cnt * PER_BOX_PRICE + PER_BOX_GAS == msg.value ,"Insufficient Box amount");
        _boxPreOrders[meta].push(BoxPreOrder({
                owner: msg.sender,
                cnt: box_cnt,
                allocate:false
            }));
        _metaBoxs[meta].saleCnt = _metaBoxs[meta].saleCnt+box_cnt;
        emit BoxSale(msg.sender,meta,_boxPreOrders[meta].length-1,box_cnt);
    }
    
    function boxAllocate(bytes memory meta,BoxAllocate[] memory box_allocates) external onlyOwner {
        require(_metaBoxs[meta].expireTime > 0  &&_metaBoxs[meta].expireTime < block.timestamp, "The box sale in process");
        BoxPreOrder[] storage boxPreOrders = _boxPreOrders[meta];
        if (boxPreOrders.length >= box_allocates.length) {
            for (uint i = 0; i < box_allocates.length; i++) {
                BoxAllocate memory box_allocate = box_allocates[i];
                BoxPreOrder storage boxPreOrder = boxPreOrders[box_allocate.orderIndex];
                if (box_allocate.cnt > 0 && !boxPreOrder.allocate) {
                    require(box_allocate.cnt <= boxPreOrder.cnt,"Insufficient box allocate cnt");
                    boxPreOrder.allocate = true;
                    _metaBoxUserInfo[meta][boxPreOrder.owner].cnt = _metaBoxUserInfo[meta][boxPreOrder.owner].cnt + box_allocate.cnt;
                }
                if (boxPreOrder.cnt > box_allocate.cnt ) {
                    uint256 refound = (boxPreOrder.cnt - box_allocate.cnt)*PER_BOX_PRICE;
                    (bool res,) = payable(boxPreOrder.owner).call{ value: refound }("");
                    require(res, "The refound is failed");
                }
                emit BoxAllocateRefund(msg.sender,meta,box_allocate.orderIndex);
            }
        }  
    }

    function boxBuy(bytes memory meta,uint256 cnt) external payable nonReentrant {
        require(cnt > 0,"Insufficient Box cnt");
        (uint256 tradeTotalAmount, uint256 fee)  = _calculateBuyAmount(meta,cnt);
        require(msg.value == tradeTotalAmount + fee ,"Insufficient pay amount");
        if (msg.value > tradeTotalAmount + fee ) {
            (bool res,) = payable(msg.sender).call{ value: msg.value - tradeTotalAmount - fee }("");
            require(res, "The buy is failed");
        }
        _updateUserInfo(meta,cnt,TradeType.BUY);
        _distributeFees(meta,fee);
        emit BoxTrade(msg.sender,meta,tradeTotalAmount,fee,TradeType.BUY,cnt);
    }

    function boxSell(bytes memory meta,uint256 cnt) external nonReentrant {
        require(cnt > 0,"Insufficient Box cnt");
        require(_metaBoxUserInfo[meta][msg.sender].cnt == cnt,"Insufficient Box balance");
        (uint256 tradeTotalAmount, uint256 fee)  = _calculateSellAmount(meta,cnt);
        (bool res,) = payable(msg.sender).call{ value: tradeTotalAmount - fee }("");
        require(res, "The sell is failed");
        _updateUserInfo(meta,cnt,TradeType.SELL);
        _distributeFees(meta,fee);
        emit BoxTrade(msg.sender,meta,tradeTotalAmount,fee,TradeType.SELL,cnt);
    }

    function boxClaim(bytes memory meta) external {
        UserInfo storage userInfo = _metaBoxUserInfo[meta][msg.sender];  
        require(userInfo.claims > 0,"The claim amount is zero");
        userInfo.claims = 0;
        userInfo.index = _metaBoxs[meta].index;
        (bool res,) = payable(msg.sender).call{ value: userInfo.claims}("");
        require(res, "The claim is failed");
        emit BoxClaim(msg.sender,meta,userInfo.claims);
    }

    function _calculateBuyAmount(bytes memory meta,uint256 cnt) internal view returns(uint256,uint256){
        require(cnt > 0,"Insufficient Box cnt");
        uint256 tradeTotalAmount = 0;
        uint256 tradeCntBefore = _metaBoxs[meta].tradeCnt;
        for (uint256 i = 0; i < cnt; i++) {
            uint256 tradeCntAfter = tradeCntBefore +1;
            uint256 price = PER_BOX_PRICE;
            if (tradeCntAfter > BOX_SALE_CNT) {
                price = _boxPrices[tradeCntAfter];
                if (price <= PER_BOX_PRICE) {
                    price = _calculateBoxPrice(tradeCntAfter);
                }
            }
            tradeTotalAmount = tradeTotalAmount + price;
            tradeCntBefore = tradeCntAfter;
        }
        uint256 fee = Math.mulDiv(tradeTotalAmount,BOX_TRADE_FEE,100);
        return (tradeTotalAmount,fee);
    }

    function _calculateSellAmount(bytes memory meta,uint256 cnt) internal view returns(uint256,uint256){
        require(cnt > 0,"Insufficient Box cnt");
        require(_metaBoxUserInfo[meta][msg.sender].cnt >= cnt,"Insufficient Box balance");
        uint256 tradeTotalAmount = 0;
        uint256 tradeCntBefore = _metaBoxs[meta].tradeCnt;
        for (uint256 i = 0; i < cnt; i++) {
            uint256 tradeCntAfter = tradeCntBefore -1;
            uint256 price = PER_BOX_PRICE;
            if (tradeCntBefore > BOX_SALE_CNT) {
                price = _boxPrices[tradeCntBefore];
                if (price <= PER_BOX_PRICE) {
                    price = _calculateBoxPrice(tradeCntBefore);
                }
            }
            tradeTotalAmount = tradeTotalAmount + price;
            tradeCntBefore = tradeCntAfter;
        }
        uint256 fee = Math.mulDiv(tradeTotalAmount,BOX_TRADE_FEE,100);
        return (tradeTotalAmount,fee);
    }

    function _distributeFees(bytes memory meta, uint256 fees) internal {
        BoxMeta storage boxMeta = _metaBoxs[meta];
        if (fees > 0 ) {
            uint256 ownerFees = Math.mulDiv(fees,BOX_OWNER_FEE,BOX_TRADE_FEE);
            boxMeta.rewards = boxMeta.rewards + ownerFees;
            uint256 FarmAllFees = Math.mulDiv(fees,BOX_FARM_FEE,BOX_TRADE_FEE);
            boxMeta.index = boxMeta.index + FarmAllFees/boxMeta.tradeCnt;
            uint256 platfromFees = fees - ownerFees - FarmAllFees;
            (bool owner_res,) = payable(boxMeta.owner).call{ value: ownerFees }("");
            (bool sign_res,) = payable(_feeReciever).call{ value: platfromFees }("");
            require(owner_res && sign_res, "The trade is failed");
            emit DistributeFees(_feeReciever,meta,platfromFees,FeeType.PLATFORM);
            emit DistributeFees(boxMeta.owner,meta,ownerFees,FeeType.OWNER);
        }
    }

    function _updateUserInfo(bytes memory meta,uint256 cnt,TradeType trade_type) internal {
      if (cnt > 0) {
          UserInfo storage userInfo = _metaBoxUserInfo[meta][msg.sender];  
          userInfo.claims += (_metaBoxs[meta].index-userInfo.index)*userInfo.cnt;
          if (trade_type == TradeType.BUY) {
              userInfo.cnt += cnt;
          }else {
              userInfo.cnt -= cnt;
          }
          userInfo.index = _metaBoxs[meta].index;
      }
    }

    // 0.0005*x^(1.25)-0.15
    function _calculateBoxPrice(uint256 x) internal pure returns (uint256) {
        uint256 boxPrice = 100;
        if (x > 1000) {
            boxPrice = (x - 1000)**2 / 9 + 100*(x - 100)/3 + 100;
        }else if (x > 100) {
            boxPrice = 100 * (x - 100) / 3 + 100;
        }
        return boxPrice*10**14;
    }

    function _stringToBytes(string memory source) public pure returns (bytes memory) {
      bytes memory result = bytes(source);
      require(result.length <= 32, "Ths source string exceeds 32 bytes");
      return result;
  }
}