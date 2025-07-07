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
    struct TradeVars {
        uint256 offLen;
        uint256 reqLen;
        uint256 totalOff;
        uint256 totalReq;
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
    error NFTsNotListed(uint[] badOff, uint[] badReq);

    constructor() Ownable(_msgSender()) {}

    receive() external payable {}

    function _makeKey(
        address contractAddr,
        uint256 tokenId
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(contractAddr, tokenId));
    }

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

    function listNFTs(
        address[] calldata nftContracts,
        uint256[] calldata tokenIds,
        uint256[] calldata prices
    ) external whenNotPaused nonReentrant {
        uint len = nftContracts.length;
        require(
            len > 0 && len == tokenIds.length && len == prices.length,
            "Array mismatch"
        );
        for (uint i = 0; i < len; i++) {
            uint256 price = prices[i];
            require(price > 0, "Price>0");
            address nftContract = nftContracts[i];
            uint256 tokenId = tokenIds[i];
            bytes32 key = keccak256(abi.encodePacked(nftContract, tokenId));
            require(!listings[key].active, "Already listed");
            IERC721(nftContract).transferFrom(
                msg.sender,
                address(this),
                tokenId
            );
            listings[key] = Listing({
                seller: msg.sender,
                nftContract: nftContract,
                tokenId: tokenId,
                price: price,
                active: true
            });
            emit NFTListed(msg.sender, nftContract, tokenId, price);
        }
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

    function cancelListings(
        address[] calldata nftContracts,
        uint256[] calldata tokenIds
    ) external whenNotPaused nonReentrant {
        uint len = nftContracts.length;
        require(len > 0 && len == tokenIds.length, "Array mismatch");
        uint256[] memory badIds = new uint256[](len);
        uint badCount;
        for (uint i = 0; i < len; i++) {
            bytes32 key = keccak256(
                abi.encodePacked(nftContracts[i], tokenIds[i])
            );
            Listing storage lst = listings[key];
            if (!lst.active || lst.seller != msg.sender) {
                badIds[badCount++] = tokenIds[i];
            }
        }
        if (badCount > 0) {
            revert NFTsNotListed(badIds, new uint256[](0));
        }
        for (uint i = 0; i < len; i++) {
            address nftContract = nftContracts[i];
            uint256 tokenId = tokenIds[i];
            bytes32 key = keccak256(abi.encodePacked(nftContract, tokenId));
            listings[key].active = false;
            IERC721(nftContract).transferFrom(
                address(this),
                msg.sender,
                tokenId
            );
            emit NFTDelisted(msg.sender, nftContract, tokenId);
        }
    }

    function buyNFTs(
        address[] calldata nftContracts,
        uint256[] calldata tokenIds
    ) external payable whenNotPaused nonReentrant {
        uint len = nftContracts.length;
        require(len > 0 && len == tokenIds.length, "Array mismatch");
        uint256 totalPrice;
        for (uint i = 0; i < len; i++) {
            bytes32 key = keccak256(
                abi.encodePacked(nftContracts[i], tokenIds[i])
            );
            Listing storage lst = listings[key];
            require(lst.active, "Not for sale");
            totalPrice += lst.price;
        }
        require(msg.value == totalPrice, "Wrong ETH amount");
        for (uint i = 0; i < len; i++) {
            address nftContract = nftContracts[i];
            uint256 tokenId = tokenIds[i];
            bytes32 key = keccak256(abi.encodePacked(nftContract, tokenId));
            Listing storage lst = listings[key];
            lst.active = false;
            (bool sent, ) = payable(lst.seller).call{value: lst.price}("");
            require(sent, "Payment failed");
            IERC721(nftContract).transferFrom(
                address(this),
                msg.sender,
                tokenId
            );
            emit NFTPurchased(msg.sender, nftContract, tokenId, lst.price);
        }
    }

    function validateOffers(
        address[] calldata offersC,
        uint256[] calldata offersT
    ) private view {
        for (uint256 i = 0; i < offersC.length; i++) {
            Listing storage lst = listings[_makeKey(offersC[i], offersT[i])];
            require(lst.active, "Offer not listed");
            require(lst.seller == msg.sender, "Not offer owner");
        }
    }

    function validateRequests(
        address[] calldata reqC,
        uint256[] calldata reqT
    ) private view {
        for (uint256 i = 0; i < reqC.length; i++) {
            Listing storage lst = listings[_makeKey(reqC[i], reqT[i])];
            require(lst.active, "Request not listed");
            require(lst.seller != msg.sender, "Request owned by you");
        }
    }

    function settleTrades(
        address[] calldata offersC,
        uint256[] calldata offersT,
        address[] calldata reqC,
        uint256[] calldata reqT,
        TradeVars memory v,
        uint256 extra
    ) private {
        for (uint256 i = 0; i < v.reqLen; i++) {
            bytes32 key = _makeKey(reqC[i], reqT[i]);
            Listing storage lst = listings[key];
            lst.active = false;
            uint256 pay = lst.price +
                (extra > 0 ? (lst.price * extra) / v.totalReq : 0);
            (bool ok, ) = payable(lst.seller).call{value: pay}("");
            require(ok, "Pay fail");
            IERC721(reqC[i]).transferFrom(address(this), msg.sender, reqT[i]);
        }
        for (uint256 i = 0; i < v.offLen; i++) {
            bytes32 key = _makeKey(offersC[i], offersT[i]);
            Listing storage lst = listings[key];
            lst.active = false; // already deactivated, but safe
            IERC721(offersC[i]).transferFrom(
                address(this),
                lst.seller,
                offersT[i]
            );
        }
    }

    function tradeNFTs(
        address[] calldata offeredContracts,
        uint256[] calldata offeredTokenIds,
        address[] calldata requestedContracts,
        uint256[] calldata requestedTokenIds
    ) external payable whenNotPaused nonReentrant {
        TradeVars memory v;
        v.offLen = offeredContracts.length;
        v.reqLen = requestedContracts.length;
        require(v.offLen > 0 && v.reqLen > 0, "Empty arrays");
        require(
            v.offLen == offeredTokenIds.length &&
                v.reqLen == requestedTokenIds.length,
            "Array mismatch"
        );

        validateOffers(offeredContracts, offeredTokenIds);
        validateRequests(requestedContracts, requestedTokenIds);

        for (uint256 i = 0; i < v.offLen; i++) {
            Listing storage lst = listings[
                _makeKey(offeredContracts[i], offeredTokenIds[i])
            ];
            v.totalOff += lst.price;
        }
        for (uint256 i = 0; i < v.reqLen; i++) {
            Listing storage lst = listings[
                _makeKey(requestedContracts[i], requestedTokenIds[i])
            ];
            v.totalReq += lst.price;
        }

        uint256 extra = v.totalReq > v.totalOff ? v.totalReq - v.totalOff : 0;
        uint256 surplus = v.totalOff > v.totalReq ? v.totalOff - v.totalReq : 0;
        require(
            msg.value + _balances[msg.sender] >= extra,
            "Insufficient funds"
        );
        if (msg.value < extra) {
            _balances[msg.sender] -= (extra - msg.value);
        }

        settleTrades(
            offeredContracts,
            offeredTokenIds,
            requestedContracts,
            requestedTokenIds,
            v,
            extra
        );

        if (surplus > 0) {
            _balances[msg.sender] += surplus;
        }

        emit NFTsTraded(
            msg.sender,
            offeredContracts,
            offeredTokenIds,
            requestedContracts,
            requestedTokenIds,
            v.totalOff,
            v.totalReq,
            extra
        );
    }
}
