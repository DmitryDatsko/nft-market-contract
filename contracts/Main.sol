// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {Ownable} from "./Ownable.sol";
import {Pausable} from "./Pausable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

contract Main is Ownable, Pausable, ReentrancyGuard, ERC721Holder {
    uint16 private constant maxNftAmount = 10;

    struct Listing {
        uint256 id;
        address nftContract;
        uint256 tokenId;
        address payable seller;
        uint256 price;
        bool isSold;
        bool isActive;
    }

    struct Trade {
        Peer from;
        Peer to;
        uint256[] listingIds;
        bool isActive;
    }

    struct Peer {
        address user;
        uint256[] tokenIds;
        address[] nftContracts;
    }

    struct CreateListingRequest {
        address contractAddress;
        uint256 tokenId;
        uint256 price;
    }

    uint256 private _nextListingId;
    uint256 private _nextTradeId;
    mapping(uint256 => Listing) public listings;
    mapping(uint256 => Trade) public trades;

    event ListingCreated(
        uint256 indexed id,
        address indexed nftContract,
        uint256 indexed tokenId,
        address seller,
        uint256 price
    );
    event ListingSold(uint256 indexed id, address indexed buyer);
    event ListingRemoved(uint256 indexed id, address indexed owner);
    event TradeCreated(
        uint256 tradeId,
        address indexed from,
        address indexed to,
        uint256[] listingIds
    );
    event TradeAccepted(uint256 tradeId);
    event TradeRejected(uint256 tradeId);
    event TradeCompleted(uint256 tradeId);

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
        CreateListingRequest[] calldata request
    ) external whenNotPaused nonReentrant {
        require(request.length > 0 && request.length <= maxNftAmount, "10 NFT per one call");

        for (uint256 i = 0; i < request.length; i++) {
            require(request[i].price > 0, "Price must be greater than zero");

            IERC721(request[i].contractAddress).safeTransferFrom(
                _msgSender(),
                address(this),
                request[i].tokenId
            );

            uint256 listingId = _nextListingId++;
            listings[listingId] = Listing({
                id: listingId,
                nftContract: request[i].contractAddress,
                tokenId: request[i].tokenId,
                seller: payable(_msgSender()),
                price: request[i].price,
                isSold: false,
                isActive: true
            });

            emit ListingCreated(
                listingId,
                request[i].contractAddress,
                request[i].tokenId,
                _msgSender(),
                request[i].price
            );
        }
    }

    function buyListing(
        uint256[] calldata listingIds
    ) external payable whenNotPaused nonReentrant {
        require(listingIds.length > 0 && listingIds.length <= maxNftAmount,"Invalid input");

        uint256 total = 0;
        address[] memory addrs = new address[](listingIds.length);
        uint256[] memory sums = new uint256[](listingIds.length);
        uint256 sellersCount = 0;

        for(uint256 i = 0; i < listingIds.length; i++) {
            for(uint256 j = i + 1; j < listingIds.length; j++){
                require(listingIds[i] != listingIds[j], "Duplicate listing id");
            }
            Listing storage lst = listings[listingIds[i]];
            require(lst.isActive && !lst.isSold && lst.seller != _msgSender(),
                "Invalid listing");

            total += lst.price;
        }
        require(msg.value == total, "Wrong total");

        for(uint256 i = 0; i < listingIds.length; i++) {
            Listing storage lst = listings[listingIds[i]];
            lst.isSold = true;
            lst.isActive = false;
        }

        for(uint256 i = 0; i < listingIds.length; i++) {
            Listing storage lst = listings[listingIds[i]];
            IERC721(lst.nftContract).safeTransferFrom(address(this), _msgSender(), lst.tokenId);

            bool found = false;
            for(uint256 k = 0; k < sellersCount; k++){
                if(addrs[k] == lst.seller){
                    sums[k] += lst.price;
                    found = true;
                    break;
                }
            }
            if (!found){
                addrs[sellersCount] = lst.seller;
                sums[sellersCount] = lst.price;
                sellersCount++;
            }

            emit ListingSold(listingIds[i], _msgSender());
        }

        for(uint256 k = 0; k < sellersCount; k++){
            (bool sent, ) = payable(addrs[k]).call{value: sums[k]}("");
            require(sent, "Failed to send Ether");
        }
    }

    function removeListing(
        uint256 listingId
    ) external whenNotPaused nonReentrant {
        Listing storage lst = listings[listingId];
        
        require(lst.isActive, "Listing is not active");
        require(!lst.isSold, "Already sold");
        require(lst.seller == _msgSender(), "Only owner can remove from listing");
        require(IERC721(lst.nftContract).ownerOf(lst.tokenId) == address(this), "Contract not owner of token");

        IERC721(lst.nftContract).safeTransferFrom(
            address(this),
            _msgSender(),
            lst.tokenId
        );

        lst.isActive = false;

        emit ListingRemoved(listingId, _msgSender());
    }

    function removeListingByTrade(
        uint256 listingId
    ) internal whenNotPaused{
        Listing storage lst = listings[listingId];

        lst.isActive = false;

        emit ListingRemoved(listingId, _msgSender());
    }

    function createTrade(
        address to,
        uint256[] calldata tokenIdsFrom,
        address[] calldata nftContractsFrom,
        uint256[] calldata listingIdsTo
    ) external whenNotPaused returns (uint256) {
        require(
            to != _msgSender(), "Can't offer trade for yourself"
        );
        require(
            nftContractsFrom.length == tokenIdsFrom.length,
            "Bad calldata, not equal length of from arrays"
        );
        require(
            tokenIdsFrom.length <= maxNftAmount,
            "Max 10 NFT for one side per trade"
        );
        require(
            listingIdsTo.length <= maxNftAmount,
            "Max 10 NFT for one side per trade"
        );
        
        for(uint256 i = 0; i < tokenIdsFrom.length; i++){
            require(
                IERC721(nftContractsFrom[i]).ownerOf(tokenIdsFrom[i]) == _msgSender(),
                "Offered nft are not owned by msgSender"
            );
        }

        uint256[] memory tokenIdsTo = new uint256[](listingIdsTo.length);
        address[] memory nftContractsTo = new address[](listingIdsTo.length);
        address firstSeller = listings[listingIdsTo[0]].seller;

        for (uint256 i = 0; i < listingIdsTo.length; i++) {
            Listing storage lst = listings[listingIdsTo[i]];

            require(lst.isActive, "Listing not active");
            require(lst.seller == firstSeller, "Offered trade for multi-sellers");
            require(!lst.isSold, "Listing already sold");
            require(lst.seller == to, "Listing doesn't belong to 'to'");

            tokenIdsTo[i] = lst.tokenId;
            nftContractsTo[i] = lst.nftContract;
        }

        uint256 tradeId = _nextTradeId++;

        Trade storage tr = trades[tradeId];
        tr.isActive = true;

        for (uint256 i = 0; i < listingIdsTo.length; ++i) {
            tr.listingIds.push(listingIdsTo[i]);
        }

        tr.from.user = _msgSender();

        for (uint256 i = 0; i < tokenIdsFrom.length; ++i) {
            tr.from.tokenIds.push(tokenIdsFrom[i]);
        }

        for (uint256 i = 0; i < nftContractsFrom.length; ++i) {
            tr.from.nftContracts.push(nftContractsFrom[i]);
        }

        for (uint256 i = 0; i < listingIdsTo.length; ++i) {
            Listing storage lst = listings[listingIdsTo[i]];
            tr.to.tokenIds.push(lst.tokenId);
            tr.to.nftContracts.push(lst.nftContract);
        }
        tr.to.user = to;

        emit TradeCreated(tradeId, _msgSender(), to, listingIdsTo);
        return tradeId;
    }

    function acceptTrade(
        uint256 tradeId
        ) external whenNotPaused nonReentrant {
        Trade storage trade = trades[tradeId];
        require(trade.isActive, "Trade is no longer active");
        require(
            trade.to.user == _msgSender(),
            "Only the recipient can accept the trade"
        );

        for(uint256 i = 0; i < trade.from.tokenIds.length; i++){
            address nftContract = trade.from.nftContracts[i];
            uint256 tokenId = trade.from.tokenIds[i];
            IERC721 token = IERC721(nftContract);

            require(token.ownerOf(tokenId) == trade.from.user, 
                "Offered NFT are not owned by offerer");

            require(
                token.getApproved(tokenId) == address(this) || token.isApprovedForAll(trade.from.user, address(this)),
                "Marketplace not approved to transfer offered NFT"
            );
        }

        for (uint256 i = 0; i < trade.listingIds.length; i++) {
            Listing storage lst = listings[trade.listingIds[i]];

            require(lst.isActive, "Listing not active");
            require(!lst.isSold, "Listing already sold");
            require(lst.seller == trade.to.user, "Listing doesn't belong to 'to'");
        }

        trade.isActive = false;
        emit TradeAccepted(tradeId);
        
        for (uint256 i = 0; i < trade.from.tokenIds.length; i++) {
            IERC721(trade.from.nftContracts[i]).safeTransferFrom(
                trade.from.user,
                trade.to.user,
                trade.from.tokenIds[i]
            );
        }

        for (uint256 i = 0; i < trade.to.tokenIds.length; i++) {
            IERC721(trade.to.nftContracts[i]).safeTransferFrom(
                address(this),
                trade.from.user,
                trade.to.tokenIds[i]
            );

            removeListingByTrade(trade.listingIds[i]);
        }

        emit TradeCompleted(tradeId);
    }

    function rejectTrade(uint256 tradeId) external whenNotPaused {
        Trade storage trade = trades[tradeId];
        require(trade.isActive, "Trade is no longer active");
        require(
            trade.to.user == _msgSender() || trade.from.user == _msgSender(),
            "Only peers can reject the trade"
        );

        trade.isActive = false;
        emit TradeRejected(tradeId);
    }
}
