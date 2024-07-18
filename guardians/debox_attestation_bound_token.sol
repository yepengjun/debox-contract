// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./library/VerifyAttestation.sol";

contract AttestationsDeBoxBoundToken is ERC721,VerifyAttestation, Ownable {

    uint256 private _tokenId = 0;
    string  private _baseURIextended;
    string private conferenceID = "2";
    address _attestorKey = 0x538080305560986811c3c1A2c5BCb4F37670EF7e;
    address _issuerKey = 0xE0e8c66e1025A564C70255A3c3059247aec6c54f;
    address public _signOwner = 0x96216849c49358B10257cb55b28eA603c874b05E;
    mapping(bytes => bool) _tokenBytesMinted;
    mapping(address => bool) _allowMinted;
    bool private _preAllowMinted = true;

    event ConferenceIDUpdated(string oldID, string newID);

    constructor(string memory baseURI_) ERC721("EDCON 2023 Bager", "EDCON DeBox") {
        _baseURIextended = baseURI_;
    }

    modifier callerIsUser() {
        require(tx.origin == _msgSender(), "The caller is another contract");
        _;
    }

    function _baseURI() internal view override returns (string memory) {
        return _baseURIextended;
    }

    function setBaseURI(string memory base_uri) external onlyOwner() {
        _baseURIextended = base_uri;
    }

    function modifySignOwner(address new_sign_owner) external onlyOwner {
        require(new_sign_owner != address(0), "Invalid address");
        _signOwner = new_sign_owner;
    }

    function modifyPreAllowMinted(bool preAllowMint) external onlyOwner {
        _preAllowMinted = preAllowMint;
    }

    function updateAttestationKeys(address newattestorKey, address newIssuerKey) public onlyOwner {
        _attestorKey = newattestorKey;
        _issuerKey = newIssuerKey;
    }

    function updateConferenceID(string calldata newValue) public onlyOwner {
        emit ConferenceIDUpdated(conferenceID, newValue);
        conferenceID = newValue;
    }

    function verify(bytes memory attestation) public view returns (address attestor, address ticketIssuer, address subject, bytes memory ticketId, bytes memory conferenceId, bool attestationValid){
        ( attestor, ticketIssuer, subject, ticketId, conferenceId, attestationValid) = _verifyTicketAttestation(attestation);
    }

    function alllowMint(bytes memory signature) public callerIsUser() {
        require(_preAllowMinted, "Alllow Mint not start");
        require(_allowMinted[msg.sender] == false, "Current address already minted");
        bytes32 messageHash = keccak256(abi.encodePacked(_signOwner));
        verifySignature(messageHash,signature);
        _allowMinted[msg.sender] = true;
        _mint(msg.sender, _tokenId);
        _tokenId = _tokenId + 1;
    }

    function mintUsingAttestation(bytes memory attestation) public callerIsUser() {
        (address subject,bytes memory tokenBytes,bytes memory conferenceBytes,bool timeStampValid) = verifyTicketAttestation(attestation, _attestorKey, _issuerKey);
        uint256 tokenId = bytesToUint(tokenBytes);
        require(subject != address(0) && tokenId != 0 && timeStampValid && compareStrings(conferenceBytes, conferenceID), "Attestation not valid");
        require(tokenBytes.length < 33 , "TokenID overflow");
        require(_tokenBytesMinted[tokenBytes] == false, "TokenID already minted");
        _tokenBytesMinted[tokenBytes] = true;
        _mint(subject, _tokenId);
        _tokenId = _tokenId + 1;
    }

    function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize) internal override (ERC721) {
        require(from == address(0) || to == address(0), "The token is non-transferable");
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    function supportsInterface(bytes4 _interfaceId) public view override(ERC721) returns (bool) {
        return  super.supportsInterface(_interfaceId);
    }

    function compareStrings(bytes memory s1, string memory s2) private pure returns(bool) {
        return keccak256(abi.encodePacked(s1)) == keccak256(abi.encodePacked(s2));
    }

    function verifySignature(bytes32 messageHash, bytes memory signature) public view returns (bool) {
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }
        if (v < 27) {
            v += 27;
        }
        address signer = ecrecover(messageHash, v, r, s);
        require(signer == _signOwner, "Invalid signature");
        return true;
    }
}