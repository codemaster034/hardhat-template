// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/*
██████╗ ███████╗██╗   ██╗██╗ ██████╗ ██╗   ██╗███████╗    
██╔══██╗██╔════╝██║   ██║██║██╔═══██╗██║   ██║██╔════╝    
██║  ██║█████╗  ██║   ██║██║██║   ██║██║   ██║███████╗    
██║  ██║██╔══╝  ╚██╗ ██╔╝██║██║   ██║██║   ██║╚════██║    
██████╔╝███████╗ ╚████╔╝ ██║╚██████╔╝╚██████╔╝███████║    
╚═════╝ ╚══════╝  ╚═══╝  ╚═╝ ╚═════╝  ╚═════╝ ╚══════╝    
                                                          
        ██╗     ██╗ ██████╗██╗  ██╗███████╗               
        ██║     ██║██╔════╝██║ ██╔╝██╔════╝               
        ██║     ██║██║     █████╔╝ ███████╗               
        ██║     ██║██║     ██╔═██╗ ╚════██║               
        ███████╗██║╚██████╗██║  ██╗███████║               
        ╚══════╝╚═╝ ╚═════╝╚═╝  ╚═╝╚══════╝ BSC             
                                                         
            Devious Licks / 2021 / V1.12
*/

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract DeviousLicks is ERC721Enumerable, Ownable {
  using Strings for uint256;
  using ECDSA for bytes32;

  uint256 public constant DL_GIFT = 88; //88 Gift Amount
  uint256 public constant DL_PREPRICE = 0.35 ether;
  uint256 public constant DL_PRICE = 0.45 ether;
  uint256 public constant DL_MAX = 8888; //8888 Total Supply
  uint256 public constant DL_PER_MINT = 5; //Max per tx (public sale)
  uint256 public DL_PRIVATE = 800; //800 Presale Supply
  uint256 public DL_MAXMINT = 8800; //8800 Total Mintable (excluding gift)

  mapping(address => bool) public presalerList;
  mapping(address => uint256) public presalerListPurchases;

  string private _contractURI =
    "ipfs://bafybeiaraw7oqnot2bk3fgntlsegzqw2cranijne6tdynlzldyrwdhogve";
  string private _tokenBaseURI =
    "ipfs://QmR8aP6CpXJWN5129WUKau34xxToddoqiTNAUmq6sG1q9F/";

  string public proof;
  uint256 public giftedAmount;
  uint256 public publicAmountMinted;
  uint256 public privateAmountMinted;
  uint256 public presalePurchaseLimit = 2; //max presale mint per addr
  bool public presaleLive;
  bool public saleLive;
  bool public locked; // metadata lock

  constructor(string memory _name, string memory _symbol)
    ERC721(_name, _symbol)
  {}

  modifier notLocked() {
    require(!locked, "Contract metadata methods are locked");
    _;
  }

  function addToPresaleList(address[] calldata entries) external onlyOwner {
    for (uint256 i = 0; i < entries.length; i++) {
      address entry = entries[i];
      require(entry != address(0), "NULL_ADDRESS");
      require(!presalerList[entry], "DUPLICATE_ENTRY");

      presalerList[entry] = true;
    }
  }

  function removeFromPresaleList(address[] calldata entries)
    external
    onlyOwner
  {
    for (uint256 i = 0; i < entries.length; i++) {
      address entry = entries[i];
      require(entry != address(0), "NULL_ADDRESS");

      presalerList[entry] = false;
    }
  }

  function buy(uint256 tokenQuantity) external payable {
    require(saleLive, "SALE_CLOSED");
    require(!presaleLive, "ONLY_PRESALE");
    require(totalSupply() < DL_MAXMINT, "OUT_OF_STOCK");
    require(
      publicAmountMinted + tokenQuantity <= DL_MAXMINT - DL_PRIVATE,
      "EXCEED_PUBLIC"
    );
    require(tokenQuantity <= DL_PER_MINT, "EXCEED_DL_PER_MINT");
    require(DL_PRICE * tokenQuantity <= msg.value, "INSUFFICIENT_ETH");

    for (uint256 i = 0; i < tokenQuantity; i++) {
      publicAmountMinted++;
      _safeMint(msg.sender, totalSupply() + 1);
    }
  }

  //@dev mint to provide airdrop
  function devMint(uint256 tokenQuantity) external onlyOwner {
    require(!saleLive && presaleLive, "PRESALE_CLOSED");
    require(privateAmountMinted + tokenQuantity <= 100, "EXCEED_ALLOC");
    require(totalSupply() < DL_MAXMINT, "OUT_OF_STOCK");
    for (uint256 i = 0; i < tokenQuantity; i++) {
      privateAmountMinted++;
      _safeMint(msg.sender, totalSupply() + 1);
    }
  }

  function presaleBuy(uint256 tokenQuantity) external payable {
    require(!saleLive && presaleLive, "PRESALE_CLOSED");
    require(presalerList[msg.sender], "NOT_QUALIFIED");
    require(totalSupply() < DL_MAXMINT, "OUT_OF_STOCK");
    require(
      privateAmountMinted + tokenQuantity <= DL_PRIVATE,
      "EXCEED_PRIVATE"
    );
    require(
      presalerListPurchases[msg.sender] + tokenQuantity <= presalePurchaseLimit,
      "EXCEED_ALLOC"
    );
    require(DL_PREPRICE * tokenQuantity <= msg.value, "INSUFFICIENT_ETH");

    for (uint256 i = 0; i < tokenQuantity; i++) {
      privateAmountMinted++;
      presalerListPurchases[msg.sender]++;
      _safeMint(msg.sender, totalSupply() + 1);
    }
  }

  function gift(address[] calldata receivers) external onlyOwner {
    require(totalSupply() + receivers.length <= DL_MAX, "MAX_MINT");
    require(giftedAmount + receivers.length <= DL_GIFT, "GIFTS_EMPTY");

    for (uint256 i = 0; i < receivers.length; i++) {
      giftedAmount++;
      _safeMint(receivers[i], totalSupply() + 1);
    }
  }

  function withdraw() external onlyOwner {
    payable(msg.sender).transfer(address(this).balance);
  }

  function isPresaler(address addr) external view returns (bool) {
    return presalerList[addr];
  }

  function presalePurchasedCount(address addr) external view returns (uint256) {
    return presalerListPurchases[addr];
  }

  function walletOfOwner(address _owner)
    public
    view
    returns (uint256[] memory)
  {
    uint256 ownerTokenCount = balanceOf(_owner);
    uint256[] memory tokenIds = new uint256[](ownerTokenCount);
    for (uint256 i; i < ownerTokenCount; i++) {
      tokenIds[i] = tokenOfOwnerByIndex(_owner, i);
    }
    return tokenIds;
  }

  // Owner functions for enabling presale, sale, revealing and setting the provenance hash
  function lockMetadata() external onlyOwner {
    locked = true;
  }

  function togglePresaleStatus() external onlyOwner {
    presaleLive = !presaleLive;
  }

  function toggleSaleStatus() external onlyOwner {
    saleLive = !saleLive;
  }

  function setProvenanceHash(string calldata hash)
    external
    onlyOwner
    notLocked
  {
    proof = hash;
  }

  function setContractURI(string calldata URI) external onlyOwner notLocked {
    _contractURI = URI;
  }

  function contractURI() public view returns (string memory) {
    return _contractURI;
  }

  function setPresaleLimit(uint256 limit) external onlyOwner {
    presalePurchaseLimit = limit;
  }

  function setPrivateLimit(uint256 limit) external onlyOwner {
    DL_PRIVATE = limit;
  }

  function setBaseURI(string calldata URI) external onlyOwner notLocked {
    _tokenBaseURI = URI;
  }

  function tokenURI(uint256 tokenId)
    public
    view
    override(ERC721)
    returns (string memory)
  {
    require(_exists(tokenId), "Cannot query non-existent token");

    return string(abi.encodePacked(_tokenBaseURI, tokenId.toString()));
  }
}
