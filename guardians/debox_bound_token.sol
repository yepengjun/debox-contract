// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.16;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./utils/DateTime.sol";
import "./interfaces/IERC5192.sol";

contract DeBoxBoundToken is ERC721, DateTime, Ownable {

    struct TokenMeta {
        uint256 period;
        bytes32 meta;
    }    
    string  private _baseURIextended;
    uint256 private _tokenId = 0;
    uint256 public  _mtype = 0;
    address public  _proxy;
    mapping(uint256 => TokenMeta) public  _tokenMetas;

    event Mint(address sender, uint256 id, string meta, uint256 period, uint256 mtype);
    event ModifyProxy(address sender, address ca);

    constructor(string memory uri, uint256 mtype) ERC721("DeBox MOD", "DeBox Bound Token") {
        _baseURIextended = uri;
        _mtype = mtype;
    }

    modifier callerIsProxy(uint256 mtype) {
        require(_proxy == msg.sender && _mtype == mtype);
        _;
    }

    function modifyProxy(address ca) external onlyOwner {
        require(ca != address(0), "Invalid address");
        _proxy = ca;
        emit ModifyProxy(msg.sender, ca);
    }
    
    function _baseURI() internal view override returns (string memory) {
        return _baseURIextended;
    }

    function setBaseURI(string memory uri) external onlyOwner() {
        _baseURIextended = uri;
    }

    function _stringToBytes32(string memory source) internal pure returns (bytes32 result) {
        bytes memory temp = bytes(source);
        require(temp.length <= 32, "Ths source string exceeds 32 bytes");
        assembly {
            result := mload(add(source, 32))
        }
    }

    function _verifyPeriod(uint256 period) internal view returns (bool) {
        uint256 year = getYear(block.timestamp);
        uint256 month = (getMonth(block.timestamp) + 1) / 2;
        return period == year * 100 + month;
    }

    function verifyToken(uint256 id, string memory meta, uint256 mtype) external view callerIsProxy(mtype) returns (bool)  {
        require(ownerOf(id) == tx.origin, "The caller is not the owner of the token");
        return _tokenMetas[id].meta == _stringToBytes32(meta) && _verifyPeriod(_tokenMetas[id].period);
    }

   function safeMint(string memory meta, uint256 period, uint256 mtype) external callerIsProxy(mtype) returns (uint256) {
        require(_verifyPeriod(period), "The period is invalid");
        _tokenId += 1;
        _tokenMetas[_tokenId] = TokenMeta({
                meta: _stringToBytes32(meta),
                period: period
            });
        _safeMint(tx.origin, _tokenId);
        emit Mint(tx.origin, _tokenId, meta, period, mtype);
        return _tokenId;
    }

    function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize) internal override (ERC721) {
        require(from == address(0) || to == address(0), "The token is non-transferable");
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    function supportsInterface(bytes4 _interfaceId) public view override(ERC721) returns (bool) {
        return _interfaceId == type(IERC5192).interfaceId || super.supportsInterface(_interfaceId);
    }
}
