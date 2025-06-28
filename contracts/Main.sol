// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {Ownable} from "./Ownable.sol";
import {Pausable} from "./Pausable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Main is Ownable, Pausable, ReentrancyGuard {
    struct Listing {
        address seller;
        address nftContract;
        uint256 tokenId;
        uint256 price;
        bool active;
    }
    mapping(bytes32 => Listing) public listings;
    mapping(address => uint256) private _balances;

    event Deposited(address indexed user, uint256 amount);
    event NFTListed(
        address indexed seller,
        address indexed nftContract,
        uint256 indexed tokenId,
        uint256 price
    );
    event PriceUpdated(
        address indexed seller,
        address indexed nftContract,
        uint256 indexed tokenId,
        uint256 oldPrice,
        uint256 newPrice
    );
    event NFTDelisted(
        address indexed seller,
        address indexed nftContract,
        uint256 indexed tokenId
    );
    event NFTPurchased(
        address indexed buyer,
        address indexed nftContract,
        uint256 indexed tokenId,
        uint256 price
    );
    event NFTsTraded(
        address indexed proposer,
        address[] offeredContracts,
        uint256[] offeredTokenIds,
        address[] requestedContracts,
        uint256[] requestedTokenIds,
        uint256 totalOffered,
        uint256 totalRequested,
        uint256 extraPaid
    );

    error DepositInsufficientValue(string message);

    constructor() Ownable(_msgSender()) {}

    receive() external payable {}

    fallback() external payable {}

    function pause() external onlyOwner whenNotPaused {
        _pause();
    }

    function unpause() external onlyOwner whenPaused {
        _unpause();
    }

    function balanceOf(
        address account
    ) external view whenNotPaused returns (uint256) {
        return _balances[account];
    }

    function deposit() external payable whenNotPaused {
        if (msg.value <= 0) {
            revert DepositInsufficientValue("Less than accepted");
        } else if (_msgSender().balance < msg.value) {
            revert DepositInsufficientValue("Insufficient balance");
        }

        _balances[msg.sender] += msg.value;
        emit Deposited(msg.sender, msg.value);
    }

    function listNFT(
        address nftContract,
        uint256 tokenId,
        uint256 price
    ) external whenNotPaused nonReentrant {
        require(price > 0, "Price > 0");

        bytes32 key = keccak256(abi.encodePacked(nftContract, tokenId));
        require(!listings[key].active, "Already listed");

        IERC721(nftContract).transferFrom(msg.sender, address(this), tokenId);

        listings[key] = Listing({
            seller: msg.sender,
            nftContract: nftContract,
            tokenId: tokenId,
            price: price,
            active: true
        });

        emit NFTListed(msg.sender, nftContract, tokenId, price);
    }

    function updatePrice(
        address nftContract,
        uint256 tokenId,
        uint256 newPrice
    ) external whenNotPaused nonReentrant {
        bytes32 key = keccak256(abi.encodePacked(nftContract, tokenId));
        Listing storage lst = listings[key];

        require(lst.active, "Not listed");
        require(lst.seller == msg.sender, "Not seller");
        require(newPrice > 0, "Price > 0");

        uint256 old = lst.price;
        lst.price = newPrice;

        emit PriceUpdated(msg.sender, nftContract, tokenId, old, newPrice);
    }

    function cancelListing(
        address nftContract,
        uint256 tokenId
    ) external whenNotPaused nonReentrant {
        bytes32 key = keccak256(abi.encodePacked(nftContract, tokenId));
        Listing storage lst = listings[key];

        require(lst.active, "Not listed");
        require(lst.seller == msg.sender, "Not seller");

        lst.active = false;
        IERC721(nftContract).transferFrom(address(this), msg.sender, tokenId);

        emit NFTDelisted(msg.sender, nftContract, tokenId);
    }

    function buyNFT(
        address nftContract,
        uint256 tokenId
    ) external payable whenNotPaused nonReentrant {
        bytes32 key = keccak256(abi.encodePacked(nftContract, tokenId));
        Listing storage lst = listings[key];

        require(lst.active, "Not for sale");
        require(msg.value == lst.price, "Wrong ETH amount");

        lst.active = false;

        (bool sent, ) = payable(lst.seller).call{value: msg.value}("");
        require(sent, "Payment failed");

        IERC721(nftContract).transferFrom(address(this), msg.sender, tokenId);

        emit NFTPurchased(msg.sender, nftContract, tokenId, lst.price);
    }

    function _collectAndDeactivate(
        address[] calldata contracts,
        uint256[] calldata tokenIds,
        bool isOffered
    ) private returns (uint total) {
        for (uint i = 0; i < contracts.length; i++) {
            bytes32 key = keccak256(
                abi.encodePacked(contracts[i], tokenIds[i])
            );
            Listing storage lst = listings[key];
            require(lst.active, "Not listed");
            if (isOffered) {
                require(lst.seller == msg.sender, "Not owner");
            } else {
                require(lst.seller != msg.sender, "Self-trade");
            }
            total += lst.price;
            lst.active = false;
        }
    }

    function tradeNFTs(
        address[] calldata offeredContracts,
        uint256[] calldata offeredTokenIds,
        address[] calldata requestedContracts,
        uint256[] calldata requestedTokenIds
    ) external payable whenNotPaused nonReentrant {
        require(
            offeredContracts.length > 0 && requestedContracts.length > 0,
            "Empty arrays"
        );
        require(
            offeredContracts.length == offeredTokenIds.length &&
                requestedContracts.length == requestedTokenIds.length,
            "Arrays mismatch"
        );

        uint totalOff = _collectAndDeactivate(
            offeredContracts,
            offeredTokenIds,
            true
        );
        uint totalReq = _collectAndDeactivate(
            requestedContracts,
            requestedTokenIds,
            false
        );

        uint extra = totalReq > totalOff ? totalReq - totalOff : 0;
        uint surplus = totalOff > totalReq ? totalOff - totalReq : 0;
        require(
            msg.value + _balances[msg.sender] >= extra,
            "Insufficient funds"
        );
        if (msg.value < extra) {
            _balances[msg.sender] -= (extra - msg.value);
        }

        for (uint i = 0; i < requestedContracts.length; i++) {
            bytes32 key = keccak256(
                abi.encodePacked(requestedContracts[i], requestedTokenIds[i])
            );
            Listing memory lst = listings[key];
            uint share = extra > 0 ? (lst.price * extra) / totalReq : 0;
            payable(lst.seller).transfer(lst.price + share);
            IERC721(requestedContracts[i]).transferFrom(
                address(this),
                msg.sender,
                requestedTokenIds[i]
            );
        }

        for (uint i = 0; i < offeredContracts.length; i++) {
            bytes32 key = keccak256(
                abi.encodePacked(offeredContracts[i], offeredTokenIds[i])
            );
            Listing memory lst = listings[key];
            IERC721(offeredContracts[i]).transferFrom(
                address(this),
                lst.seller,
                offeredTokenIds[i]
            );
        }

        if (surplus > 0) {
            _balances[msg.sender] += surplus;
        }
        emit NFTsTraded(
            msg.sender,
            offeredContracts,
            offeredTokenIds,
            requestedContracts,
            requestedTokenIds,
            totalOff,
            totalReq,
            extra
        );
    }
}
