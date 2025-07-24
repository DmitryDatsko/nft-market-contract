// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {Ownable} from "./Ownable.sol";
import {Pausable} from "./Pausable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Main is Ownable, Pausable, ReentrancyGuard {
    struct Listing {
        uint256 id;
        address nftContract;
        uint256 tokenId;
        address payable seller;
        uint256 price;
        bool isSold;
    }

    uint256 private _nextListingId;
    mapping(uint256 => Listing) public listings;

    event ListingCreated(
        uint256 indexed id,
        address indexed nftContract,
        uint256 indexed tokenId,
        address seller,
        uint256 price
    );
    event ListingSold(uint256 indexed id, address indexed buyer);

    constructor() Ownable(_msgSender()) {}

    receive() external payable {}

    fallback() external payable {}

    function pause() external onlyOwner whenNotPaused {
        _pause();
    }

    function unpause() external onlyOwner whenPaused {
        _unpause();
    }

    function _getContractBalance()
        internal
        view
        whenNotPaused
        returns (uint256)
    {
        return address(this).balance;
    }

    function createListing(
        address nftContract,
        uint256 tokenId,
        uint256 price
    ) external whenNotPaused nonReentrant {
        require(price > 0, "Price must be > 0");

        IERC721(nftContract).transferFrom(msg.sender, address(this), tokenId);

        uint256 listingId = _nextListingId++;
        listings[listingId] = Listing({
            id: listingId,
            nftContract: nftContract,
            tokenId: tokenId,
            seller: payable(msg.sender),
            price: price,
            isSold: false
        });

        emit ListingCreated(listingId, nftContract, tokenId, msg.sender, price);
    }

    function buyListing(
        uint256 listingId
    ) external payable whenNotPaused nonReentrant {
        Listing storage lst = listings[listingId];
        require(!lst.isSold, "Already sold");
        require(msg.value == lst.price, "Wrong amount");

        lst.isSold = true;

        (bool sent, ) = lst.seller.call{value: msg.value}("");
        require(sent, "Failed to send Ether");

        IERC721(lst.nftContract).transferFrom(
            address(this),
            msg.sender,
            lst.tokenId
        );

        emit ListingSold(listingId, msg.sender);
    }
}
