// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

interface ERC20Base {
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Transfer(address indexed from, address indexed to, uint256 value);
    function totalSupply() external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
    function balanceOf(address who) external view returns (uint256);
}

abstract contract IERC20 is ERC20Base {
    function transfer(address to, uint256 value) virtual external returns (bool);
    function transferFrom(address from, address to, uint256 value) virtual external returns (bool);
}

contract CErc20Storage {
    /**
     * @notice Underlying asset for this CToken
     */
    address public underlying;
}

abstract contract CErc20Interface is CErc20Storage {

    /*** User Interface ***/
    function balanceOf(address account) virtual external returns (uint);
    function exchangeRateStored() virtual external returns(uint);
    function mint(uint mintAmount) virtual external returns (uint);
    function redeem(uint redeemTokens) virtual external returns (uint);
    function redeemUnderlying(uint redeemAmount) virtual external returns (uint);

    /*** Admin Functions ***/

    function _addReserves(uint addAmount) virtual external returns (uint);
}

contract MyContract {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIdCounter;

    IERC20 public USDToken;
    CErc20Interface public cUSDToken;

    address public owner;
    modifier onlyOwner() {
        require(msg.sender == owner, "Only the owner can call this function");
        _;
    }

    // Mapping from token ID to owner address
    mapping(uint256 => address) private _owners;

    // Mapping owner address to token count
    mapping(address => uint256) private _balances;

    // Optional mapping for token URIs
    mapping(uint256 => string) private _tokenURIs;

    // Owner own nftIds
    mapping(address => mapping(uint256 => bool)) private _nftIdOwnerHave;

    mapping(address => mapping(uint256 => uint256)) public cUSDTBalance;

    uint256 public rateOfOneNFT = 1;

    uint256 private _totalSupply;

    constructor(
        address _usdtTokenAddress,
        address _cUSDTAddress
    ) {
        USDToken = IERC20(_usdtTokenAddress);
        cUSDToken = CErc20Interface(_cUSDTAddress);
        owner = msg.sender;
    }

    function _mintNFT(address to, uint256 tokenId) internal {
        unchecked {
            // Will not overflow unless all 2**256 token ids are minted to the same owner.
            // Given that tokens are minted one by one, it is impossible in practice that
            // this ever happens. Might change if we allow batch minting.
            // The ERC fails to describe this case.
            _balances[to] += 1;
        }
        _owners[tokenId] = to;
        _nftIdOwnerHave[to][tokenId] = true;
    }

    function _setTokenURI(uint256 tokenId, string memory _tokenURI) internal {
        _tokenURIs[tokenId] = _tokenURI;
    }

    function buyNFT(uint256 USDTtoken) public {
        require(USDTtoken >= rateOfOneNFT, "Amount is less to buy NFT");
        require(USDToken.balanceOf(msg.sender) >= rateOfOneNFT*1e6, "You have not enough token");
        // compound protocol logic
        // for supply and mint cToken to this contract
        require(
            USDToken.transferFrom(msg.sender, address(this), rateOfOneNFT*1e6),
            "Transfer failed"
        );
        require(
            USDToken.approve(address(cUSDToken), rateOfOneNFT*1e6),
            "Approval failed"
        );
        uint256 previousBal = cUSDToken.balanceOf(address(this));
        require(cUSDToken.mint(rateOfOneNFT*1e6) == 0, "Minting cUSDT failed");
        uint256 currentBal = cUSDToken.balanceOf(address(this));
        _tokenIdCounter.increment();
        uint256 tokenId = _tokenIdCounter.current();
        cUSDTBalance[msg.sender][tokenId] += currentBal-previousBal;
        _mintNFT(msg.sender, tokenId);
        string memory uri = string(abi.encodePacked("https://gateway.pinata.cloud/ipfs/QmbA2TGPiGSeyLwmCffEqhfjNhX6XJaS88ExywgQbgnaJP/",
            Strings.toString(tokenId),".json"));
        _setTokenURI(tokenId, uri);
        _totalSupply += (rateOfOneNFT*1e6);
    }

    function tokenURI(uint256 tokenId) public view returns (string memory) {
        require(_tokenIdCounter.current() >= tokenId, "Id does not exists");
        return _tokenURIs[tokenId];
    }

    function nftIdOwnerHave(address to, uint256 tokenId) public view returns(bool) {
        return _nftIdOwnerHave[to][tokenId];
    }

    function ownerOf(uint256 tokenId) public view returns(address) {
        require(_tokenIdCounter.current() >= tokenId, "Id does not exists");
        return _owners[tokenId];
    }

    function totalSupply() public view returns(uint256) {
        return _totalSupply;
    }

    function _burn(address to, uint256 tokenId) internal virtual {
        unchecked {
            // Cannot overflow, as that would require more tokens to be burned/transferred
            // out than the owner initially received through minting and transferring in.
            _balances[to] -= 1;
        }
        delete _owners[tokenId];

        if (bytes(_tokenURIs[tokenId]).length != 0) {
            delete _tokenURIs[tokenId];
        }
        _nftIdOwnerHave[to][tokenId] = false;
    }

    function withdrawToken(uint256 tokenId) public {
        require(_balances[msg.sender] >= 1, "No NFT");
        require(_nftIdOwnerHave[msg.sender][tokenId] == true, "Not Own this tokenId");
        _burn(msg.sender, tokenId);
        // compound protocol logic
        // to redeem token with interest accured by the cToken in this contract 
        require(
            cUSDToken.redeem(cUSDTBalance[msg.sender][tokenId]) == 0,
            "Redeem cUSDT failed"
        );
        cUSDTBalance[msg.sender][tokenId] = 0;
        require(USDToken.balanceOf(address(this)) >= rateOfOneNFT*1e6, "Contact to the Admin");
        USDToken.transfer(msg.sender, rateOfOneNFT*1e6);
        _totalSupply -= (rateOfOneNFT*1e6);
    }

    function contractUSDToken() view public returns(uint256) {
        require(USDToken.balanceOf(address(this)) >= _totalSupply, "No Balance");
        return USDToken.balanceOf(address(this)) - _totalSupply;
    }

    function withdrawOnlyOwner(uint256 amount) public onlyOwner {
        require(USDToken.balanceOf(address(this)) >= _totalSupply + amount, "Not enough tokens");
        USDToken.transfer(msg.sender, amount);
    }
}